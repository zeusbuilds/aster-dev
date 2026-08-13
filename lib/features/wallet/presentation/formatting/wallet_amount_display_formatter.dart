import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../../../shared/formatting/fiat_amount_formatter.dart';
import '../../domain/models/models.dart';

/// Numeric and unit spans for one exact wallet amount.
@immutable
final class FormattedWalletAmount {
  const FormattedWalletAmount({required this.numeric, required this.unit});

  final String numeric;
  final String unit;

  String get text => '$numeric $unit';
}

/// Formats canonical wallet units without floating-point conversion.
final class WalletAmountDisplayFormatter {
  WalletAmountDisplayFormatter({String? locale})
    : _integer = NumberFormat.decimalPattern(locale);

  final NumberFormat _integer;
  static const _inputCodec = WalletAmountInputCodec();

  FormattedWalletAmount format({
    required int units,
    required PaymentRoute route,
    required BitcoinUnit bitcoinUnit,
  }) {
    if (units < 0 || units > WalletAmount.maxNativeUnits) {
      throw ArgumentError.value(units, 'units');
    }
    final precision = _inputCodec.displayPrecision(route, bitcoinUnit);
    final scale = _powerOfTen(precision);
    final value = BigInt.from(units);
    final whole = value ~/ scale;
    final remainder = value.remainder(scale);
    final groupedWhole = _integer.format(whole.toInt());
    final numeric = remainder == BigInt.zero
        ? groupedWhole
        : '$groupedWhole${_integer.symbols.DECIMAL_SEP}'
              '${_localizeDigits(remainder.toString().padLeft(precision, '0').replaceFirst(_trailingZeros, ''))}';
    return FormattedWalletAmount(
      numeric: numeric,
      unit: route.asset.kind == WalletAssetKind.bitcoin
          ? bitcoinUnit.label
          : route.asset.symbol,
    );
  }

  static BigInt _powerOfTen(int exponent) {
    var value = BigInt.one;
    for (var index = 0; index < exponent; index += 1) {
      value *= BigInt.from(10);
    }
    return value;
  }

  static final _trailingZeros = RegExp(r'0+$');

  String _localizeDigits(String value) {
    final zero = _integer.symbols.ZERO_DIGIT.codeUnitAt(0);
    if (zero == 0x30) return value;
    return String.fromCharCodes(
      value.codeUnits.map((digit) => zero + digit - 0x30),
    );
  }
}

/// Exact fiat estimate used only when a truthful asset quote is available.
abstract final class WalletFiatEstimate {
  /// Converts canonical route units to fiat minor units with half-up rounding.
  static int? minorUnits({
    required int units,
    required PaymentRoute route,
    required int? assetPriceMinorUnits,
  }) {
    if (units < 0 || units > WalletAmount.maxNativeUnits) {
      throw ArgumentError.value(units, 'units');
    }
    final precision = switch (route.asset.kind) {
      WalletAssetKind.bitcoin => route.rail == PaymentRail.onchain ? 8 : 11,
      WalletAssetKind.usdt => route.asset.precision,
    };
    if (assetPriceMinorUnits == null || assetPriceMinorUnits <= 0) return null;
    final denominator = WalletAmountDisplayFormatter._powerOfTen(precision);
    final numerator = BigInt.from(units) * BigInt.from(assetPriceMinorUnits);
    final rounded = (numerator + denominator ~/ BigInt.two) ~/ denominator;
    if (rounded > BigInt.from(WalletAmount.maxNativeUnits)) return null;
    return rounded.toInt();
  }

  /// Formats exact fiat [minorUnits] without converting through `double`.
  static String formatMinorUnits({
    required int minorUnits,
    required String symbol,
    required String code,
    required int minorUnitDigits,
    String? locale,
  }) {
    if (minorUnits < 0 || minorUnits > WalletAmount.maxNativeUnits) {
      throw ArgumentError.value(minorUnits, 'minorUnits');
    }
    return FiatAmountFormatter(locale: locale).format(
      minorUnits: minorUnits,
      symbol: symbol,
      code: code,
      minorUnitDigits: minorUnitDigits,
    );
  }
}
