#!/usr/bin/env bash

set -euo pipefail

readonly output_dir="${1:-build/app/outputs/flutter-apk}"
readonly expected_certificate_sha256="${UTEXO_RELEASE_CERT_SHA256:-}"

fail() {
  printf 'Android release artifact check failed: %s\n' "$1" >&2
  exit 1
}

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

readonly apksigner="$(find_apksigner)"
[[ -n "${apksigner}" && -x "${apksigner}" ]] || fail "apksigner is required"

normalize_digest() {
  printf '%s' "$1" | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]'
}

verify_signature() {
  local apk_path="$1"
  local apk_entries="$2"
  local certificate_output
  local actual_digest
  local expected_digest

  if ! "${apksigner}" verify "${apk_path}" >/dev/null 2>&1; then
    if grep -aFq 'APK Sig Block 42' "${apk_path}" ||
      grep -Eq '^META-INF/[^/]+\.(RSA|DSA|EC|SF)$' <<<"${apk_entries}"; then
      fail "${apk_path} contains an invalid APK signature"
    fi
    [[ -z "${expected_certificate_sha256}" ]] ||
      fail "${apk_path} is unsigned but UTEXO_RELEASE_CERT_SHA256 is configured"
    printf 'Verified %s is an unsigned candidate artifact\n' "${apk_path}"
    return
  fi

  [[ -n "${expected_certificate_sha256}" ]] ||
    fail "${apk_path} is signed but no approved UTEXO_RELEASE_CERT_SHA256 is configured"
  certificate_output="$("${apksigner}" verify --print-certs "${apk_path}")" ||
    fail "could not inspect the signature on ${apk_path}"
  actual_digest="$({
    printf '%s\n' "${certificate_output}" |
      sed -nE \
        's/^(Signer #[0-9]+|V[0-9.]+ Signer): certificate SHA-256 digest: (.*)$/\2/p'
  })"
  [[ -n "${actual_digest}" && "${actual_digest}" != *$'\n'* ]] ||
    fail "${apk_path} must have exactly one inspectable signing certificate"
  actual_digest="$(normalize_digest "${actual_digest}")"
  expected_digest="$(normalize_digest "${expected_certificate_sha256}")"
  [[ "${actual_digest}" == "${expected_digest}" ]] ||
    fail "${apk_path} signing certificate does not match UTEXO_RELEASE_CERT_SHA256"
  printf 'Verified %s uses the approved release certificate\n' "${apk_path}"
}

verify_apk() {
  local apk_path="$1"
  local expected_abi="$2"
  local archive_entries
  local packaged_abis

  [[ -f "${apk_path}" ]] || fail "missing ${apk_path}"

  archive_entries="$(unzip -Z1 "${apk_path}")" ||
    fail "could not inspect ${apk_path}"
  packaged_abis="$(
    printf '%s\n' "${archive_entries}" |
      sed -nE 's#^lib/([^/]+)/.*#\1#p' |
      LC_ALL=C sort -u
  )"

  [[ "${packaged_abis}" == "${expected_abi}" ]] ||
    fail "${apk_path} contains ABIs [${packaged_abis//$'\n'/, }] instead of only ${expected_abi}"

  local required_library
  for required_library in libapp.so libflutter.so librgb_lightning_node.so; do
    printf '%s\n' "${archive_entries}" |
      grep -Fxq "lib/${expected_abi}/${required_library}" ||
      fail "${apk_path} is missing lib/${expected_abi}/${required_library}"
  done

  verify_signature "${apk_path}" "${archive_entries}"
  ./scripts/verify-android-native-libraries.sh "${apk_path}" lib apk
  printf 'Verified %s (%s only)\n' "${apk_path}" "${expected_abi}"
}

verify_apk "${output_dir}/app-arm64-v8a-release.apk" "arm64-v8a"
verify_apk "${output_dir}/app-armeabi-v7a-release.apk" "armeabi-v7a"
verify_apk "${output_dir}/app-x86_64-release.apk" "x86_64"

printf 'All Android release APK slices are ABI-safe.\n'
