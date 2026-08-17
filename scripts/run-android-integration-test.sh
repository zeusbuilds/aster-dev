#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly target="${1:-integration_test/wallet_storage_security_test.dart}"
readonly device_id="${2:-${ANDROID_DEVICE_ID:-}}"
readonly release_package="com.example.asterdev"
readonly test_package="${release_package}.debug"

cd "${root}"

fail() {
  printf 'Android integration test failed: %s\n' "$1" >&2
  exit 64
}

[[ "${target}" =~ ^integration_test/[A-Za-z0-9_]+\.dart$ ]] ||
  fail "target must be a Dart file under integration_test/"
[[ -f "${target}" ]] || fail "target does not exist: ${target}"
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

package_path() {
  "${adb}" -s "${device_id}" shell pm path "$1" 2>/dev/null |
    tr -d '\r' |
    LC_ALL=C sort
}

readonly release_path_before="$(package_path "${release_package}")"

fvm flutter pub get --enforce-lockfile
set +e
fvm flutter drive --no-pub \
  --driver=test_driver/integration_test.dart \
  --target="${target}" \
  --keep-app-running \
  -d "${device_id}"
test_status=$?
set -e

# Flutter's Android project parser does not account for a build-type
# applicationIdSuffix when stopping a drive run. Keep the app running above,
# then stop only the known isolated test package ourselves. Never uninstall a
# package here: both release-candidate and developer debug state are durable.
"${adb}" -s "${device_id}" shell am force-stop "${test_package}" >/dev/null

readonly release_path_after="$(package_path "${release_package}")"
[[ "${release_path_after}" == "${release_path_before}" ]] ||
  fail "the release package changed during the integration run"
[[ -n "$(package_path "${test_package}")" ]] ||
  fail "the isolated debug package was not installed"

readonly apk="build/app/outputs/flutter-apk/app-debug.apk"
[[ -f "${apk}" ]] || fail "Flutter did not produce ${apk}"
source "${root}/scripts/android-artifact-toolchain.sh"
utexo_resolve_android_artifact_toolchain ||
  fail "the exact Android artifact toolchain is unavailable"
readonly built_package="$("${UTEXO_AAPT2}" dump packagename "${apk}")"
[[ "${built_package}" == "${test_package}" ]] ||
  fail "debug APK uses ${built_package}, expected ${test_package}"

((test_status == 0)) || exit "${test_status}"
printf 'Android integration test preserved release identity and used %s.\n' \
  "${test_package}"
