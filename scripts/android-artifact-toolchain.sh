#!/usr/bin/env bash

# Resolves release-verification tools from exact repository/AGP declarations.
utexo_resolve_android_artifact_toolchain() {
  if [[ -n "${UTEXO_AAPT2_PROTO_JAR:-}" &&
    -n "${UTEXO_BUNDLETOOL_JAR:-}" &&
    -n "${UTEXO_PROTOBUF_JAR:-}" &&
    -n "${UTEXO_APKSIGNER:-}" &&
    -n "${UTEXO_AAPT2:-}" &&
    -n "${UTEXO_ZIPALIGN:-}" &&
    -n "${UTEXO_LLVM_READELF:-}" ]]; then
    return 0
  fi

  local script_root repository output key line value
  script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repository="$(cd "${script_root}/.." && pwd)"
  output="$(
    cd "${repository}"
    fvm dart run tool/resolve_android_artifact_toolchain.dart
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
    line="$(printf '%s\n' "${output}" | grep -E "^${key}=" || true)"
    if [[ -z "${line}" || "${line}" == *$'\n'* ]]; then
      printf 'Android artifact toolchain resolution failed for %s.\n' \
        "${key}" >&2
      return 1
    fi
    value="${line#*=}"
    printf -v "${key}" '%s' "${value}"
    export "${key}"
  done
}
