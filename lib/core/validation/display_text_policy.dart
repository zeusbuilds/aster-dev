/// Policy for bounded human-readable text that may be rendered in the UI.
///
/// Protocol identifiers have a stricter visible-ASCII contract. This policy
/// permits ordinary Unicode while rejecting controls, bidirectional state,
/// invisible separators, and default-ignorable characters that can make
/// persisted or native-derived labels deceptive.
abstract final class DisplayTextPolicy {
  /// Whether [value] is nonempty, trimmed, bounded, and safe to display.
  static bool isSafe(String value, {required int maximumCharacters}) {
    if (maximumCharacters <= 0 ||
        value.isEmpty ||
        value.length > maximumCharacters ||
        value != value.trim() ||
        _hasUnpairedSurrogate(value)) {
      return false;
    }
    return !value.runes.any(_isUnsafeCodePoint);
  }

  static bool _hasUnpairedSurrogate(String value) {
    final units = value.codeUnits;
    for (var index = 0; index < units.length; index += 1) {
      final unit = units[index];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (index + 1 >= units.length) return true;
        final low = units[index + 1];
        if (low < 0xdc00 || low > 0xdfff) return true;
        index += 1;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return true;
      }
    }
    return false;
  }

  static bool _isUnsafeCodePoint(int value) {
    return value <= 0x1f ||
        (value >= 0x7f && value <= 0x9f) ||
        value == 0xad ||
        value == 0x34f ||
        (value >= 0x600 && value <= 0x605) ||
        value == 0x61c ||
        value == 0x6dd ||
        value == 0x70f ||
        (value >= 0x890 && value <= 0x891) ||
        value == 0x8e2 ||
        (value >= 0x115f && value <= 0x1160) ||
        value == 0x1680 ||
        (value >= 0x17b4 && value <= 0x17b5) ||
        (value >= 0x180b && value <= 0x180e) ||
        (value >= 0x2000 && value <= 0x200f) ||
        (value >= 0x2028 && value <= 0x202e) ||
        value == 0x202f ||
        (value >= 0x205f && value <= 0x206f) ||
        value == 0x2800 ||
        value == 0x3000 ||
        value == 0x3164 ||
        (value >= 0xfdd0 && value <= 0xfdef) ||
        value == 0xfeff ||
        value == 0xffa0 ||
        (value >= 0xfff9 && value <= 0xfffb) ||
        value == 0x110bd ||
        value == 0x110cd ||
        (value >= 0x13430 && value <= 0x1343f) ||
        (value >= 0x1bca0 && value <= 0x1bca3) ||
        (value >= 0x1d173 && value <= 0x1d17a) ||
        (value & 0xffff) >= 0xfffe ||
        (value >= 0xe0000 && value <= 0xe007f);
  }
}
