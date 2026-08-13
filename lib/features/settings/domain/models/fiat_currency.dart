import 'package:flutter/foundation.dart';

import '../../../../shared/formatting/fiat_currency_policy.dart';

/// Validated ISO 4217 currency metadata used by settings and fiat displays.
@immutable
final class FiatCurrency {
  FiatCurrency({
    required this.name,
    required this.symbol,
    required this.code,
    required this.countryCode,
  }) {
    if (name.trim() != name || name.isEmpty || name.length > 80) {
      throw const FormatException('Invalid currency name.');
    }
    if (symbol.trim() != symbol || symbol.isEmpty || symbol.length > 8) {
      throw const FormatException('Invalid currency symbol.');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
      throw const FormatException('Invalid ISO 4217 currency code.');
    }
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(countryCode)) {
      throw const FormatException('Invalid currency country code.');
    }
  }

  factory FiatCurrency.fromJson(Map<String, Object?> json) {
    return FiatCurrency(
      name: json['name'] as String,
      symbol: json['symbol'] as String,
      code: json['code'] as String,
      countryCode: json['countryCode'] as String,
    );
  }

  final String name;
  final String symbol;
  final String code;
  final String countryCode;

  /// ISO 4217 minor-unit precision used for exact integer fiat values.
  ///
  /// Codes not listed in the zero- or three-decimal groups use the standard
  /// two decimal places. The catalog accepts only ISO-shaped codes, while the
  /// market boundary separately limits which currencies can be quoted.
  int get minorUnitDigits => FiatCurrencyPolicy.minorUnitDigits(code);

  @override
  bool operator ==(Object other) =>
      other is FiatCurrency &&
      other.name == name &&
      other.symbol == symbol &&
      other.code == code &&
      other.countryCode == countryCode;

  @override
  int get hashCode => Object.hash(name, symbol, code, countryCode);
}
