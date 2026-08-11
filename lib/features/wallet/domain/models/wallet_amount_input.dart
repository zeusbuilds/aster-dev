import 'package:flutter/foundation.dart';

import '../../../../shared/formatting/bitcoin_unit.dart';
import 'wallet_amount.dart';
import 'wallet_asset.dart';

/// Why a user-entered payment amount cannot currently be submitted.
enum WalletAmountInputIssue {
  empty,
  malformed,
  precisionExceeded,
  zero,
  outOfRange,
}

/// Exact parsing result for a user-entered decimal payment amount.
@immutable
final class WalletAmountInput {
  const WalletAmountInput._({
    required this.text,
    required this.units,
    required this.issue,
  });

  factory WalletAmountInput._valid({required String text, required int units}) {
    if (text.isEmpty || units <= 0 || units > WalletAmount.maxNativeUnits) {
      throw ArgumentError('A valid amount requires positive native units.');
    }
    return WalletAmountInput._(text: text, units: units, issue: null);
  }

  const WalletAmountInput._invalid({
    required String text,
    required WalletAmountInputIssue issue,
  }) : this._(text: text, units: null, issue: issue);

  final String text;
  final int? units;
  final WalletAmountInputIssue? issue;

  bool get isValid => units != null && issue == null;

  @override
  bool operator ==(Object other) =>
      other is WalletAmountInput &&
      other.text == text &&
      other.units == units &&
      other.issue == issue;

  @override
  int get hashCode => Object.hash(text, units, issue);
}

/// Converts display decimals to a route's canonical integer units.
///
/// Bitcoin on-chain amounts resolve to satoshis. Bitcoin Lightning amounts
/// resolve to millisatoshis. RGB amounts use the deployment-owned contract
/// precision for either rail. No monetary value passes through `double`.
final class WalletAmountInputCodec {
  const WalletAmountInputCodec();

  static const _maximumInputCharacters = 64;
  static final _decimalPattern = RegExp(r'^\d+(?:\.\d*)?$');
  static final _trailingZeros = RegExp(r'0+$');
  static final _powersOfTen = List<BigInt>.unmodifiable(
    List<BigInt>.generate(19, (exponent) {
      var value = BigInt.one;
      for (var index = 0; index < exponent; index += 1) {
        value *= BigInt.from(10);
      }
      return value;
    }),
  );

  WalletAmountInput parse({
    required String text,
    required PaymentRoute route,
    required BitcoinUnit bitcoinUnit,
  }) {
    if (text.isEmpty) {
      return const WalletAmountInput._invalid(
        text: '',
        issue: WalletAmountInputIssue.empty,
      );
    }
    if (text.length > _maximumInputCharacters ||
        text != text.trim() ||
        !_decimalPattern.hasMatch(text)) {
      return WalletAmountInput._invalid(
        text: text,
        issue: WalletAmountInputIssue.malformed,
      );
    }

    final precision = displayPrecision(route, bitcoinUnit);
    final separator = text.indexOf('.');
    final wholeText = separator == -1 ? text : text.substring(0, separator);
    final fractionText = separator == -1 ? '' : text.substring(separator + 1);
    if ((precision == 0 && separator != -1) ||
        fractionText.length > precision) {
      return WalletAmountInput._invalid(
        text: text,
        issue: WalletAmountInputIssue.precisionExceeded,
      );
    }

    final whole = BigInt.tryParse(wholeText);
    if (whole == null) {
      return WalletAmountInput._invalid(
        text: text,
        issue: WalletAmountInputIssue.malformed,
      );
    }
    final scale = _powersOfTen[precision];
    final fraction = fractionText.isEmpty
        ? BigInt.zero
        : BigInt.parse(fractionText.padRight(precision, '0'));
    final units = whole * scale + fraction;
    if (units == BigInt.zero) {
      return WalletAmountInput._invalid(
        text: text,
        issue: WalletAmountInputIssue.zero,
      );
    }
    if (units > BigInt.from(WalletAmount.maxNativeUnits)) {
      return WalletAmountInput._invalid(
        text: text,
        issue: WalletAmountInputIssue.outOfRange,
      );
    }
    return WalletAmountInput._valid(text: text, units: units.toInt());
  }

  /// Produces ungrouped keypad text from canonical route units.
  String formatUnits({
    required int units,
    required PaymentRoute route,
    required BitcoinUnit bitcoinUnit,
  }) {
    if (units < 0 || units > WalletAmount.maxNativeUnits) {
      throw ArgumentError.value(units, 'units');
    }
    final precision = displayPrecision(route, bitcoinUnit);
    if (precision == 0) return units.toString();

    final scale = _powersOfTen[precision];
    final value = BigInt.from(units);
    final whole = value ~/ scale;
    final remainder = value.remainder(scale);
    if (remainder == BigInt.zero) return whole.toString();
    final fraction = remainder
        .toString()
        .padLeft(precision, '0')
        .replaceFirst(_trailingZeros, '');
    return '$whole.$fraction';
  }

  int displayPrecision(PaymentRoute route, BitcoinUnit bitcoinUnit) {
    if (route.asset.kind == WalletAssetKind.usdt) {
      return route.asset.precision;
    }
    return switch ((route.rail, bitcoinUnit)) {
      (PaymentRail.onchain, BitcoinUnit.sats) => 0,
      (PaymentRail.onchain, BitcoinUnit.bitcoin) => 8,
      (PaymentRail.lightning, BitcoinUnit.sats) => 3,
      (PaymentRail.lightning, BitcoinUnit.bitcoin) => 11,
    };
  }
}
