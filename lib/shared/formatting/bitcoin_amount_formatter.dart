import 'package:intl/intl.dart';

import 'bitcoin_unit.dart';

/// Formats integer satoshi amounts without passing monetary values through a
/// floating-point representation.
final class BitcoinAmountFormatter {
  BitcoinAmountFormatter({required this.unit, String? locale})
    : _integer = NumberFormat.decimalPattern(locale);

  static const int satoshisPerBitcoin = 100000000;

  final BitcoinUnit unit;
  final NumberFormat _integer;

  /// Formats [satoshis] and appends the selected unit label.
  String format(int satoshis) => '${formatNumeric(satoshis)} ${unit.label}';

  /// Formats only the numeric portion of [satoshis].
  String formatNumeric(int satoshis) => switch (unit) {
    BitcoinUnit.sats => _integer.format(satoshis),
    BitcoinUnit.bitcoin => _formatBitcoin(satoshis),
  };

  String _formatBitcoin(int satoshis) {
    final value = BigInt.from(satoshis);
    final negative = value.isNegative;
    final absolute = value.abs();
    final whole = absolute ~/ BigInt.from(satoshisPerBitcoin);
    final remainder = absolute.remainder(BigInt.from(satoshisPerBitcoin));
    final groupedWhole = _integer.format(whole.toInt());
    if (remainder == BigInt.zero) {
      return '${negative ? '-' : ''}$groupedWhole';
    }

    final fraction = remainder
        .toString()
        .padLeft(8, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '${negative ? '-' : ''}$groupedWhole'
        '${_integer.symbols.DECIMAL_SEP}$fraction';
  }
}
