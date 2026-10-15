import 'package:aster/features/home/presentation/formatting/formatting.dart';
import 'package:aster/features/market/domain/models/models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/formatting/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 12);
  final usdMarket = BitcoinMarketSnapshot(
    quoteCurrency: MarketQuoteCurrency(
      code: 'USD',
      symbol: r'$',
      minorUnitDigits: 2,
    ),
    currentBitcoinPrice: FiatMarketPrice(minorUnits: 10000000, observedAt: now),
    currentUsdtPrice: FiatMarketPrice(minorUnits: 100, observedAt: now),
    currentSource: BitcoinPriceSource.spot,
    history: const [],
  );
  final eurMarket = BitcoinMarketSnapshot(
    quoteCurrency: MarketQuoteCurrency(
      code: 'EUR',
      symbol: '€',
      minorUnitDigits: 2,
    ),
    currentBitcoinPrice: FiatMarketPrice(minorUnits: 9000000, observedAt: now),
    currentUsdtPrice: FiatMarketPrice(minorUnits: 92, observedAt: now),
    currentSource: BitcoinPriceSource.spot,
    history: const [],
  );

  test('formats exact Bitcoin total and available cross-rail balances', () {
    final display = HomeAssetDisplayFormatter().format(
      balance: _bitcoinBalance(),
      bitcoinUnit: BitcoinUnit.sats,
      currencyCode: 'USD',
      now: now,
      bitcoinMarket: usdMarket,
    );

    expect(display.total.text, '1,001.5 sats');
    expect(display.available.text, '901.25 sats');
    expect(display.fiatContext, r'$1.00 USD estimated');
  });

  test(
    'pending Bitcoin spendability does not alter or clamp the confirmed total',
    () {
      WalletAmount onchain(int units) =>
          WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units);
      final lightning = WalletAmount.lightning(
        assetId: WalletAsset.bitcoin.id,
        units: 0,
      );
      final display = HomeAssetDisplayFormatter().format(
        balance: WalletBalance(
          asset: WalletAsset.bitcoin,
          onchainSettled: onchain(0),
          onchainFuture: onchain(100000),
          onchainSpendable: onchain(80000),
          onchainLocked: onchain(20000),
          lightningOwned: lightning,
          lightningSpendable: lightning,
          lightningReceivable: lightning,
        ),
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'USD',
        now: now,
        bitcoinMarket: usdMarket,
      );
      expect(display.total.text, '0 sats');
      expect(display.available.text, '80,000 sats');
      expect(display.fiatContext, r'$0.00 USD estimated');
    },
  );

  test('formats a selected non-USD quote without relabeling it', () {
    final formatter = HomeAssetDisplayFormatter();
    expect(
      formatter
          .format(
            balance: _bitcoinBalance(),
            bitcoinUnit: BitcoinUnit.bitcoin,
            currencyCode: 'EUR',
            now: now,
            bitcoinMarket: eurMarket,
          )
          .fiatContext,
      '€0.90 EUR estimated',
    );
  });

  test('rejects mismatched and stale selected-currency quotes', () {
    final formatter = HomeAssetDisplayFormatter();
    expect(
      formatter
          .format(
            balance: _bitcoinBalance(),
            bitcoinUnit: BitcoinUnit.bitcoin,
            currencyCode: 'EUR',
            now: now,
            bitcoinMarket: usdMarket,
          )
          .fiatContext,
      'EUR estimate unavailable',
    );
    expect(
      formatter
          .format(
            balance: _bitcoinBalance(),
            bitcoinUnit: BitcoinUnit.bitcoin,
            currencyCode: 'USD',
            now: usdMarket.expiresAt,
            bitcoinMarket: usdMarket,
          )
          .fiatContext,
      'USD estimate unavailable',
    );
  });

  test('formats configured USDT from its independent live fiat quote', () {
    final display = HomeAssetDisplayFormatter().format(
      balance: _usdtBalance(),
      bitcoinUnit: BitcoinUnit.sats,
      currencyCode: 'USD',
      now: now,
      bitcoinMarket: usdMarket,
    );

    expect(display.total.text, '125 USDT');
    expect(display.available.text, '110 USDT');
    expect(display.fiatContext, r'$125.00 USD estimated');
  });
}

WalletBalance _bitcoinBalance() {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: units);
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: onchain(1000),
    onchainFuture: onchain(1000),
    onchainSpendable: onchain(900),
    onchainLocked: onchain(100),
    lightningOwned: lightning(1500),
    lightningSpendable: lightning(1250),
    lightningReceivable: lightning(0),
  );
}

WalletBalance _usdtBalance() {
  final asset = WalletAsset.rgbUsdt(assetId: 'contract-id', precision: 2);
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: asset.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: asset.id, units: units);
  return WalletBalance(
    asset: asset,
    onchainSettled: onchain(10000),
    onchainFuture: onchain(10000),
    onchainSpendable: onchain(9000),
    onchainLocked: onchain(1000),
    lightningOwned: lightning(2500),
    lightningSpendable: lightning(2000),
    lightningReceivable: lightning(0),
  );
}
