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

verify_signature() {
  local apk_path="$1"

  ./scripts/verify-android-apk-signature.sh "${apk_path}"
}

verify_apk() {
  local apk_path="$1"
  local expected_abi="$2"
  [[ -f "${apk_path}" ]] || fail "missing ${apk_path}"

  fvm dart run tool/verify_android_release_identity.dart \
    --apk "${apk_path}" \
    --aapt2 "${UTEXO_AAPT2}" ||
    fail "${apk_path} does not match committed release identity"

  verify_signature "${apk_path}"
  ./scripts/verify-android-native-libraries.sh \
    "${apk_path}" \
    lib \
    apk \
    "${expected_abi}"
  printf 'Verified %s (%s only)\n' "${apk_path}" "${expected_abi}"
}

verify_apk "${output_dir}/app-arm64-v8a-release.apk" "arm64-v8a"
verify_apk "${output_dir}/app-armeabi-v7a-release.apk" "armeabi-v7a"
verify_apk "${output_dir}/app-x86_64-release.apk" "x86_64"

printf 'All Android release APK slices are ABI-safe.\n'
