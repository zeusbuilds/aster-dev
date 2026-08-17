#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
command -v keytool >/dev/null 2>&1 || fail "keytool is required"
readonly apksigner="${UTEXO_APKSIGNER}"

readonly fixtures="$(mktemp -d "${TMPDIR:-/tmp}/utexo-apk-signatures.XXXXXX")"
trap 'rm -rf "${fixtures}"' EXIT
cp "${source_apk}" "${fixtures}/v1.apk"
cp "${source_apk}" "${fixtures}/v2.apk"

sign_fixture() {
  local apk="$1"
  local v2="$2"
  "${apksigner}" sign \
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

readonly approved_digest="$({
  keytool -list -v \
    -keystore "${debug_keystore}" \
    -alias androiddebugkey \
    -storepass android |
    sed -nE 's/^[[:space:]]*SHA256: (.*)$/\1/p'
})"
[[ -n "${approved_digest}" ]] || fail "could not read test certificate"

if UTEXO_RELEASE_CERT_SHA256="${approved_digest}" \
  ./scripts/verify-android-apk-signature.sh "${fixtures}/v1.apk" \
  >/dev/null 2>&1; then
  fail "v1-only APK unexpectedly passed"
fi
UTEXO_RELEASE_CERT_SHA256="${approved_digest}" \
  ./scripts/verify-android-apk-signature.sh "${fixtures}/v2.apk"

if ./scripts/verify-android-apk-signature.sh "${fixtures}/v2.apk" \
  >/dev/null 2>&1; then
  fail "signed APK without an approved fingerprint unexpectedly passed"
fi
if UTEXO_RELEASE_CERT_SHA256="${approved_digest}00" \
  ./scripts/verify-android-apk-signature.sh "${fixtures}/v2.apk" \
  >/dev/null 2>&1; then
  fail "mismatched certificate unexpectedly passed"
fi

printf 'Android APK v2/v3 signature policy fault matrix passed.\n'
