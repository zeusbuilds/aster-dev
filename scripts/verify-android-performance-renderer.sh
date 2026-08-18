#!/usr/bin/env bash

set -euo pipefail

readonly adb="${1:-}"
readonly device_id="${2:-}"

fail() {
  printf 'Android performance renderer verification failed: %s\n' "$1" >&2
  exit 64
}

[[ -x "${adb}" ]] || fail "adb is unavailable: ${adb}"
[[ -n "${device_id}" ]] || fail "a device ID is required"

surface_dump="$(
  "${adb}" -s "${device_id}" shell dumpsys SurfaceFlinger 2>/dev/null
)" || fail "could not inspect SurfaceFlinger on ${device_id}"
readonly surface_dump
renderer_line="$(
  printf '%s\n' "${surface_dump}" |
    tr -d '\r' |
    grep -m 1 '^GLES:' || true
)"
readonly renderer_line
[[ -n "${renderer_line}" ]] ||
  fail "SurfaceFlinger did not report a GLES renderer"

renderer_normalized="$(
  printf '%s' "${renderer_line}" | LC_ALL=C tr '[:upper:]' '[:lower:]'
)"
readonly renderer_normalized
case "${renderer_normalized}" in
  *swiftshader* | *llvmpipe* | *lavapipe* | *softpipe* | *software\ rasterizer*)
    fail "software rendering is not valid performance evidence: ${renderer_line}"
    ;;
esac

printf 'Android performance renderer: %s\n' "${renderer_line#GLES: }"
