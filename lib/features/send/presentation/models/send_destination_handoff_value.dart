import 'package:flutter/foundation.dart';

/// One bounded, memory-only destination staged by the persistent Scan tab.
///
/// The value is consumed once after a selected Send target loads successfully.
/// It is never persisted, routed, logged, or included in [toString].
@immutable
final class SendDestinationHandoffValue {
  SendDestinationHandoffValue(String raw) : value = raw.trim() {
    if (value.isEmpty ||
        value.length > maximumCharacters ||
        _unsafeCharacters.hasMatch(value)) {
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

final _unsafeCharacters = RegExp(
  r'[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u070f\u180e'
  r'\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060-\u206f'
  r'\ufeff\ufff9-\ufffb]',
);
