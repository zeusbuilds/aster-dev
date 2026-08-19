#!/usr/bin/env bash

_aster_package_script_directory="${BASH_SOURCE[0]%/*}"
[[ "${_aster_package_script_directory}" != "${BASH_SOURCE[0]}" ]] ||
  _aster_package_script_directory=.
source "${_aster_package_script_directory}/bounded-command.sh"

# Prints the canonical installed paths for one Android package. An empty,
# successful result means the package is absent; every malformed or failed
# package-manager response remains a failure.
aster_android_package_paths() {
  (($# == 3)) || return 64
  local package_adb="$1"
  local package_device_id="$2"
  local package_name="$3"
  local normalized_paths

  [[ -x "${package_adb}" && -n "${package_device_id}" ]] || return 64
  [[ "${package_name}" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$ ]] ||
    return 64

  local awk_bin sort_bin
  awk_bin="$(command -v awk)" || return 69
  sort_bin="$(command -v sort)" || return 69
  normalized_paths="$(
    aster_bounded_capture \
      "${ASTER_QUICK_TIMEOUT_SECONDS}" \
      65536 \
      "${ASTER_QUICK_OUTPUT_BYTES}" \
      -- \
      /bin/bash --noprofile --norc -p -c '
        set -o pipefail
        "$1" -s "$2" shell pm path "$3" |
          LC_ALL=C "$4" '\''
        {
          consumed += length($0) + 1
          if (consumed > 65536) exit 65
          sub(/\r$/, "")
          if ($0 !~ /^package:\/[^[:cntrl:]]+$/) exit 66
          print
        }
      '\'' |
          LC_ALL=C "$5" -u
      ' aster-android-package-paths \
      "${package_adb}" \
      "${package_device_id}" \
      "${package_name}" \
      "${awk_bin}" \
      "${sort_bin}"
  )" || return

  if [[ -n "${normalized_paths}" ]]; then
    printf '%s\n' "${normalized_paths}"
  fi
  return 0
}
