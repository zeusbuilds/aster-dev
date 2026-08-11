import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/formatting/bitcoin_unit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = WalletAmountInputCodec();
  const bitcoinOnchain = PaymentRoute(
    asset: WalletAsset.bitcoin,
    rail: PaymentRail.onchain,
  );
  const bitcoinLightning = PaymentRoute(
    asset: WalletAsset.bitcoin,
    rail: PaymentRail.lightning,
  );
  final usdt = WalletAsset.rgbUsdt(
    assetId: 'rgb:configured-usdt',
    precision: 6,
  );

  test('parses Bitcoin display units into exact route units', () {
    expect(
      codec
          .parse(
            text: '100',
            route: bitcoinOnchain,
            bitcoinUnit: BitcoinUnit.sats,
          )
          .units,
      100,
    );
    expect(
      codec
          .parse(
            text: '0.00000001',
            route: bitcoinOnchain,
            bitcoinUnit: BitcoinUnit.bitcoin,
          )
          .units,
      1,
    );
    expect(
      codec
          .parse(
            text: '1.001',
            route: bitcoinLightning,
            bitcoinUnit: BitcoinUnit.sats,
          )
          .units,
      1001,
    );
    expect(
      codec
          .parse(
            text: '0.00000000001',
            route: bitcoinLightning,
            bitcoinUnit: BitcoinUnit.bitcoin,
          )
          .units,
      1,
    );
  });

  test('uses deployment-owned RGB precision on either rail', () {
    for (final rail in PaymentRail.values) {
      final parsed = codec.parse(
        text: '1.234567',
        route: PaymentRoute(asset: usdt, rail: rail),
        bitcoinUnit: BitcoinUnit.sats,
      );

      expect(parsed.units, 1234567);
      expect(parsed.issue, isNull);
    }
  });

  test('classifies empty, malformed, precision, zero, and range errors', () {
    WalletAmountInput parse(String text) => codec.parse(
      text: text,
      route: bitcoinOnchain,
      bitcoinUnit: BitcoinUnit.bitcoin,
    );

    expect(parse('').issue, WalletAmountInputIssue.empty);
    for (final value in const ['.', '-1', '+1', '1..0', '1,000', ' 1']) {
      expect(parse(value).issue, WalletAmountInputIssue.malformed);
    }
    expect(
      parse('0.000000001').issue,
      WalletAmountInputIssue.precisionExceeded,
    );
    expect(parse('0.00000000').issue, WalletAmountInputIssue.zero);
    expect(
      parse('99999999999999999999').issue,
      WalletAmountInputIssue.outOfRange,
    );
    expect(
      codec
          .parse(
            text: '1.',
            route: bitcoinOnchain,
            bitcoinUnit: BitcoinUnit.sats,
          )
          .issue,
      WalletAmountInputIssue.precisionExceeded,
    );
  });

  test('formats canonical units into reversible ungrouped keypad text', () {
    final vectors = <(PaymentRoute, BitcoinUnit, int, String)>[
      (bitcoinOnchain, BitcoinUnit.sats, 1000, '1000'),
      (bitcoinOnchain, BitcoinUnit.bitcoin, 100000001, '1.00000001'),
      (bitcoinLightning, BitcoinUnit.sats, 1001, '1.001'),
      (bitcoinLightning, BitcoinUnit.bitcoin, 1001, '0.00000001001'),
      (
        PaymentRoute(asset: usdt, rail: PaymentRail.onchain),
        BitcoinUnit.sats,
        1250000,
        '1.25',
      ),
    ];

    for (final (route, unit, units, text) in vectors) {
      expect(
        codec.formatUnits(units: units, route: route, bitcoinUnit: unit),
        text,
      );
      expect(
        codec.parse(text: text, route: route, bitcoinUnit: unit).units,
        units,
      );
    }
  });
}
