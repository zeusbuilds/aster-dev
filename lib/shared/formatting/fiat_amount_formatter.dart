import 'package:intl/intl.dart';

import 'fiat_currency_policy.dart';

/// Formats exact non-negative fiat minor units without floating-point math.
final class FiatAmountFormatter {
  FiatAmountFormatter({String? locale})
    : _locale = locale,
      _integer = NumberFormat.decimalPattern(locale);

  final String? _locale;
  final NumberFormat _integer;

  /// Formats [minorUnits] with a curated [symbol] and ISO [minorUnitDigits].
  ///
  /// [wholeUnitsOnly] is for indicative market headlines, using integer
  /// half-up rounding. Balances and payment amounts retain the exact default.
  String format({
    required int minorUnits,
    required String symbol,
    required String code,
    required int minorUnitDigits,
    bool includeCurrencyCode = true,
    bool wholeUnitsOnly = false,
  }) {
    if (minorUnits < 0) {
      throw ArgumentError.value(minorUnits, 'minorUnits');
    }
    if (symbol.trim() != symbol || symbol.isEmpty || symbol.length > 8) {
      throw ArgumentError.value(symbol, 'symbol');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
      throw ArgumentError.value(code, 'code');
    }
    if (minorUnitDigits != FiatCurrencyPolicy.minorUnitDigits(code)) {
      throw ArgumentError.value(minorUnitDigits, 'minorUnitDigits');
    }

    final scale = BigInt.from(10).pow(minorUnitDigits);
    final value = BigInt.from(minorUnits);
    final whole =
        (value + (wholeUnitsOnly ? scale ~/ BigInt.two : BigInt.zero)) ~/ scale;
    final fraction = minorUnitDigits == 0 || wholeUnitsOnly
        ? ''
        : value.remainder(scale).toString().padLeft(minorUnitDigits, '0');
    final localizedNumber =
        '${_integer.format(whole.toInt())}'
        '${fraction.isEmpty ? '' : _integer.symbols.DECIMAL_SEP}'
        '${_localizeDigits(fraction)}';
    final currencyLayout = NumberFormat.currency(
      locale: _locale,
      name: code,
      symbol: symbol,
      decimalDigits: minorUnitDigits,
    );
    return '${currencyLayout.positivePrefix}$localizedNumber'
        '${currencyLayout.positiveSuffix}${includeCurrencyCode ? ' $code' : ''}';
  }

  String _localizeDigits(String value) {
    final zero = _integer.symbols.ZERO_DIGIT.codeUnitAt(0);
    if (zero == 0x30) return value;
    return String.fromCharCodes(
      value.codeUnits.map((digit) => zero + digit - 0x30),
    );
  }
}
