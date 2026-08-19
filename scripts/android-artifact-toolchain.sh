#!/usr/bin/env bash

_utexo_artifact_script_directory="${BASH_SOURCE[0]%/*}"
[[ "${_utexo_artifact_script_directory}" != "${BASH_SOURCE[0]}" ]] ||
  _utexo_artifact_script_directory=.
source "${_utexo_artifact_script_directory}/bounded-command.sh"

# Resolves release-verification tools from exact repository/AGP declarations.
utexo_resolve_android_artifact_toolchain() {
  local repository output key candidate value match_count
  repository="${UTEXO_BOUNDED_ROOT}"
  output="$(
    cd "${repository}"
    utexo_capture_inspector \
      "${UTEXO_BOUNDED_DART}" \
      --disable-dart-dev \
      tool/resolve_android_artifact_toolchain.dart
  )" || return 1

  for key in \
    UTEXO_AGP_VERSION \
    UTEXO_BUILD_TOOLS_VERSION \
    UTEXO_NDK_VERSION \
    UTEXO_AAPT2_PROTO_VERSION \
    UTEXO_BUNDLETOOL_VERSION \
    UTEXO_PROTOBUF_VERSION \
    UTEXO_AAPT2_PROTO_JAR \
    UTEXO_BUNDLETOOL_JAR \
    UTEXO_PROTOBUF_JAR \
    UTEXO_APKSIGNER \
    UTEXO_AAPT2 \
    UTEXO_ZIPALIGN \
    UTEXO_LLVM_READELF; do
    match_count=0
    value=''
    while IFS= read -r candidate || [[ -n "${candidate}" ]]; do
      if [[ "${candidate}" == "${key}="* ]]; then
        match_count=$((match_count + 1))
        value="${candidate#*=}"
      fi
    done <<<"${output}"
    if ((match_count != 1)) || [[ -z "${value}" ]]; then
      printf 'Android artifact toolchain resolution failed for %s.\n' \
        "${key}" >&2
      return 1
    fi
    printf -v "${key}" '%s' "${value}"
    export "${key}"
  done
}
