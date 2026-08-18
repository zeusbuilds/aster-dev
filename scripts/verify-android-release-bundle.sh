#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${root}/scripts/android-artifact-toolchain.sh"
utexo_resolve_android_artifact_toolchain

readonly bundle_path="${1:-build/app/outputs/bundle/release/app-release.aab}"
readonly expected_certificate_sha256="${UTEXO_RELEASE_CERT_SHA256:-}"

fail() {
  printf 'Android release bundle check failed: %s\n' "$1" >&2
  exit 1
}

command -v unzip >/dev/null 2>&1 || fail "unzip is required"
command -v jarsigner >/dev/null 2>&1 || fail "jarsigner is required"
command -v keytool >/dev/null 2>&1 || fail "keytool is required"
command -v java >/dev/null 2>&1 || fail "java is required"
[[ -f "${bundle_path}" ]] || fail "missing ${bundle_path}"

fvm dart run tool/verify_android_release_identity.dart \
  --bundle "${bundle_path}" \
  --aapt2-proto "${UTEXO_AAPT2_PROTO_JAR}" \
  --protobuf "${UTEXO_PROTOBUF_JAR}" ||
  fail "${bundle_path} does not match committed release identity"

readonly archive_entries="$(unzip -Z1 "${bundle_path}")" ||
  fail "could not inspect ${bundle_path}"
readonly packaged_abis="$({
  printf '%s\n' "${archive_entries}" |
    sed -nE 's#^base/lib/([^/]+)/.*#\1#p' |
    LC_ALL=C sort -u
})"
readonly expected_abis=$'arm64-v8a\narmeabi-v7a\nx86_64'
[[ "${packaged_abis}" == "${expected_abis}" ]] ||
  fail "${bundle_path} has an unexpected ABI set [${packaged_abis//$'\n'/, }]"

for abi in arm64-v8a armeabi-v7a x86_64; do
  for library in libapp.so libflutter.so librgb_lightning_node.so; do
    printf '%s\n' "${archive_entries}" |
      grep -Fxq "base/lib/${abi}/${library}" ||
      fail "${bundle_path} is missing base/lib/${abi}/${library}"
  done
done

java --class-path "${UTEXO_BUNDLETOOL_JAR}:${UTEXO_PROTOBUF_JAR}" \
  scripts/BundleConfigInspector.java "${bundle_path}" ||
  fail "${bundle_path} does not request 16 KiB native-library page alignment"

./scripts/verify-android-native-libraries.sh "${bundle_path}" base/lib aab

normalize_digest() {
  printf '%s' "$1" | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]'
}

certificate_output="$(keytool -printcert -jarfile "${bundle_path}" 2>/dev/null)" ||
  fail "could not inspect the signature on ${bundle_path}"
actual_digest="$({
  printf '%s\n' "${certificate_output}" |
    sed -nE 's/^[[:space:]]*SHA256: (.*)$/\1/p'
})"

if [[ -z "${actual_digest}" ]]; then
  [[ -z "${expected_certificate_sha256}" ]] ||
    fail "${bundle_path} is unsigned but UTEXO_RELEASE_CERT_SHA256 is configured"
  printf 'Verified %s is an unsigned candidate bundle\n' "${bundle_path}"
else
  [[ -n "${expected_certificate_sha256}" ]] ||
    fail "${bundle_path} is signed but no approved UTEXO_RELEASE_CERT_SHA256 is configured"
  jarsigner -verify "${bundle_path}" >/dev/null 2>&1 ||
    fail "${bundle_path} has an invalid JAR signature"
  [[ "${actual_digest}" != *$'\n'* ]] ||
    fail "${bundle_path} must have exactly one inspectable signing certificate"
  [[ "$(normalize_digest "${actual_digest}")" == \
    "$(normalize_digest "${expected_certificate_sha256}")" ]] ||
    fail "${bundle_path} signing certificate does not match UTEXO_RELEASE_CERT_SHA256"
  printf 'Verified %s uses the approved release certificate\n' "${bundle_path}"
fi

printf 'Verified %s contains the complete ABI/native-library matrix.\n' "${bundle_path}"
