#!/usr/bin/env bash

set -euo pipefail

script_directory="${BASH_SOURCE[0]%/*}"
[[ "${script_directory}" != "${BASH_SOURCE[0]}" ]] || script_directory=.
readonly root="$(cd "${script_directory}/.." && pwd -P)"
cd "${root}"
source "${root}/scripts/android-artifact-toolchain.sh"
utexo_resolve_android_artifact_toolchain

readonly archive_path="${1:-}"
readonly native_root="${2:-}"
readonly archive_kind="${3:-}"
readonly expected_abis="${4:-}"

fail() {
  printf 'Android native-library check failed: %s\n' "$1" >&2
  exit 1
}

[[ -n "${archive_path}" && -n "${native_root}" && -n "${archive_kind}" &&
  -n "${expected_abis}" ]] ||
  fail "usage: $0 <archive> <native-root> <apk|aab> <expected-abis-csv>"
[[ "${archive_kind}" == "apk" || "${archive_kind}" == "aab" ]] ||
  fail "archive kind must be apk or aab"
if [[ "${archive_kind}" == "apk" ]]; then
  [[ "${native_root}" == "lib" ]] || fail "APK native root must be lib"
else
  [[ "${native_root}" == "base/lib" ]] || fail "AAB native root must be base/lib"
fi
[[ -f "${archive_path}" ]] || fail "missing ${archive_path}"
java_bin="$(command -v java)" || fail "java is required"
mktemp_bin="$(command -v mktemp)" || fail "mktemp is required"
rm_bin="$(command -v rm)" || fail "rm is required"
find_bin="$(command -v find)" || fail "find is required"
sort_bin="$(command -v sort)" || fail "sort is required"
readonly java_bin mktemp_bin rm_bin find_bin sort_bin
readonly readelf_bin="${UTEXO_LLVM_READELF}"

if [[ "${archive_kind}" == "apk" ]]; then
  readonly zipalign_bin="${UTEXO_ZIPALIGN}"
  utexo_run_inspector \
    "${zipalign_bin}" -c -P 16 4 "${archive_path}" >/dev/null ||
    fail "${archive_path} does not use 16 KiB APK alignment"
  printf 'Verified %s uses 16 KiB APK alignment\n' "${archive_path}"
fi

temporary_directory="$(utexo_capture_quick "${mktemp_bin}" -d)" ||
  fail "could not create an isolated native-library directory"
readonly temporary_directory
cleanup() {
  local status=$?
  local cleanup_status=0
  trap - EXIT HUP INT TERM
  utexo_run_quick "${rm_bin}" -rf -- "${temporary_directory}" \
    >/dev/null 2>&1 || cleanup_status=1
  ((status != 0)) && exit "${status}"
  exit "${cleanup_status}"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

extraction_output="$({
  utexo_capture_inspector \
    "${java_bin}" scripts/AndroidNativeLibraryExtractor.java \
    "${archive_path}" \
    "${native_root}" \
    "${temporary_directory}" \
    "${expected_abis}"
})" ||
  fail "could not validate and extract native libraries from ${archive_path}"
readonly extraction_output
[[ "${extraction_output}" =~ ^EXTRACTED_NATIVE_LIBRARIES=([1-9][0-9]*)$ ]] ||
  fail "native-library extractor emitted an invalid result"
readonly extracted_library_count="${BASH_REMATCH[1]}"
readonly library_inventory="${temporary_directory}/.native-library-inventory"
if ! inventory_output="$(
  utexo_capture_inspector \
    /bin/bash --noprofile --norc -p -c '
      set -o pipefail
      "$1" "$3" -mindepth 2 -maxdepth 2 -type f -name "*.so" -print |
        LC_ALL=C "$2"
    ' utexo-native-library-inventory \
    "${find_bin}" \
    "${sort_bin}" \
    "${temporary_directory}"
)"; then
  fail "could not enumerate every extracted native library"
fi
printf '%s\n' "${inventory_output}" >"${library_inventory}"

library_count=0
while IFS= read -r library_path; do
  [[ -n "${library_path}" ]] ||
    fail "native-library inventory contains an empty path"
  library_count=$((library_count + 1))
  library_parent="${library_path%/*}"
  abi="${library_parent##*/}"
  library_name="${library_path##*/}"
  minimum_alignment=$((0x1000))
  if [[ "${abi}" == "arm64-v8a" || "${abi}" == "x86_64" ]]; then
    minimum_alignment=$((0x4000))
  fi

  program_headers="$(
    utexo_capture_inspector "${readelf_bin}" -lW "${library_path}"
  )" ||
    fail "could not inspect ELF headers for ${abi}/${library_name}"
  load_segments=''
  while IFS= read -r program_header || [[ -n "${program_header}" ]]; do
    read -r -a header_fields <<<"${program_header}"
    if ((${#header_fields[@]} >= 4)) &&
      [[ "${header_fields[0]}" == "LOAD" ]]; then
      last_header_index=$((${#header_fields[@]} - 1))
      load_segments+="${header_fields[1]} ${header_fields[2]} "
      load_segments+="${header_fields[${last_header_index}]}"$'\n'
    fi
  done <<<"${program_headers}"
  load_segments="${load_segments%$'\n'}"
  [[ -n "${load_segments}" ]] ||
    fail "${abi}/${library_name} has no inspectable ELF LOAD segments"

  while read -r offset virtual_address alignment; do
    for value in "${offset}" "${virtual_address}" "${alignment}"; do
      [[ "${value}" =~ ^0x[0-9a-fA-F]+$ ]] ||
        fail "${abi}/${library_name} has malformed LOAD metadata ${value}"
    done
    if ((alignment == 0 || (alignment & (alignment - 1)) != 0)); then
      fail "${abi}/${library_name} has non-power-of-two LOAD alignment ${alignment}"
    fi
    if (( alignment < minimum_alignment )); then
      fail "${abi}/${library_name} has ${alignment} LOAD alignment; ${minimum_alignment} bytes is required"
    fi
    if ((offset % alignment != virtual_address % alignment)); then
      fail "${abi}/${library_name} has incongruent LOAD offset/address for ${alignment} alignment"
    fi
  done <<<"${load_segments}"

  if [[ "${program_headers}" != *GNU_RELRO* ]]; then
    dynamic_headers="$(
      utexo_capture_inspector "${readelf_bin}" -dW "${library_path}"
    )" ||
      fail "could not inspect dynamic headers for ${abi}/${library_name}"
    if [[ "${dynamic_headers}" =~ \((REL|RELA|JMPREL|PLTREL)\) ]]; then
      fail "${abi}/${library_name} has dynamic relocations without GNU_RELRO"
    fi
  fi
done <"${library_inventory}"

((library_count == extracted_library_count)) ||
  fail "inspected ${library_count} of ${extracted_library_count} extracted native libraries"
printf 'Verified %s has compatible ELF alignment and RELRO policy for %d libraries\n' \
  "${archive_path}" "${library_count}"
