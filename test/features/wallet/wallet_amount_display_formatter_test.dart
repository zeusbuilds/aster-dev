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

  test('formats deployment-precision RGB and USD estimates exactly', () {
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
    expect(WalletUsdEstimate.cents(units: 1234567, route: usdt), 123);
    expect(
      WalletUsdEstimate.formatCents(6500000, locale: 'en_US'),
      '\$65,000.00',
    );
  });

  test('uses satoshi and millisatoshi denominators for BTC USD estimates', () {
    const onchain = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );
    const lightning = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    expect(
      WalletUsdEstimate.cents(
        units: 100000000,
        route: onchain,
        bitcoinPriceCents: 6500000,
      ),
      6500000,
    );
    expect(
      WalletUsdEstimate.cents(
        units: 100000000000,
        route: lightning,
        bitcoinPriceCents: 6500000,
      ),
      6500000,
    );
  });
}
