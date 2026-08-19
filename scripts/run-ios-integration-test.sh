#!/usr/bin/env bash

set -euo pipefail

script_directory="${BASH_SOURCE[0]%/*}"
[[ "${script_directory}" != "${BASH_SOURCE[0]}" ]] || script_directory=.
readonly root="$(cd "${script_directory}/.." && pwd -P)"
readonly target="${1:-integration_test/wallet_storage_security_test.dart}"
readonly simulator_id="${2:-${IOS_SIMULATOR_ID:-}}"
readonly release_bundle="com.example.asterdev"
readonly test_bundle="${release_bundle}.debug"
readonly ruby_bundle_path="${BUNDLE_PATH:-${root}/.bundle}"
readonly bundler_version="4.0.10"

export BUNDLE_PATH="${ruby_bundle_path}"
export BUNDLE_FROZEN=true

cd "${root}"
source "${root}/scripts/bounded-command.sh"

fail() {
  printf 'iOS integration test failed: %s\n' "$1" >&2
  exit 64
}

[[ "${target}" =~ ^integration_test/[A-Za-z0-9_]+\.dart$ ]] ||
  fail "target must be a Dart file under integration_test/"
[[ -f "${target}" ]] || fail "target does not exist: ${target}"
[[ -n "${simulator_id}" ]] ||
  fail "pass a simulator UDID or set IOS_SIMULATOR_ID"
utexo_bounded_boundary_available || fail "bounded command runner is unavailable"
xcrun_bin="$(command -v xcrun)" || fail "xcrun is unavailable"
bundle_bin="$(command -v bundle)" || fail "Bundler is unavailable"
plutil_bin="$(command -v plutil)" || fail "plutil is unavailable"
mktemp_bin="$(command -v mktemp)" || fail "mktemp is unavailable"
rm_bin="$(command -v rm)" || fail "rm is unavailable"
readonly xcrun_bin bundle_bin plutil_bin mktemp_bin rm_bin
[[ "$(utexo_capture_quick "${bundle_bin}" --version)" == \
  "${bundler_version}" ]] ||
  fail "Bundler ${bundler_version} is required"
utexo_run_quick "${bundle_bin}" check >/dev/null 2>&1 ||
  fail "locked CocoaPods gems are unavailable; run make ios-dependencies"
utexo_run_quick \
  "${xcrun_bin}" simctl getenv "${simulator_id}" SIMULATOR_UDID \
  >/dev/null 2>&1 ||
  fail "simulator is not booted: ${simulator_id}"

bundle_path() {
  local bundle_identifier="$1"
  local escaped_identifier
  [[ "${bundle_identifier}" =~ ^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+$ ]] ||
    return 1
  escaped_identifier="${bundle_identifier//./\\.}"
  utexo_capture_quick \
    /bin/bash --noprofile --norc -p -c '
      set -euo pipefail
      readonly rm_command="$5"
      temporary_file="$("$4" "${TMPDIR:-/tmp}/utexo-simapps.XXXXXX")"
      cleanup() {
        local status=$?
        trap - EXIT HUP INT TERM
        "${rm_command}" -f -- "${temporary_file}" >/dev/null 2>&1 || {
          ((status != 0)) || status=70
        }
        exit "${status}"
      }
      trap cleanup EXIT
      trap "exit 129" HUP
      trap "exit 130" INT
      trap "exit 143" TERM
      "$1" simctl listapps "$2" >"${temporary_file}"
      "$3" -lint "${temporary_file}" >/dev/null
      if path="$(
        "$3" -extract "$6.Path" raw "${temporary_file}" 2>/dev/null
      )"; then
        [[ -n "${path}" && "${path}" != *$'\''\n'\''* ]] || exit 65
        printf "%s\n" "${path}"
        exit 0
      fi
      if "$3" -type "$6" "${temporary_file}" >/dev/null 2>&1; then
        exit 65
      fi
    ' utexo-ios-bundle-path \
    "${xcrun_bin}" \
    "${simulator_id}" \
    "${plutil_bin}" \
    "${mktemp_bin}" \
    "${rm_bin}" \
    "${escaped_identifier}"
}

release_path_before="$(bundle_path "${release_bundle}")" ||
  fail "could not inspect the release bundle before the integration run"
readonly release_path_before

utexo_run_build \
  "${bundle_bin}" exec fvm flutter pub get --enforce-lockfile

restore_flutter_target() {
  local test_status=$?
  local restore_status
  local restored_app="${root}/build/ios/iphonesimulator/Runner.app"
  trap - EXIT
  set +e
  utexo_run_build \
    "${bundle_bin}" exec fvm flutter build ios --simulator --debug --no-pub
  restore_status=$?
  if ((restore_status == 0)); then
    utexo_run_quick \
      "${xcrun_bin}" simctl install "${simulator_id}" "${restored_app}"
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
utexo_run_build \
  "${bundle_bin}" exec fvm flutter test --no-pub \
  "${target}" -d "${simulator_id}"

release_path_after="$(bundle_path "${release_bundle}")" ||
  fail "could not inspect the release bundle after the integration run"
readonly release_path_after
[[ "${release_path_after}" == "${release_path_before}" ]] ||
  fail "the release bundle changed during the integration run"

readonly built_test_app="${root}/build/ios/iphonesimulator/Runner.app"
[[ -d "${built_test_app}" ]] || fail "the built integration app is missing"
readonly built_test_bundle="$(
  utexo_capture_quick \
    "${plutil_bin}" -extract CFBundleIdentifier raw -- \
    "${built_test_app}/Info.plist"
)"
[[ "${built_test_bundle}" == "${test_bundle}" ]] ||
  fail "the built integration app has the wrong bundle identity"
utexo_run_quick \
  "${xcrun_bin}" simctl install "${simulator_id}" "${built_test_app}"

test_path_after="$(bundle_path "${test_bundle}")" ||
  fail "could not inspect the installed debug bundle"
readonly test_path_after
[[ -n "${test_path_after}" ]] ||
  fail "the isolated debug bundle was not installed"
release_path_after_install="$(bundle_path "${release_bundle}")" ||
  fail "could not inspect the release bundle after debug installation"
readonly release_path_after_install
[[ "${release_path_after_install}" == "${release_path_before}" ]] ||
  fail "installing the debug proof artifact changed the release bundle"
printf 'iOS integration test preserved release identity and used %s.\n' \
  "${test_bundle}"
