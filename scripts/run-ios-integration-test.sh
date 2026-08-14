#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly target="${1:-integration_test/wallet_storage_security_test.dart}"
readonly simulator_id="${2:-${IOS_SIMULATOR_ID:-}}"
readonly release_bundle="com.example.asterdev"
readonly test_bundle="${release_bundle}.debug"

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
xcrun simctl getenv "${simulator_id}" SIMULATOR_UDID >/dev/null 2>&1 ||
  fail "simulator is not booted: ${simulator_id}"

bundle_path() {
  xcrun simctl get_app_container "${simulator_id}" "$1" app 2>/dev/null || true
}

readonly release_path_before="$(bundle_path "${release_bundle}")"

restore_flutter_target() {
  local test_status=$?
  local restore_status
  trap - EXIT
  set +e
  fvm flutter build ios --simulator --debug --config-only
  restore_status=$?
  set -e

  if ((restore_status != 0)); then
    printf 'Failed to restore the ordinary iOS Flutter target.\n' >&2
  fi

  if ((test_status != 0)); then
    exit "${test_status}"
  fi
  exit "${restore_status}"
}

trap restore_flutter_target EXIT
fvm flutter test "${target}" -d "${simulator_id}"

readonly release_path_after="$(bundle_path "${release_bundle}")"
[[ "${release_path_after}" == "${release_path_before}" ]] ||
  fail "the release bundle changed during the integration run"
printf 'iOS integration test preserved release identity and used %s.\n' \
  "${test_bundle}"
