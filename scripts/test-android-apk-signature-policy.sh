#!/usr/bin/env bash

set -euo pipefail

script_directory="${BASH_SOURCE[0]%/*}"
[[ "${script_directory}" != "${BASH_SOURCE[0]}" ]] || script_directory=.
readonly root="$(cd "${script_directory}/.." && pwd -P)"
cd "${root}"
source "${root}/scripts/android-artifact-toolchain.sh"
utexo_resolve_android_artifact_toolchain

readonly source_apk="${1:-build/app/outputs/flutter-apk/app-debug.apk}"
readonly debug_keystore="${ANDROID_TEST_KEYSTORE:-${HOME}/.android/debug.keystore}"

fail() {
  printf 'Android APK signature policy test failed: %s\n' "$1" >&2
  exit 1
}

[[ -f "${source_apk}" ]] || fail "missing source APK: ${source_apk}"
[[ -f "${debug_keystore}" ]] || fail "missing disposable test keystore"
keytool_bin="$(command -v keytool)" || fail "keytool is required"
mktemp_bin="$(command -v mktemp)" || fail "mktemp is required"
rm_bin="$(command -v rm)" || fail "rm is required"
cp_bin="$(command -v cp)" || fail "cp is required"
readonly keytool_bin mktemp_bin rm_bin cp_bin
readonly apksigner="${UTEXO_APKSIGNER}"

fixtures="$(
  utexo_capture_quick \
    "${mktemp_bin}" -d "${TMPDIR:-/tmp}/utexo-apk-signatures.XXXXXX"
)" || fail "could not create an isolated signature fixture directory"
readonly fixtures
cleanup() {
  local status=$?
  local cleanup_status=0
  trap - EXIT HUP INT TERM
  utexo_run_quick "${rm_bin}" -rf -- "${fixtures}" >/dev/null 2>&1 ||
    cleanup_status=1
  ((status != 0)) && exit "${status}"
  exit "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
utexo_run_quick "${cp_bin}" "${source_apk}" "${fixtures}/v1.apk"
utexo_run_quick "${cp_bin}" "${source_apk}" "${fixtures}/v2.apk"

sign_fixture() {
  local apk="$1"
  local v2="$2"
  utexo_run_inspector "${apksigner}" sign \
    --ks "${debug_keystore}" \
    --ks-key-alias androiddebugkey \
    --ks-pass pass:android \
    --key-pass pass:android \
    --v1-signing-enabled true \
    --v2-signing-enabled "${v2}" \
    --v3-signing-enabled false \
    --v4-signing-enabled false \
    "${apk}"
}

sign_fixture "${fixtures}/v1.apk" false
sign_fixture "${fixtures}/v2.apk" true

keytool_output="$(
  utexo_capture_inspector "${keytool_bin}" -list -v \
    -keystore "${debug_keystore}" \
    -alias androiddebugkey \
    -storepass android
)" || fail "could not read test certificate"
approved_digest=''
approved_digest_count=0
while IFS= read -r keytool_line || [[ -n "${keytool_line}" ]]; do
  if [[ "${keytool_line}" =~ ^[[:space:]]*SHA256:[[:space:]](.+)$ ]]; then
    approved_digest="${BASH_REMATCH[1]}"
    approved_digest_count=$((approved_digest_count + 1))
  fi
done <<<"${keytool_output}"
((approved_digest_count == 1)) || fail "could not read one test certificate"
readonly approved_digest

if (
  export UTEXO_RELEASE_CERT_SHA256="${approved_digest}"
  utexo_run_inspector \
    "${root}/scripts/verify-android-apk-signature.sh" \
    "${fixtures}/v1.apk" >/dev/null 2>&1
); then
  fail "v1-only APK unexpectedly passed"
fi
(
  export UTEXO_RELEASE_CERT_SHA256="${approved_digest}"
  utexo_run_inspector \
    "${root}/scripts/verify-android-apk-signature.sh" \
    "${fixtures}/v2.apk"
)

if utexo_run_inspector \
  "${root}/scripts/verify-android-apk-signature.sh" \
  "${fixtures}/v2.apk" >/dev/null 2>&1; then
  fail "signed APK without an approved fingerprint unexpectedly passed"
fi
if (
  export UTEXO_RELEASE_CERT_SHA256="${approved_digest}00"
  utexo_run_inspector \
    "${root}/scripts/verify-android-apk-signature.sh" \
    "${fixtures}/v2.apk" >/dev/null 2>&1
); then
  fail "mismatched certificate unexpectedly passed"
fi

printf 'Android APK v2/v3 signature policy fault matrix passed.\n'
