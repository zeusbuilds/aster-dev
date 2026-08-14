import '../../../../core/validation/validation.dart';

/// Validation policy for encoded wallet protocol data.
///
/// Bitcoin addresses and URIs, Lightning/RGB invoices, transaction IDs,
/// payment hashes, outpoints, and public keys are wire identifiers. They must
/// be visible ASCII so invisible Unicode cannot create a value that displays
/// differently from the bytes sent to or returned by the native wallet.
abstract final class WalletProtocolText {
  /// Maximum encoded payment-request length accepted at app boundaries.
  static const maximumEncodedCharacters = 8192;

  /// Maximum opaque native-identifier length accepted at app boundaries.
  static const maximumIdentifierCharacters = 1024;

  /// Whether [value] is bounded nonempty visible ASCII protocol data.
  static bool isEncodedValue(
    String value, {
    int maximumCharacters = maximumEncodedCharacters,
  }) {
    return _isVisibleAscii(value, maximumCharacters);
  }

  /// Whether [value] is a bounded nonempty visible ASCII identifier.
  static bool isIdentifier(
    String value, {
    int maximumCharacters = maximumIdentifierCharacters,
  }) {
    return _isVisibleAscii(value, maximumCharacters);
  }

  static bool _isVisibleAscii(String value, int maximumCharacters) {
    return ProtocolTextPolicy.isVisibleAscii(
      value,
      maximumCharacters: maximumCharacters,
    );
  }
}
