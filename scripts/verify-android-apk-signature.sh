#!/usr/bin/env bash

set -euo pipefail

script_directory="${BASH_SOURCE[0]%/*}"
[[ "${script_directory}" != "${BASH_SOURCE[0]}" ]] || script_directory=.
readonly root="$(cd "${script_directory}/.." && pwd -P)"
cd "${root}"
source "${root}/scripts/android-artifact-toolchain.sh"
utexo_resolve_android_artifact_toolchain

readonly apk_path="${1:-}"
readonly expected_certificate_sha256="${UTEXO_RELEASE_CERT_SHA256:-}"

fail() {
  printf 'Android APK signature check failed: %s\n' "$1" >&2
  exit 1
}

[[ -n "${apk_path}" && -f "${apk_path}" ]] ||
  fail "pass an existing APK path"
java_bin="$(command -v java)" || fail "java is required"
grep_bin="$(command -v grep)" || fail "grep is required"
readonly java_bin grep_bin

readonly apksigner="${UTEXO_APKSIGNER}"

signature_evidence="$(
  utexo_capture_inspector \
    "${java_bin}" scripts/AndroidJarSignatureInspector.java \
    --signature-evidence \
    "${apk_path}"
)" || fail "could not inspect ${apk_path} archive metadata"
[[ "${signature_evidence}" == "SIGNATURE_EVIDENCE" ||
  "${signature_evidence}" == "NO_SIGNATURE_EVIDENCE" ]] ||
  fail "${apk_path} emitted an unknown archive-signature result"

signature_output=''
if ! signature_output="$(
  utexo_capture_inspector \
    "${apksigner}" verify --verbose --print-certs "${apk_path}" 2>&1
)"; then
  if utexo_run_quick \
    "${grep_bin}" -aFq 'APK Sig Block 42' "${apk_path}" ||
    [[ "${signature_evidence}" == "SIGNATURE_EVIDENCE" ]]; then
    fail "${apk_path} contains an invalid APK signature"
  fi
  [[ -z "${expected_certificate_sha256}" ]] ||
    fail "${apk_path} is unsigned but UTEXO_RELEASE_CERT_SHA256 is configured"
  printf 'Verified %s is an unsigned candidate artifact\n' "${apk_path}"
  exit 0
fi

[[ -n "${expected_certificate_sha256}" ]] ||
  fail "${apk_path} is signed but no approved UTEXO_RELEASE_CERT_SHA256 is configured"
valid_scheme=0
while IFS= read -r signature_line || [[ -n "${signature_line}" ]]; do
  if [[ "${signature_line}" =~ ^Verified\ using\ v(2|3)\ scheme\ \(APK\ Signature\ Scheme\ v(2|3)(\.1)?\):\ true$ ]] &&
    [[ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
    valid_scheme=1
  fi
done <<<"${signature_output}"
if ((valid_scheme != 1)); then
  fail "${apk_path} must use APK Signature Scheme v2 or v3"
fi

actual_digest=''
actual_digest_count=0
while IFS= read -r signature_line || [[ -n "${signature_line}" ]]; do
  if [[ "${signature_line}" =~ ^(Signer\ \#[0-9]+|V[0-9.]+\ Signer):?[[:space:]]+certificate\ SHA-256\ digest:[[:space:]](.+)$ ]]; then
    actual_digest="${BASH_REMATCH[2]}"
    actual_digest_count=$((actual_digest_count + 1))
  fi
done <<<"${signature_output}"
((actual_digest_count == 1)) ||
  fail "${apk_path} must have exactly one inspectable signing certificate"
actual_digest="$(utexo_normalize_sha256 "${actual_digest}")" ||
  fail "${apk_path} emitted an invalid signing certificate digest"
expected_digest="$(
  utexo_normalize_sha256 "${expected_certificate_sha256}"
)" || fail "UTEXO_RELEASE_CERT_SHA256 is malformed"
[[ "${actual_digest}" == "${expected_digest}" ]] ||
  fail "${apk_path} signing certificate does not match UTEXO_RELEASE_CERT_SHA256"
printf 'Verified %s uses v2/v3 and the approved release certificate\n' \
  "${apk_path}"
