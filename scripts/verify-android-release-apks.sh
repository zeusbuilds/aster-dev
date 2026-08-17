#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${root}/scripts/android-artifact-toolchain.sh"
utexo_resolve_android_artifact_toolchain

readonly output_dir="${1:-build/app/outputs/flutter-apk}"

fail() {
  printf 'Android release artifact check failed: %s\n' "$1" >&2
  exit 1
}

command -v unzip >/dev/null 2>&1 || fail "unzip is required"

verify_signature() {
  local apk_path="$1"

  ./scripts/verify-android-apk-signature.sh "${apk_path}"
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

  verify_signature "${apk_path}"
  ./scripts/verify-android-native-libraries.sh "${apk_path}" lib apk
  printf 'Verified %s (%s only)\n' "${apk_path}" "${expected_abi}"
}

verify_apk "${output_dir}/app-arm64-v8a-release.apk" "arm64-v8a"
verify_apk "${output_dir}/app-armeabi-v7a-release.apk" "armeabi-v7a"
verify_apk "${output_dir}/app-x86_64-release.apk" "x86_64"

printf 'All Android release APK slices are ABI-safe.\n'
