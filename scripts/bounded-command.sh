#!/usr/bin/env bash

# Shared subprocess boundary for repository-owned shell entry points. The Dart
# VM is the small trusted launcher; every command it starts is placed in an
# owned process group and receives explicit time and output limits.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'bounded-command.sh must be sourced by an owned script.\n' >&2
  exit 64
fi
if declare -p ASTER_BOUNDED_COMMAND_LOADED >/dev/null 2>&1; then
  _aster_boundary_declaration="$(
    declare -p ASTER_BOUNDED_COMMAND_LOADED 2>/dev/null
  )"
  if [[ "${_aster_boundary_declaration}" == "declare -r "* ]]; then
    return 0
  fi
  unset ASTER_BOUNDED_COMMAND_LOADED
fi
readonly ASTER_BOUNDED_COMMAND_LOADED=1
_aster_bounded_source_directory="${BASH_SOURCE[0]%/*}"
[[ "${_aster_bounded_source_directory}" != "${BASH_SOURCE[0]}" ]] ||
  _aster_bounded_source_directory=.
readonly ASTER_BOUNDED_ROOT="$(
  cd "${_aster_bounded_source_directory}/.."
  pwd -P
)"
readonly ASTER_BOUNDED_FLUTTER_VERSION=3.47.0
readonly ASTER_BOUNDED_LOCAL_DART="${ASTER_BOUNDED_ROOT}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart"
_aster_bounded_dart="${ASTER_BOUNDED_LOCAL_DART}"
if [[ ! -x "${_aster_bounded_dart}" ]]; then
  _aster_bounded_flutter_root="${FLUTTER_ROOT:-}"
  _aster_bounded_flutter_metadata_file="${_aster_bounded_flutter_root}/bin/cache/flutter.version.json"
  _aster_bounded_flutter_version=''
  _aster_bounded_flutter_version_count=0
  _aster_bounded_flutter_version_pattern='^[[:space:]]*"frameworkVersion"[[:space:]]*:[[:space:]]*"([^"]+)"[[:space:]]*,[[:space:]]*$'
  if [[ "${_aster_bounded_flutter_root}" == /* &&
    -f "${_aster_bounded_flutter_metadata_file}" ]]; then
    while IFS= read -r _aster_bounded_flutter_metadata_line ||
      [[ -n "${_aster_bounded_flutter_metadata_line}" ]]; do
      if [[ "${_aster_bounded_flutter_metadata_line}" == *'"frameworkVersion"'* ]]; then
        _aster_bounded_flutter_version_count=$((_aster_bounded_flutter_version_count + 1))
        if [[ "${_aster_bounded_flutter_metadata_line}" =~ ${_aster_bounded_flutter_version_pattern} ]]; then
          _aster_bounded_flutter_version="${BASH_REMATCH[1]}"
        else
          _aster_bounded_flutter_version=''
        fi
      fi
    done <"${_aster_bounded_flutter_metadata_file}"
  fi
  if [[ "${_aster_bounded_flutter_version_count}" == 1 && "${_aster_bounded_flutter_version}" == "${ASTER_BOUNDED_FLUTTER_VERSION}" ]]; then
    _aster_bounded_dart="${_aster_bounded_flutter_root}/bin/cache/dart-sdk/bin/dart"
  else
    _aster_bounded_dart=''
  fi
fi
readonly ASTER_BOUNDED_DART="${_aster_bounded_dart}"
readonly ASTER_BOUNDED_RUNNER="${ASTER_BOUNDED_ROOT}/tool/run_bounded_command.dart"
unset _aster_bounded_dart
unset _aster_bounded_flutter_root
unset _aster_bounded_flutter_metadata_file
unset _aster_bounded_flutter_metadata_line
unset _aster_bounded_flutter_version
unset _aster_bounded_flutter_version_count
unset _aster_bounded_flutter_version_pattern

readonly ASTER_QUICK_TIMEOUT_SECONDS=120
readonly ASTER_INSPECT_TIMEOUT_SECONDS=600
readonly ASTER_BUILD_TIMEOUT_SECONDS=3600
readonly ASTER_QUICK_OUTPUT_BYTES=$((8 * 1024 * 1024))
readonly ASTER_INSPECT_OUTPUT_BYTES=$((16 * 1024 * 1024))
readonly ASTER_BUILD_OUTPUT_BYTES=$((64 * 1024 * 1024))

aster_bounded_boundary_available() {
  [[ -x "${ASTER_BOUNDED_DART}" && -f "${ASTER_BOUNDED_RUNNER}" ]]
}

aster_bounded_capture() {
  (($# >= 5)) || return 64
  local timeout_seconds="$1"
  local max_stdout_bytes="$2"
  local max_stderr_bytes="$3"
  shift 3
  [[ "$1" == "--" ]] || return 64
  shift
  aster_bounded_boundary_available || return 69
  "${ASTER_BOUNDED_DART}" --disable-dart-dev \
    "${ASTER_BOUNDED_RUNNER}" \
    --timeout-seconds "${timeout_seconds}" \
    --max-stdout-bytes "${max_stdout_bytes}" \
    --max-stderr-bytes "${max_stderr_bytes}" \
    -- "$@"
}

aster_bounded_stream() {
  (($# >= 5)) || return 64
  local timeout_seconds="$1"
  local max_stdout_bytes="$2"
  local max_stderr_bytes="$3"
  shift 3
  [[ "$1" == "--" ]] || return 64
  shift
  aster_bounded_boundary_available || return 69
  "${ASTER_BOUNDED_DART}" --disable-dart-dev \
    "${ASTER_BOUNDED_RUNNER}" \
    --timeout-seconds "${timeout_seconds}" \
    --max-stdout-bytes "${max_stdout_bytes}" \
    --max-stderr-bytes "${max_stderr_bytes}" \
    --stream-output \
    -- "$@"
}

aster_capture_quick() {
  aster_bounded_capture \
    "${ASTER_QUICK_TIMEOUT_SECONDS}" \
    "${ASTER_QUICK_OUTPUT_BYTES}" \
    "${ASTER_QUICK_OUTPUT_BYTES}" \
    -- "$@"
}

aster_run_quick() {
  aster_bounded_stream \
    "${ASTER_QUICK_TIMEOUT_SECONDS}" \
    "${ASTER_QUICK_OUTPUT_BYTES}" \
    "${ASTER_QUICK_OUTPUT_BYTES}" \
    -- "$@"
}

aster_capture_inspector() {
  aster_bounded_capture \
    "${ASTER_INSPECT_TIMEOUT_SECONDS}" \
    "${ASTER_INSPECT_OUTPUT_BYTES}" \
    "${ASTER_INSPECT_OUTPUT_BYTES}" \
    -- "$@"
}

aster_run_inspector() {
  aster_bounded_stream \
    "${ASTER_INSPECT_TIMEOUT_SECONDS}" \
    "${ASTER_INSPECT_OUTPUT_BYTES}" \
    "${ASTER_INSPECT_OUTPUT_BYTES}" \
    -- "$@"
}

aster_run_build() {
  aster_bounded_stream \
    "${ASTER_BUILD_TIMEOUT_SECONDS}" \
    "${ASTER_BUILD_OUTPUT_BYTES}" \
    "${ASTER_BUILD_OUTPUT_BYTES}" \
    -- "$@"
}

aster_normalize_sha256() {
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
