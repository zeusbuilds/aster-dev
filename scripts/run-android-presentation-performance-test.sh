#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly device_id="${1:-${ANDROID_DEVICE_ID:-}}"
readonly target="integration_test/presentation_performance_test.dart"
readonly release_package="com.example.asterdev"
readonly debug_package="${release_package}.debug"
readonly profile_package="${release_package}.profile"

cd "${root}"

fail() {
  printf 'Android presentation performance test failed: %s\n' "$1" >&2
  exit 64
}

[[ -n "${device_id}" ]] ||
  fail "pass a device ID or set ANDROID_DEVICE_ID"

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "${sdk_root}" && -f android/local.properties ]]; then
  sdk_root="$(sed -n 's/^sdk\.dir=//p' android/local.properties | tail -n 1)"
fi
readonly sdk_root
readonly adb="${sdk_root}/platform-tools/adb"
[[ -x "${adb}" ]] || fail "Android adb is unavailable"
"${adb}" -s "${device_id}" get-state >/dev/null 2>&1 ||
  fail "device is not attached: ${device_id}"
"${root}/scripts/verify-android-performance-renderer.sh" \
  "${adb}" "${device_id}"

package_path() {
  "${adb}" -s "${device_id}" shell pm path "$1" 2>/dev/null |
    tr -d '\r' |
    LC_ALL=C sort
}

clear_profile_state() {
  [[ -n "$(package_path "${profile_package}")" ]] || return 0
  "${adb}" -s "${device_id}" shell am force-stop \
    "${profile_package}" >/dev/null
  local output
  output="$(
    "${adb}" -s "${device_id}" shell pm clear "${profile_package}" |
      tr -d '\r'
  )" || return 1
  [[ "${output}" == "Success" ]]
}

readonly release_path_before="$(package_path "${release_package}")"
readonly debug_path_before="$(package_path "${debug_package}")"

cleanup() {
  local command_status=$?
  local cleanup_status=0
  local release_path_after debug_path_after
  trap - EXIT
  set +e

  clear_profile_state
  cleanup_status=$?
  release_path_after="$(package_path "${release_package}")"
  debug_path_after="$(package_path "${debug_package}")"
  if [[ "${release_path_after}" != "${release_path_before}" ]]; then
    printf 'The release package changed during the performance run.\n' >&2
    cleanup_status=1
  fi
  if [[ "${debug_path_after}" != "${debug_path_before}" ]]; then
    printf 'The debug package changed during the performance run.\n' >&2
    cleanup_status=1
  fi

  if ((command_status != 0)); then
    exit "${command_status}"
  fi
  exit "${cleanup_status}"
}

trap cleanup EXIT
clear_profile_state || fail "could not reset the isolated profile package"

fvm flutter pub get --enforce-lockfile
fvm flutter drive --no-pub \
  --no-dds \
  --driver=test_driver/integration_test.dart \
  --target="${target}" \
  --keep-app-running \
  --dart-define=UTEXO_ISOLATED_PROFILE_BENCHMARK=true \
  -d "${device_id}" \
  --profile

readonly profile_path_after="$(package_path "${profile_package}")"
[[ -n "${profile_path_after}" ]] ||
  fail "the isolated profile package was not installed"

readonly apk="build/app/outputs/flutter-apk/app-profile.apk"
[[ -f "${apk}" ]] || fail "Flutter did not produce ${apk}"
source "${root}/scripts/android-artifact-toolchain.sh"
utexo_resolve_android_artifact_toolchain ||
  fail "the exact Android artifact toolchain is unavailable"
readonly built_package="$("${UTEXO_AAPT2}" dump packagename "${apk}")"
[[ "${built_package}" == "${profile_package}" ]] ||
  fail "profile APK uses ${built_package}, expected ${profile_package}"

printf 'Android presentation performance test used isolated identity %s.\n' \
  "${profile_package}"
