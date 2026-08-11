import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _nodePublicKey =
    '020000000000000000000000000000000000000000000000000000000000000000';

void main() {
  test('wallet domain objects compare by validated value', () {
    final asset = WalletAsset.rgbUsdt(assetId: 'rgb:contract', precision: 6);
    final sameAsset = WalletAsset.rgbUsdt(
      assetId: 'rgb:contract',
      precision: 6,
    );
    final settled = WalletAmount.onchain(assetId: asset.id, units: 100);
    final spendable = WalletAmount.onchain(assetId: asset.id, units: 80);
    final locked = WalletAmount.onchain(assetId: asset.id, units: 20);
    final future = WalletAmount.onchain(assetId: asset.id, units: 110);
    final lightning = WalletAmount.lightning(assetId: asset.id, units: 10);
    final balance = WalletBalance(
      asset: asset,
      onchainSettled: settled,
      onchainFuture: future,
      onchainSpendable: spendable,
      onchainLocked: locked,
      lightningOwned: lightning,
      lightningSpendable: lightning,
      lightningReceivable: lightning,
    );
    final sameBalance = WalletBalance(
      asset: sameAsset,
      onchainSettled: WalletAmount.onchain(assetId: sameAsset.id, units: 100),
      onchainFuture: WalletAmount.onchain(assetId: sameAsset.id, units: 110),
      onchainSpendable: WalletAmount.onchain(assetId: sameAsset.id, units: 80),
      onchainLocked: WalletAmount.onchain(assetId: sameAsset.id, units: 20),
      lightningOwned: WalletAmount.lightning(assetId: sameAsset.id, units: 10),
      lightningSpendable: WalletAmount.lightning(
        assetId: sameAsset.id,
        units: 10,
      ),
      lightningReceivable: WalletAmount.lightning(
        assetId: sameAsset.id,
        units: 10,
      ),
    );

    expect(asset, sameAsset);
    expect(balance, sameBalance);
    expect(balance.hashCode, sameBalance.hashCode);
  });

  test(
    'payment targets have stable slugs and resolve from concrete routes',
    () {
      final usdt = WalletAsset.rgbUsdt(
        assetId: 'rgb:usdt-contract',
        precision: 6,
      );

      for (final target in WalletPaymentTarget.values) {
        expect(WalletPaymentTarget.tryParse(target.slug), target);
      }
      expect(WalletPaymentTarget.tryParse('BTC'), isNull);
      expect(
        PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.lightning,
        ).target,
        WalletPaymentTarget.bitcoinLightning,
      );
      expect(
        PaymentRoute(asset: usdt, rail: PaymentRail.onchain).target,
        WalletPaymentTarget.usdtOnchain,
      );
    },
  );

  test('payment capabilities distinguish missing deployment metadata', () {
    final available = WalletPaymentCapability.available(
      PaymentRoute(asset: WalletAsset.bitcoin, rail: PaymentRail.onchain),
    );
    const unavailable = WalletPaymentCapability.unavailable(
      WalletPaymentTarget.usdtLightning,
    );

    expect(available.isAvailable, isTrue);
    expect(available.route, isNotNull);
    expect(unavailable.isAvailable, isFalse);
    expect(unavailable.route, isNull);
  });

  test('registry and network metadata compare by value', () {
    final created = DateTime.utc(2026, 8, 8);
    final profile = WalletProfile(
      id: '00000000000000000000000000000001',
      name: 'Main',
      createdAt: created,
      updatedAt: created,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.ready,
      storageToken: '10000000000000000000000000000001',
    );
    final firstRegistry = WalletRegistry(
      profiles: [profile],
      activeWalletId: profile.id,
    );
    final secondRegistry = WalletRegistry(
      profiles: [profile],
      activeWalletId: profile.id,
    );
    final firstStatus = WalletNetworkStatus(
      environment: BlockchainEnvironment.regtest,
      blockHeight: 42,
      nodePublicKey: _nodePublicKey,
      channelCount: 2,
      usableChannelCount: 1,
      peerCount: 1,
    );
    final secondStatus = WalletNetworkStatus(
      environment: BlockchainEnvironment.regtest,
      blockHeight: 42,
      nodePublicKey: _nodePublicKey,
      channelCount: 2,
      usableChannelCount: 1,
      peerCount: 1,
    );

    expect(firstRegistry, secondRegistry);
    expect(firstStatus, secondStatus);
    expect(
      WalletPublicKeys(bitcoin: 'tpub-btc', rgb: 'tpub-rgb'),
      WalletPublicKeys(bitcoin: 'tpub-btc', rgb: 'tpub-rgb'),
    );
  });

  test('wallet names reject control and bidirectional override characters', () {
    final created = DateTime.utc(2026, 8, 8);

    WalletProfile profile(String name) => WalletProfile(
      id: '00000000000000000000000000000001',
      name: name,
      createdAt: created,
      updatedAt: created,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.ready,
      storageToken: '10000000000000000000000000000001',
    );

    expect(() => profile('Main\nWallet'), throwsArgumentError);
    expect(() => profile('Main\u202eWallet'), throwsArgumentError);
    expect(() => profile('Main\u2028Wallet'), throwsArgumentError);
    expect(() => profile('Main\u061cWallet'), throwsArgumentError);
  });

  test('wallet public keys reject whitespace and unbounded native values', () {
    expect(
      () => WalletPublicKeys(bitcoin: 'tpub btc', rgb: 'tpub-rgb'),
      throwsArgumentError,
    );
    expect(
      () => WalletPublicKeys(bitcoin: 'a' * 513, rgb: 'tpub-rgb'),
      throwsArgumentError,
    );
  });

  test('aggregate balances reject signed 64-bit overflow', () {
    const asset = WalletAsset.bitcoin;
    final maximum = WalletAmount.onchain(
      assetId: asset.id,
      units: WalletAmount.maxNativeUnits,
    );
    final zero = WalletAmount.onchain(assetId: asset.id, units: 0);
    final lightning = WalletAmount.lightning(assetId: asset.id, units: 1);

    expect(
      () => WalletBalance(
        asset: asset,
        onchainSettled: maximum,
        onchainFuture: maximum,
        onchainSpendable: maximum,
        onchainLocked: zero,
        lightningOwned: lightning,
        lightningSpendable: lightning,
        lightningReceivable: lightning,
      ),
      throwsFormatException,
    );
  });
}
