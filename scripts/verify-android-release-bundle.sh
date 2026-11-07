#!/usr/bin/env bash

set -euo pipefail

script_directory="${BASH_SOURCE[0]%/*}"
[[ "${script_directory}" != "${BASH_SOURCE[0]}" ]] || script_directory=.
readonly root="$(cd "${script_directory}/.." && pwd -P)"
cd "${root}"
source "${root}/scripts/android-artifact-toolchain.sh"
aster_resolve_android_artifact_toolchain

readonly bundle_path="${1:-build/app/outputs/bundle/release/app-release.aab}"
readonly expected_certificate_sha256="${ASTER_RELEASE_CERT_SHA256:-}"
temporary_directory=""
rm_bin=''

cleanup() {
  local status=$?
  local cleanup_status=0
  trap - EXIT HUP INT TERM
  if [[ -n "${temporary_directory}" && -n "${rm_bin}" ]] &&
    ! aster_run_quick \
      "${rm_bin}" -rf -- "${temporary_directory}" >/dev/null 2>&1; then
    printf 'Android release bundle cleanup failed: %s\n' "${temporary_directory}" >&2
    cleanup_status=1
  fi
  ((status != 0)) && exit "${status}"
  exit "${cleanup_status}"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
  printf 'Android release bundle check failed: %s\n' "$1" >&2
  exit 1
}

java_bin="$(command -v java)" || fail "java is required"
mktemp_bin="$(command -v mktemp)" || fail "mktemp is required"
rm_bin="$(command -v rm)" || fail "rm is required"
readonly java_bin mktemp_bin rm_bin
[[ -f "${bundle_path}" ]] || fail "missing ${bundle_path}"
aster_run_inspector \
  "${ASTER_BOUNDED_DART}" --disable-dart-dev \
  tool/verify_release_artifact.dart \
  --kind android-bundle \
  --file "${bundle_path}" ||
  fail "${bundle_path} exceeds the release artifact budget or is unsafe"
temporary_directory="$(
  aster_capture_quick \
    "${mktemp_bin}" -d "${TMPDIR:-/tmp}/aster-aab-config.XXXXXX"
)" ||
  fail "could not create an isolated bundle-inspection directory"
readonly temporary_directory
readonly bundle_config_path="${temporary_directory}/BundleConfig.pb"

aster_run_inspector \
  "${ASTER_BOUNDED_DART}" --disable-dart-dev \
  tool/verify_android_release_identity.dart \
  --bundle "${bundle_path}" \
  --aapt2-proto "${ASTER_AAPT2_PROTO_JAR}" \
  --protobuf "${ASTER_PROTOBUF_JAR}" ||
  fail "${bundle_path} does not match committed release identity"

aster_run_inspector \
  "${java_bin}" scripts/AndroidArchiveEntryExtractor.java \
  "${bundle_path}" \
  BundleConfig.pb \
  "${bundle_config_path}" \
  16777216 ||
  fail "${bundle_path} does not contain a safely bounded BundleConfig.pb"

aster_run_inspector \
  "${java_bin}" --class-path \
  "${ASTER_BUNDLETOOL_JAR}:${ASTER_PROTOBUF_JAR}" \
  scripts/BundleConfigInspector.java "${bundle_config_path}" ||
  fail "${bundle_path} does not request 16 KiB native-library page alignment"

aster_run_inspector \
  "${root}/scripts/verify-android-native-libraries.sh" \
  "${bundle_path}" \
  base/lib \
  aab \
  arm64-v8a,x86_64

signature_output="$(
  aster_capture_inspector \
    "${java_bin}" scripts/AndroidJarSignatureInspector.java "${bundle_path}"
)" || fail "${bundle_path} has incomplete or invalid JAR signing coverage"
readonly signature_output

case "${signature_output}" in
  UNSIGNED)
    [[ -z "${expected_certificate_sha256}" ]] ||
      fail "${bundle_path} is unsigned but ASTER_RELEASE_CERT_SHA256 is configured"
    printf 'Verified %s is an unsigned candidate bundle\n' "${bundle_path}"
    ;;
  SIGNED_SHA256=*)
    readonly actual_digest="${signature_output#SIGNED_SHA256=}"
    [[ "${actual_digest}" =~ ^[0-9a-f]{64}$ ]] ||
      fail "${bundle_path} emitted an invalid signing certificate identity"
    [[ -n "${expected_certificate_sha256}" ]] ||
      fail "${bundle_path} is signed but no approved ASTER_RELEASE_CERT_SHA256 is configured"
    normalized_actual_digest="$(aster_normalize_sha256 "${actual_digest}")" ||
      fail "${bundle_path} emitted an invalid signing certificate identity"
    normalized_expected_digest="$(
      aster_normalize_sha256 "${expected_certificate_sha256}"
    )" || fail "ASTER_RELEASE_CERT_SHA256 is malformed"
    [[ "${normalized_actual_digest}" == \
      "${normalized_expected_digest}" ]] ||
      fail "${bundle_path} signing certificate does not match ASTER_RELEASE_CERT_SHA256"
    printf 'Verified %s uses the approved release certificate\n' "${bundle_path}"
    ;;
  *)
    fail "${bundle_path} emitted an unknown JAR signature result"
    ;;
esac

printf 'Verified %s contains the complete ABI/native-library matrix.\n' "${bundle_path}"
