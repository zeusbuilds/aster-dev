/// Low-level policy for bounded wire-protocol text.
///
/// Human display text must use its own Unicode-aware policy. This helper is
/// only for protocol values whose canonical representation is visible ASCII.
abstract final class ProtocolTextPolicy {
  /// Whether [value] is nonempty visible ASCII within [maximumCharacters].
  static bool isVisibleAscii(String value, {required int maximumCharacters}) {
    if (maximumCharacters <= 0 ||
        value.isEmpty ||
        value.length > maximumCharacters) {
      return false;
    }
    return value.codeUnits.every((unit) => unit >= 0x21 && unit <= 0x7e);
  }
}
