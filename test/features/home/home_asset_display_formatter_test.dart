import 'package:aster/features/home/presentation/formatting/formatting.dart';
import 'package:aster/features/market/data/data.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/formatting/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 12);
  final market = BitcoinMarketSnapshot(
    currentUsdCents: 10000000,
    currentObservedAt: now,
    currentSource: BitcoinPriceSource.spot,
    history: const [],
  );

  test('formats exact Bitcoin total and available cross-rail balances', () {
    final display = HomeAssetDisplayFormatter().format(
      balance: _bitcoinBalance(),
      bitcoinUnit: BitcoinUnit.sats,
      currencyCode: 'USD',
      now: now,
      bitcoinMarket: market,
    );

    expect(display.total.text, '1,001.5 sats');
    expect(display.available.text, '901.25 sats');
    expect(display.fiatContext, r'$1.00 estimated');
  });

  test('never relabels missing or stale quote currency as USD', () {
    final formatter = HomeAssetDisplayFormatter();
    expect(
      formatter
          .format(
            balance: _bitcoinBalance(),
            bitcoinUnit: BitcoinUnit.bitcoin,
            currencyCode: 'EUR',
            now: now,
            bitcoinMarket: market,
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
            now: market.expiresAt,
            bitcoinMarket: market,
          )
          .fiatContext,
      'USD estimate unavailable',
    );
  });

  test('formats configured USDT in contract units and labels face value', () {
    final display = HomeAssetDisplayFormatter().format(
      balance: _usdtBalance(),
      bitcoinUnit: BitcoinUnit.sats,
      currencyCode: 'USD',
      now: now,
      bitcoinMarket: market,
    );

    expect(display.total.text, '125 USDT');
    expect(display.available.text, '110 USDT');
    expect(display.fiatContext, r'$125.00 face value');
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
