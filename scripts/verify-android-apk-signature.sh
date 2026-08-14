#!/usr/bin/env bash

set -euo pipefail

readonly apk_path="${1:-}"
readonly expected_certificate_sha256="${UTEXO_RELEASE_CERT_SHA256:-}"

fail() {
  printf 'Android APK signature check failed: %s\n' "$1" >&2
  exit 1
}

[[ -n "${apk_path}" && -f "${apk_path}" ]] ||
  fail "pass an existing APK path"
command -v unzip >/dev/null 2>&1 || fail "unzip is required"

find_apksigner() {
  if command -v apksigner >/dev/null 2>&1; then
    command -v apksigner
    return
  fi

  local sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -z "${sdk_root}" && -f android/local.properties ]]; then
    sdk_root="$(sed -n 's/^sdk\.dir=//p' android/local.properties | tail -n 1)"
  fi
  if [[ -n "${sdk_root}" ]]; then
    find "${sdk_root}/build-tools" -type f -name apksigner -print 2>/dev/null |
      LC_ALL=C sort |
      tail -n 1
  fi
}

normalize_digest() {
  printf '%s' "$1" | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]'
}

readonly apksigner="$(find_apksigner)"
[[ -n "${apksigner}" && -x "${apksigner}" ]] || fail "apksigner is required"

archive_entries="$(unzip -Z1 "${apk_path}")" ||
  fail "could not inspect ${apk_path}"
signature_output=''
if ! signature_output="$(
  "${apksigner}" verify --verbose --print-certs "${apk_path}" 2>&1
)"; then
  if grep -aFq 'APK Sig Block 42' "${apk_path}" ||
    grep -Eq '^META-INF/[^/]+\.(RSA|DSA|EC|SF)$' <<<"${archive_entries}"; then
    fail "${apk_path} contains an invalid APK signature"
  fi
  [[ -z "${expected_certificate_sha256}" ]] ||
    fail "${apk_path} is unsigned but UTEXO_RELEASE_CERT_SHA256 is configured"
  printf 'Verified %s is an unsigned candidate artifact\n' "${apk_path}"
  exit 0
fi

[[ -n "${expected_certificate_sha256}" ]] ||
  fail "${apk_path} is signed but no approved UTEXO_RELEASE_CERT_SHA256 is configured"
if ! grep -Eq \
  '^Verified using v(2|3) scheme \(APK Signature Scheme v(2|3)(\.1)?\): true$' \
  <<<"${signature_output}"; then
  fail "${apk_path} must use APK Signature Scheme v2 or v3"
fi

actual_digest="$({
  printf '%s\n' "${signature_output}" |
    sed -nE \
      's/^(Signer #[0-9]+|V[0-9.]+ Signer): certificate SHA-256 digest: (.*)$/\2/p'
})"
[[ -n "${actual_digest}" && "${actual_digest}" != *$'\n'* ]] ||
  fail "${apk_path} must have exactly one inspectable signing certificate"
actual_digest="$(normalize_digest "${actual_digest}")"
expected_digest="$(normalize_digest "${expected_certificate_sha256}")"
[[ "${actual_digest}" == "${expected_digest}" ]] ||
  fail "${apk_path} signing certificate does not match UTEXO_RELEASE_CERT_SHA256"
printf 'Verified %s uses v2/v3 and the approved release certificate\n' \
  "${apk_path}"
