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

readonly maximum_diagnostic_bytes=$((4 * 1024 * 1024))
renderer_line="$(
  "${adb}" -s "${device_id}" shell dumpsys SurfaceFlinger 2>/dev/null |
    tr -d '\r' |
    LC_ALL=C awk -v maximum="${maximum_diagnostic_bytes}" '
      {
        consumed += length($0) + 1
        if (consumed > maximum) exit 65
        if (!found && $0 ~ /^GLES:/) {
          print
          found = 1
        }
      }
    '
)" || fail "could not inspect bounded SurfaceFlinger diagnostics on ${device_id}"
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
