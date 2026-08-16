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

  /// Maximum visible-ASCII payload accepted by the Receive QR contract.
  ///
  /// The pinned QR encoder uses byte mode with error-correction level L. Its
  /// Version 40 ceiling is 2,953 bytes; visible ASCII makes bytes and Dart
  /// characters equivalent at this boundary.
  static const maximumQrPayloadCharacters = 2953;

  /// Maximum opaque native-identifier length accepted at app boundaries.
  static const maximumIdentifierCharacters = 1024;

  /// Whether [value] is bounded nonempty visible ASCII protocol data.
  static bool isEncodedValue(
    String value, {
    int maximumCharacters = maximumEncodedCharacters,
  }) {
    return _isVisibleAscii(value, maximumCharacters);
  }

  /// Whether [value] is safe and small enough for the Receive QR renderer.
  static bool isQrPayload(String value) {
    return _isVisibleAscii(value, maximumQrPayloadCharacters);
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
