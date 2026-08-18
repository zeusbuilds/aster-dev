#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly target="${1:-integration_test/wallet_storage_security_test.dart}"
readonly simulator_id="${2:-${IOS_SIMULATOR_ID:-}}"
readonly release_bundle="com.example.asterdev"
readonly test_bundle="${release_bundle}.debug"
readonly ruby_bundle_path="${BUNDLE_PATH:-${root}/.bundle}"
readonly bundler_version="4.0.10"

export BUNDLE_PATH="${ruby_bundle_path}"
export BUNDLE_FROZEN=true

cd "${root}"

fail() {
  printf 'iOS integration test failed: %s\n' "$1" >&2
  exit 64
}

[[ "${target}" =~ ^integration_test/[A-Za-z0-9_]+\.dart$ ]] ||
  fail "target must be a Dart file under integration_test/"
[[ -f "${target}" ]] || fail "target does not exist: ${target}"
[[ -n "${simulator_id}" ]] ||
  fail "pass a simulator UDID or set IOS_SIMULATOR_ID"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is unavailable"
command -v bundle >/dev/null 2>&1 || fail "Bundler is unavailable"
command -v plutil >/dev/null 2>&1 || fail "plutil is unavailable"
[[ "$(bundle --version)" == "${bundler_version}" ]] ||
  fail "Bundler ${bundler_version} is required"
bundle check >/dev/null 2>&1 ||
  fail "locked CocoaPods gems are unavailable; run make ios-dependencies"
xcrun simctl getenv "${simulator_id}" SIMULATOR_UDID >/dev/null 2>&1 ||
  fail "simulator is not booted: ${simulator_id}"

bundle_path() {
  xcrun simctl get_app_container "${simulator_id}" "$1" app 2>/dev/null || true
}

readonly release_path_before="$(bundle_path "${release_bundle}")"

bundle exec fvm flutter pub get --enforce-lockfile

restore_flutter_target() {
  local test_status=$?
  local restore_status
  local restored_app="${root}/build/ios/iphonesimulator/Runner.app"
  trap - EXIT
  set +e
  bundle exec fvm flutter build ios --simulator --debug --no-pub
  restore_status=$?
  if ((restore_status == 0)); then
    xcrun simctl install "${simulator_id}" "${restored_app}"
    restore_status=$?
  fi
  set -e

  if ((restore_status != 0)); then
    printf 'Failed to restore the ordinary installed iOS app.\n' >&2
  fi

  if ((test_status != 0)); then
    exit "${test_status}"
  fi
  exit "${restore_status}"
}

trap restore_flutter_target EXIT
bundle exec fvm flutter test --no-pub "${target}" -d "${simulator_id}"

readonly release_path_after="$(bundle_path "${release_bundle}")"
[[ "${release_path_after}" == "${release_path_before}" ]] ||
  fail "the release bundle changed during the integration run"

readonly built_test_app="${root}/build/ios/iphonesimulator/Runner.app"
[[ -d "${built_test_app}" ]] || fail "the built integration app is missing"
readonly built_test_bundle="$(
  plutil -extract CFBundleIdentifier raw -- "${built_test_app}/Info.plist"
)"
[[ "${built_test_bundle}" == "${test_bundle}" ]] ||
  fail "the built integration app has the wrong bundle identity"
xcrun simctl install "${simulator_id}" "${built_test_app}"

readonly test_path_after="$(bundle_path "${test_bundle}")"
[[ -n "${test_path_after}" ]] ||
  fail "the isolated debug bundle was not installed"
[[ "$(bundle_path "${release_bundle}")" == "${release_path_before}" ]] ||
  fail "installing the debug proof artifact changed the release bundle"
printf 'iOS integration test preserved release identity and used %s.\n' \
  "${test_bundle}"
