import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/formatting/formatting.dart';
import 'package:aster/shared/formatting/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final formatter = WalletAmountDisplayFormatter(locale: 'en_US');

  test('formats on-chain and Lightning Bitcoin units exactly', () {
    const onchain = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );
    const lightning = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );

    expect(
      formatter
          .format(
            units: 123456789,
            route: onchain,
            bitcoinUnit: BitcoinUnit.bitcoin,
          )
          .text,
      '1.23456789 BTC',
    );
    expect(
      formatter
          .format(
            units: 123456789,
            route: onchain,
            bitcoinUnit: BitcoinUnit.sats,
          )
          .text,
      '123,456,789 sats',
    );
    expect(
      formatter
          .format(units: 1234, route: lightning, bitcoinUnit: BitcoinUnit.sats)
          .text,
      '1.234 sats',
    );
    expect(
      formatter
          .format(
            units: 1234,
            route: lightning,
            bitcoinUnit: BitcoinUnit.bitcoin,
          )
          .text,
      '0.00000001234 BTC',
    );
  });

  test('formats deployment-precision RGB and fiat estimates exactly', () {
    final usdt = PaymentRoute(
      asset: WalletAsset.rgbUsdt(assetId: 'rgb-usdt', precision: 6),
      rail: PaymentRail.lightning,
    );
    expect(
      formatter
          .format(units: 1234567, route: usdt, bitcoinUnit: BitcoinUnit.sats)
          .text,
      '1.234567 USDT',
    );
    expect(
      WalletFiatEstimate.minorUnits(
        units: 1234567,
        route: usdt,
        assetPriceMinorUnits: 100,
      ),
      123,
    );
    expect(
      WalletFiatEstimate.formatMinorUnits(
        minorUnits: 6500000,
        symbol: r'$',
        code: 'USD',
        minorUnitDigits: 2,
        locale: 'en_US',
      ),
      '\$65,000.00 USD',
    );
    expect(
      WalletFiatEstimate.formatMinorUnits(
        minorUnits: 65000,
        symbol: '¥',
        code: 'JPY',
        minorUnitDigits: 0,
        locale: 'en_US',
      ),
      '¥65,000 JPY',
    );
    expect(
      WalletFiatEstimate.formatMinorUnits(
        minorUnits: 6500,
        symbol: 'kr',
        code: 'SEK',
        minorUnitDigits: 2,
        locale: 'sv',
      ),
      '65,00\u00a0kr SEK',
    );
  });

  test('uses satoshi and millisatoshi denominators for BTC fiat estimates', () {
    const onchain = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );
    const lightning = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    expect(
      WalletFiatEstimate.minorUnits(
        units: 100000000,
        route: onchain,
        assetPriceMinorUnits: 6500000,
      ),
      6500000,
    );
    expect(
      WalletFiatEstimate.minorUnits(
        units: 100000000000,
        route: lightning,
        assetPriceMinorUnits: 6500000,
      ),
      6500000,
    );
  });

  test('rejects fiat formatting with an incorrect ISO precision', () {
    expect(
      () => WalletFiatEstimate.formatMinorUnits(
        minorUnits: 6500,
        symbol: '¥',
        code: 'JPY',
        minorUnitDigits: 2,
      ),
      throwsArgumentError,
    );
  });

  test('does not convert against a non-positive market quote', () {
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );

    expect(
      WalletFiatEstimate.minorUnits(
        units: 100000000,
        route: route,
        assetPriceMinorUnits: 0,
      ),
      isNull,
    );
  });

  test('localizes exact fractional digits without floating-point math', () {
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );

    expect(
      WalletAmountDisplayFormatter(locale: 'ar_EG')
          .format(
            units: 125000000,
            route: route,
            bitcoinUnit: BitcoinUnit.bitcoin,
          )
          .numeric,
      '١٫٢٥',
    );
    final fiat = FiatAmountFormatter(locale: 'ar_EG')
        .format(minorUnits: 125, symbol: r'$', code: 'USD', minorUnitDigits: 2);
    expect(fiat, contains('١٫٢٥'));
    expect(fiat, isNot(contains('1.25')));
  });
}
