import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../../shared/formatting/bitcoin_unit.dart';
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
              '${remainder.toString().padLeft(precision, '0').replaceFirst(_trailingZeros, '')}';
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
}

/// Exact USD estimate used only when a truthful USD source is available.
abstract final class WalletUsdEstimate {
  /// Converts canonical route units to cents, rounded to the nearest cent.
  ///
  /// Bitcoin requires a real [bitcoinPriceCents]. RGB USDT uses its USD face
  /// denomination rather than claiming a live exchange-market price.
  static int? cents({
    required int units,
    required PaymentRoute route,
    int? bitcoinPriceCents,
  }) {
    if (units < 0 || units > WalletAmount.maxNativeUnits) {
      throw ArgumentError.value(units, 'units');
    }
    final (priceCents, precision) = switch (route.asset.kind) {
      WalletAssetKind.bitcoin => (
        bitcoinPriceCents,
        route.rail == PaymentRail.onchain ? 8 : 11,
      ),
      WalletAssetKind.usdt => (100, route.asset.precision),
    };
    if (priceCents == null || priceCents < 0) return null;
    final denominator = WalletAmountDisplayFormatter._powerOfTen(precision);
    final numerator = BigInt.from(units) * BigInt.from(priceCents);
    final rounded = (numerator + denominator ~/ BigInt.two) ~/ denominator;
    if (rounded > BigInt.from(WalletAmount.maxNativeUnits)) return null;
    return rounded.toInt();
  }

  /// Formats non-negative USD cents without converting through `double`.
  static String formatCents(int cents, {String? locale}) {
    if (cents < 0 || cents > WalletAmount.maxNativeUnits) {
      throw ArgumentError.value(cents, 'cents');
    }
    final integer = NumberFormat.decimalPattern(locale);
    final whole = cents ~/ 100;
    final fraction = cents.remainder(100).toString().padLeft(2, '0');
    return '\$${integer.format(whole)}.$fraction';
  }
}
