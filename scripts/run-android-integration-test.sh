#!/usr/bin/env bash

set -euo pipefail

script_directory="${BASH_SOURCE[0]%/*}"
[[ "${script_directory}" != "${BASH_SOURCE[0]}" ]] || script_directory=.
readonly root="$(cd "${script_directory}/.." && pwd -P)"
readonly target="${1:-integration_test/wallet_storage_security_test.dart}"
readonly device_id="${2:-${ANDROID_DEVICE_ID:-}}"
readonly release_package="com.example.asterdev"
readonly test_package="${release_package}.debug"

cd "${root}"
source "${root}/scripts/bounded-command.sh"

fail() {
  printf 'Android integration test failed: %s\n' "$1" >&2
  exit 64
}

[[ "${target}" =~ ^integration_test/[A-Za-z0-9_]+\.dart$ ]] ||
  fail "target must be a Dart file under integration_test/"
[[ -f "${target}" ]] || fail "target does not exist: ${target}"
[[ -n "${device_id}" ]] ||
  fail "pass a device ID or set ANDROID_DEVICE_ID"
aster_bounded_boundary_available || fail "bounded command runner is unavailable"

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "${sdk_root}" && -f android/local.properties ]]; then
  while IFS= read -r property || [[ -n "${property}" ]]; do
    if [[ "${property}" == sdk.dir=* ]]; then
      sdk_root="${property#sdk.dir=}"
      sdk_root="${sdk_root%$'\r'}"
    fi
  done <android/local.properties
fi
readonly sdk_root
readonly adb="${sdk_root}/platform-tools/adb"
[[ -x "${adb}" ]] || fail "Android adb is unavailable"
aster_run_quick "${adb}" -s "${device_id}" get-state >/dev/null 2>&1 ||
  fail "device is not attached: ${device_id}"
source "${root}/scripts/android-package-state.sh"

package_path() {
  aster_android_package_paths "${adb}" "${device_id}" "$1"
}

release_path_before="$(package_path "${release_package}")" ||
  fail "could not inspect the release package before the integration run"
readonly release_path_before

aster_run_build fvm flutter pub get --enforce-lockfile

cleanup() {
  local command_status=$?
  local cleanup_status=0
  local release_path_after
  local test_path_after
  trap - EXIT
  set +e

  if ! aster_run_quick \
    "${adb}" -s "${device_id}" get-state >/dev/null 2>&1; then
    printf 'Android device detached before integration cleanup.\n' >&2
    cleanup_status=1
  else
    if ! test_path_after="$(package_path "${test_package}")"; then
      printf 'Could not inspect the debug package during cleanup.\n' >&2
      cleanup_status=1
    elif [[ -n "${test_path_after}" ]]; then
      aster_run_quick \
        "${adb}" -s "${device_id}" shell am force-stop \
        "${test_package}" >/dev/null || cleanup_status=1
    fi
    if ! release_path_after="$(package_path "${release_package}")"; then
      printf 'Could not inspect the release package during cleanup.\n' >&2
      cleanup_status=1
    elif [[ "${release_path_after}" != "${release_path_before}" ]]; then
      printf 'The release package changed during the integration run.\n' >&2
      cleanup_status=1
    fi
  fi

  if ((command_status != 0)); then
    exit "${command_status}"
  fi
  exit "${cleanup_status}"
}

trap cleanup EXIT
# Flutter does not account for the build-type suffix when stopping this run.
# Keep it alive so the EXIT owner can stop only the isolated debug identity.
set +e
aster_run_build fvm flutter drive --no-pub \
  --driver=test_driver/integration_test.dart \
  --target="${target}" \
  --keep-app-running \
  -d "${device_id}"
test_status=$?
set -e
((test_status == 0)) || exit "${test_status}"

release_path_after="$(package_path "${release_package}")" ||
  fail "could not inspect the release package after the integration run"
readonly release_path_after
[[ "${release_path_after}" == "${release_path_before}" ]] ||
  fail "the release package changed during the integration run"
test_path_after="$(package_path "${test_package}")" ||
  fail "could not inspect the debug package after the integration run"
readonly test_path_after
[[ -n "${test_path_after}" ]] ||
  fail "the isolated debug package was not installed"

readonly apk="build/app/outputs/flutter-apk/app-debug.apk"
[[ -f "${apk}" ]] || fail "Flutter did not produce ${apk}"
source "${root}/scripts/android-artifact-toolchain.sh"
aster_resolve_android_artifact_toolchain ||
  fail "the exact Android artifact toolchain is unavailable"
readonly built_package="$(
  aster_capture_inspector "${ASTER_AAPT2}" dump packagename "${apk}"
)"
[[ "${built_package}" == "${test_package}" ]] ||
  fail "debug APK uses ${built_package}, expected ${test_package}"

printf 'Android integration test preserved release identity and used %s.\n' \
  "${test_package}"
