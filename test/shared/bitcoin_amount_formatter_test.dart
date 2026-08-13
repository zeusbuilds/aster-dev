import 'package:aster/shared/shared.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BitcoinAmountFormatter', () {
    test('formats exact BTC values without floating point', () {
      final formatter = BitcoinAmountFormatter(
        unit: BitcoinUnit.bitcoin,
        locale: 'en_US',
      );

      expect(formatter.format(0), '0 BTC');
      expect(formatter.format(1), '0.00000001 BTC');
      expect(formatter.format(100), '0.000001 BTC');
      expect(formatter.format(12345678), '0.12345678 BTC');
      expect(formatter.format(100000000), '1 BTC');
      expect(formatter.format(-2100000000000000), '-21,000,000 BTC');
    });

    test('formats satoshis as grouped integers', () {
      final formatter = BitcoinAmountFormatter(
        unit: BitcoinUnit.sats,
        locale: 'en_US',
      );

      expect(formatter.format(12345678), '12,345,678 sats');
      expect(formatter.format(-1), '-1 sats');
    });

    test('localizes whole and fractional digits without mixed scripts', () {
      final bitcoin = BitcoinAmountFormatter(
        unit: BitcoinUnit.bitcoin,
        locale: 'ar_EG',
      );
      final sats = BitcoinAmountFormatter(
        unit: BitcoinUnit.sats,
        locale: 'ar_EG',
      );

      expect(bitcoin.format(125000000), '١٫٢٥ BTC');
      expect(sats.format(12345678), '١٢٬٣٤٥٬٦٧٨ sats');
      expect(bitcoin.format(1), '٠٫٠٠٠٠٠٠٠١ BTC');
    });

    test('persisted unit parsing fails closed', () {
      expect(BitcoinUnit.parse('btc'), BitcoinUnit.bitcoin);
      expect(BitcoinUnit.parse('sats'), BitcoinUnit.sats);
      expect(() => BitcoinUnit.parse('bits'), throwsFormatException);
    });
  });
}
