#!/usr/bin/env bash

_aster_artifact_script_directory="${BASH_SOURCE[0]%/*}"
[[ "${_aster_artifact_script_directory}" != "${BASH_SOURCE[0]}" ]] ||
  _aster_artifact_script_directory=.
source "${_aster_artifact_script_directory}/bounded-command.sh"

# Resolves release-verification tools from exact repository/AGP declarations.
aster_resolve_android_artifact_toolchain() {
  local repository output key candidate value match_count
  repository="${ASTER_BOUNDED_ROOT}"
  output="$(
    cd "${repository}"
    aster_capture_inspector \
      "${ASTER_BOUNDED_DART}" \
      --disable-dart-dev \
      tool/resolve_android_artifact_toolchain.dart
  )" || return 1

  for key in \
    ASTER_AGP_VERSION \
    ASTER_BUILD_TOOLS_VERSION \
    ASTER_NDK_VERSION \
    ASTER_AAPT2_PROTO_VERSION \
    ASTER_BUNDLETOOL_VERSION \
    ASTER_PROTOBUF_VERSION \
    ASTER_AAPT2_PROTO_JAR \
    ASTER_BUNDLETOOL_JAR \
    ASTER_PROTOBUF_JAR \
    ASTER_APKSIGNER \
    ASTER_AAPT2 \
    ASTER_ZIPALIGN \
    ASTER_LLVM_READELF; do
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
