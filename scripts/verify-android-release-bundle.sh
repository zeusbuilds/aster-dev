#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${root}/scripts/android-artifact-toolchain.sh"
utexo_resolve_android_artifact_toolchain

readonly bundle_path="${1:-build/app/outputs/bundle/release/app-release.aab}"
readonly expected_certificate_sha256="${UTEXO_RELEASE_CERT_SHA256:-}"

fail() {
  printf 'Android release bundle check failed: %s\n' "$1" >&2
  exit 1
}

command -v java >/dev/null 2>&1 || fail "java is required"
[[ -f "${bundle_path}" ]] || fail "missing ${bundle_path}"

fvm dart run tool/verify_android_release_identity.dart \
  --bundle "${bundle_path}" \
  --aapt2-proto "${UTEXO_AAPT2_PROTO_JAR}" \
  --protobuf "${UTEXO_PROTOBUF_JAR}" ||
  fail "${bundle_path} does not match committed release identity"

java --class-path "${UTEXO_BUNDLETOOL_JAR}:${UTEXO_PROTOBUF_JAR}" \
  scripts/BundleConfigInspector.java "${bundle_path}" ||
  fail "${bundle_path} does not request 16 KiB native-library page alignment"

./scripts/verify-android-native-libraries.sh \
  "${bundle_path}" \
  base/lib \
  aab \
  arm64-v8a,armeabi-v7a,x86_64

normalize_digest() {
  printf '%s' "$1" | tr -d ':[:space:]' | tr '[:upper:]' '[:lower:]'
}

signature_output="$(
  java scripts/AndroidJarSignatureInspector.java "${bundle_path}"
)" || fail "${bundle_path} has incomplete or invalid JAR signing coverage"
readonly signature_output

case "${signature_output}" in
  UNSIGNED)
    [[ -z "${expected_certificate_sha256}" ]] ||
      fail "${bundle_path} is unsigned but UTEXO_RELEASE_CERT_SHA256 is configured"
    printf 'Verified %s is an unsigned candidate bundle\n' "${bundle_path}"
    ;;
  SIGNED_SHA256=*)
    readonly actual_digest="${signature_output#SIGNED_SHA256=}"
    [[ "${actual_digest}" =~ ^[0-9a-f]{64}$ ]] ||
      fail "${bundle_path} emitted an invalid signing certificate identity"
    [[ -n "${expected_certificate_sha256}" ]] ||
      fail "${bundle_path} is signed but no approved UTEXO_RELEASE_CERT_SHA256 is configured"
    [[ "$(normalize_digest "${actual_digest}")" == \
      "$(normalize_digest "${expected_certificate_sha256}")" ]] ||
      fail "${bundle_path} signing certificate does not match UTEXO_RELEASE_CERT_SHA256"
    printf 'Verified %s uses the approved release certificate\n' "${bundle_path}"
    ;;
  *)
    fail "${bundle_path} emitted an unknown JAR signature result"
    ;;
esac

printf 'Verified %s contains the complete ABI/native-library matrix.\n' "${bundle_path}"
