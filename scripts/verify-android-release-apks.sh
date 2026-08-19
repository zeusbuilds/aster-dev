#!/usr/bin/env bash

set -euo pipefail

script_directory="${BASH_SOURCE[0]%/*}"
[[ "${script_directory}" != "${BASH_SOURCE[0]}" ]] || script_directory=.
readonly root="$(cd "${script_directory}/.." && pwd -P)"
cd "${root}"
source "${root}/scripts/android-artifact-toolchain.sh"
aster_resolve_android_artifact_toolchain

readonly output_dir="${1:-build/app/outputs/flutter-apk}"

fail() {
  printf 'Android release artifact check failed: %s\n' "$1" >&2
  exit 1
}

verify_signature() {
  local apk_path="$1"

  aster_run_inspector \
    "${root}/scripts/verify-android-apk-signature.sh" "${apk_path}"
}

verify_apk() {
  local apk_path="$1"
  local expected_abi="$2"
  [[ -f "${apk_path}" ]] || fail "missing ${apk_path}"

  aster_run_inspector \
    "${ASTER_BOUNDED_DART}" --disable-dart-dev \
    tool/verify_android_release_identity.dart \
    --apk "${apk_path}" \
    --aapt2 "${ASTER_AAPT2}" ||
    fail "${apk_path} does not match committed release identity"

  verify_signature "${apk_path}"
  aster_run_inspector \
    "${root}/scripts/verify-android-native-libraries.sh" \
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
