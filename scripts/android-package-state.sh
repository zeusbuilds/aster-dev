#!/usr/bin/env bash

# Prints the canonical installed paths for one Android package. An empty,
# successful result means the package is absent; every malformed or failed
# package-manager response remains a failure.
utexo_android_package_paths() {
  (($# == 3)) || return 64
  local package_adb="$1"
  local package_device_id="$2"
  local package_name="$3"
  local normalized_paths

  [[ -x "${package_adb}" && -n "${package_device_id}" ]] || return 64
  [[ "${package_name}" =~ ^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$ ]] ||
    return 64

  normalized_paths="$({
    set -o pipefail
    "${package_adb}" -s "${package_device_id}" shell pm path \
      "${package_name}" 2>/dev/null |
      LC_ALL=C awk '
        {
          consumed += length($0) + 1
          if (consumed > 65536) exit 65
          sub(/\r$/, "")
          if ($0 !~ /^package:\/[^[:cntrl:]]+$/) exit 66
          print
        }
      ' |
      LC_ALL=C sort -u
  })" || return

  if [[ -n "${normalized_paths}" ]]; then
    printf '%s\n' "${normalized_paths}"
  fi
  return 0
}
