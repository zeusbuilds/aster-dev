import 'package:flutter/foundation.dart';

import '../../../wallet/domain/validation/validation.dart';

/// One bounded, memory-only destination staged by the persistent Scan tab.
///
/// The value is consumed once after a selected Send target loads successfully.
/// It is never persisted, routed, logged, or included in [toString].
@immutable
final class SendDestinationHandoffValue {
  SendDestinationHandoffValue(String raw) : value = raw.trim() {
    if (!WalletProtocolText.isEncodedValue(
      value,
      maximumCharacters: maximumCharacters,
    )) {
      throw const InvalidSendDestinationHandoffException();
    }
  }

  static const int maximumCharacters = 8192;

  final String value;

  @override
  String toString() => 'SendDestinationHandoffValue(redacted)';

  @override
  bool operator ==(Object other) =>
      other is SendDestinationHandoffValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Redacted marker for an unsafe cross-route destination handoff.
final class InvalidSendDestinationHandoffException implements Exception {
  const InvalidSendDestinationHandoffException();

  @override
  String toString() => 'InvalidSendDestinationHandoffException';
}
