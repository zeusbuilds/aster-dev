#!/usr/bin/env bash

set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${root}/scripts/android-artifact-toolchain.sh"
utexo_resolve_android_artifact_toolchain

readonly archive_path="${1:-}"
readonly native_root="${2:-}"
readonly archive_kind="${3:-}"

fail() {
  printf 'Android native-library check failed: %s\n' "$1" >&2
  exit 1
}

[[ -n "${archive_path}" && -n "${native_root}" && -n "${archive_kind}" ]] ||
  fail "usage: $0 <archive> <native-root> <apk|aab>"
[[ "${archive_kind}" == "apk" || "${archive_kind}" == "aab" ]] ||
  fail "archive kind must be apk or aab"
[[ -f "${archive_path}" ]] || fail "missing ${archive_path}"
command -v unzip >/dev/null 2>&1 || fail "unzip is required"
readonly readelf_bin="${UTEXO_LLVM_READELF}"

if [[ "${archive_kind}" == "apk" ]]; then
  readonly zipalign_bin="${UTEXO_ZIPALIGN}"
  "${zipalign_bin}" -c -P 16 4 "${archive_path}" >/dev/null ||
    fail "${archive_path} does not use 16 KiB APK alignment"
  printf 'Verified %s uses 16 KiB APK alignment\n' "${archive_path}"
fi

readonly temporary_directory="$(mktemp -d)"
cleanup() {
  find "${temporary_directory}" -depth -delete
}
trap cleanup EXIT

unzip -qq "${archive_path}" "${native_root}/*/*.so" \
  -d "${temporary_directory}" ||
  fail "could not extract native libraries from ${archive_path}"

library_count=0
while IFS= read -r library_path; do
  library_count=$((library_count + 1))
  abi="$(basename "$(dirname "${library_path}")")"
  library_name="$(basename "${library_path}")"
  minimum_alignment=$((0x1000))
  if [[ "${abi}" == "arm64-v8a" || "${abi}" == "x86_64" ]]; then
    minimum_alignment=$((0x4000))
  fi

  program_headers="$("${readelf_bin}" -lW "${library_path}")" ||
    fail "could not inspect ELF headers for ${abi}/${library_name}"
  load_alignments="$({
    printf '%s\n' "${program_headers}" |
      awk '$1 == "LOAD" {print $NF}'
  })"
  [[ -n "${load_alignments}" ]] ||
    fail "${abi}/${library_name} has no inspectable ELF LOAD segments"

  while IFS= read -r alignment; do
    [[ "${alignment}" =~ ^0x[0-9a-fA-F]+$ ]] ||
      fail "${abi}/${library_name} has malformed LOAD alignment ${alignment}"
    if (( alignment < minimum_alignment )); then
      fail "${abi}/${library_name} has ${alignment} LOAD alignment; ${minimum_alignment} bytes is required"
    fi
  done <<<"${load_alignments}"

  if ! grep -q 'GNU_RELRO' <<<"${program_headers}"; then
    dynamic_headers="$("${readelf_bin}" -dW "${library_path}")" ||
      fail "could not inspect dynamic headers for ${abi}/${library_name}"
    if grep -Eq '\((REL|RELA|JMPREL|PLTREL)\)' <<<"${dynamic_headers}"; then
      fail "${abi}/${library_name} has dynamic relocations without GNU_RELRO"
    fi
  fi
done < <(
  find "${temporary_directory}/${native_root}" -type f -name '*.so' -print |
    LC_ALL=C sort
)

((library_count > 0)) || fail "${archive_path} contains no native libraries"
printf 'Verified %s has compatible ELF alignment and RELRO policy for %d libraries\n' \
  "${archive_path}" "${library_count}"
