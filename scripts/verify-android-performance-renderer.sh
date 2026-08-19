#!/usr/bin/env bash

set -euo pipefail

script_directory="${BASH_SOURCE[0]%/*}"
[[ "${script_directory}" != "${BASH_SOURCE[0]}" ]] || script_directory=.
readonly root="$(cd "${script_directory}/.." && pwd -P)"
source "${root}/scripts/bounded-command.sh"

readonly adb="${1:-}"
readonly device_id="${2:-}"

fail() {
  printf 'Android performance renderer verification failed: %s\n' "$1" >&2
  exit 64
}

[[ -x "${adb}" ]] || fail "adb is unavailable: ${adb}"
[[ -n "${device_id}" ]] || fail "a device ID is required"
aster_bounded_boundary_available || fail "bounded command runner is unavailable"
awk_bin="$(command -v awk)" || fail "awk is unavailable"
readonly awk_bin

readonly maximum_diagnostic_bytes=$((4 * 1024 * 1024))
readonly maximum_renderer_output_bytes=4096
renderer_line="$(
  aster_bounded_capture \
    "${ASTER_QUICK_TIMEOUT_SECONDS}" \
    "${maximum_renderer_output_bytes}" \
    "${ASTER_QUICK_OUTPUT_BYTES}" \
    -- \
    /bin/bash --noprofile --norc -p -c '
      set -o pipefail
      "$1" -s "$2" shell dumpsys SurfaceFlinger |
        LC_ALL=C "$3" -v maximum="$4" '\''
          {
            consumed += length($0) + 1
            if (consumed > maximum) {
              overflow = 1
              exit 65
            }
            sub(/\r$/, "")
            if (!found && $0 ~ /^GLES:/) {
              print
              found = 1
            }
          }
          END {
            if (overflow) exit 65
          }
        '\''
    ' aster-android-performance-renderer \
    "${adb}" \
    "${device_id}" \
    "${awk_bin}" \
    "${maximum_diagnostic_bytes}"
)" || fail "could not inspect bounded SurfaceFlinger diagnostics on ${device_id}"
readonly renderer_line
[[ -n "${renderer_line}" ]] ||
  fail "SurfaceFlinger did not report a GLES renderer"

shopt -s nocasematch
case "${renderer_line}" in
  *swiftshader* | *llvmpipe* | *lavapipe* | *softpipe* | *software\ rasterizer*)
    fail "software rendering is not valid performance evidence: ${renderer_line}"
    ;;
esac
shopt -u nocasematch

printf 'Android performance renderer: %s\n' "${renderer_line#GLES: }"
