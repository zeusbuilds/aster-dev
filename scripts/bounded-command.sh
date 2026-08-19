#!/usr/bin/env bash

# Shared subprocess boundary for repository-owned shell entry points. The Dart
# VM is the small trusted launcher; every command it starts is placed in an
# owned process group and receives explicit time and output limits.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'bounded-command.sh must be sourced by an owned script.\n' >&2
  exit 64
fi
if declare -p UTEXO_BOUNDED_COMMAND_LOADED >/dev/null 2>&1; then
  _utexo_boundary_declaration="$(
    declare -p UTEXO_BOUNDED_COMMAND_LOADED 2>/dev/null
  )"
  if [[ "${_utexo_boundary_declaration}" == "declare -r "* ]]; then
    return 0
  fi
  unset UTEXO_BOUNDED_COMMAND_LOADED
fi
readonly UTEXO_BOUNDED_COMMAND_LOADED=1
_utexo_bounded_source_directory="${BASH_SOURCE[0]%/*}"
[[ "${_utexo_bounded_source_directory}" != "${BASH_SOURCE[0]}" ]] ||
  _utexo_bounded_source_directory=.
readonly UTEXO_BOUNDED_ROOT="$(
  cd "${_utexo_bounded_source_directory}/.."
  pwd -P
)"
readonly UTEXO_BOUNDED_DART="${UTEXO_BOUNDED_ROOT}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart"
readonly UTEXO_BOUNDED_RUNNER="${UTEXO_BOUNDED_ROOT}/tool/run_bounded_command.dart"

readonly UTEXO_QUICK_TIMEOUT_SECONDS=120
readonly UTEXO_INSPECT_TIMEOUT_SECONDS=600
readonly UTEXO_BUILD_TIMEOUT_SECONDS=3600
readonly UTEXO_QUICK_OUTPUT_BYTES=$((8 * 1024 * 1024))
readonly UTEXO_INSPECT_OUTPUT_BYTES=$((16 * 1024 * 1024))
readonly UTEXO_BUILD_OUTPUT_BYTES=$((64 * 1024 * 1024))

utexo_bounded_boundary_available() {
  [[ -x "${UTEXO_BOUNDED_DART}" && -f "${UTEXO_BOUNDED_RUNNER}" ]]
}

utexo_bounded_capture() {
  (($# >= 5)) || return 64
  local timeout_seconds="$1"
  local max_stdout_bytes="$2"
  local max_stderr_bytes="$3"
  shift 3
  [[ "$1" == "--" ]] || return 64
  shift
  utexo_bounded_boundary_available || return 69
  "${UTEXO_BOUNDED_DART}" --disable-dart-dev \
    "${UTEXO_BOUNDED_RUNNER}" \
    --timeout-seconds "${timeout_seconds}" \
    --max-stdout-bytes "${max_stdout_bytes}" \
    --max-stderr-bytes "${max_stderr_bytes}" \
    -- "$@"
}

utexo_bounded_stream() {
  (($# >= 5)) || return 64
  local timeout_seconds="$1"
  local max_stdout_bytes="$2"
  local max_stderr_bytes="$3"
  shift 3
  [[ "$1" == "--" ]] || return 64
  shift
  utexo_bounded_boundary_available || return 69
  "${UTEXO_BOUNDED_DART}" --disable-dart-dev \
    "${UTEXO_BOUNDED_RUNNER}" \
    --timeout-seconds "${timeout_seconds}" \
    --max-stdout-bytes "${max_stdout_bytes}" \
    --max-stderr-bytes "${max_stderr_bytes}" \
    --stream-output \
    -- "$@"
}

utexo_capture_quick() {
  utexo_bounded_capture \
    "${UTEXO_QUICK_TIMEOUT_SECONDS}" \
    "${UTEXO_QUICK_OUTPUT_BYTES}" \
    "${UTEXO_QUICK_OUTPUT_BYTES}" \
    -- "$@"
}

utexo_run_quick() {
  utexo_bounded_stream \
    "${UTEXO_QUICK_TIMEOUT_SECONDS}" \
    "${UTEXO_QUICK_OUTPUT_BYTES}" \
    "${UTEXO_QUICK_OUTPUT_BYTES}" \
    -- "$@"
}

utexo_capture_inspector() {
  utexo_bounded_capture \
    "${UTEXO_INSPECT_TIMEOUT_SECONDS}" \
    "${UTEXO_INSPECT_OUTPUT_BYTES}" \
    "${UTEXO_INSPECT_OUTPUT_BYTES}" \
    -- "$@"
}

utexo_run_inspector() {
  utexo_bounded_stream \
    "${UTEXO_INSPECT_TIMEOUT_SECONDS}" \
    "${UTEXO_INSPECT_OUTPUT_BYTES}" \
    "${UTEXO_INSPECT_OUTPUT_BYTES}" \
    -- "$@"
}

utexo_run_build() {
  utexo_bounded_stream \
    "${UTEXO_BUILD_TIMEOUT_SECONDS}" \
    "${UTEXO_BUILD_OUTPUT_BYTES}" \
    "${UTEXO_BUILD_OUTPUT_BYTES}" \
    -- "$@"
}

utexo_normalize_sha256() {
  (($# == 1)) || return 64
  local input="$1"
  local output=''
  local character
  local index
  for ((index = 0; index < ${#input}; index++)); do
    character="${input:index:1}"
    case "${character}" in
      [0-9a-fA-F]) output+="${character}" ;;
      : | ' ' | $'\t' | $'\r' | $'\n') ;;
      *) return 65 ;;
    esac
  done
  ((${#output} == 64)) || return 65
  output="${output//A/a}"
  output="${output//B/b}"
  output="${output//C/c}"
  output="${output//D/d}"
  output="${output//E/e}"
  output="${output//F/f}"
  printf '%s' "${output}"
}
