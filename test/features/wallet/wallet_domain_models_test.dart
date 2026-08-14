import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/domain/validation/validation.dart';
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

  test('payment contracts preserve exact units and reject route mismatch', () {
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    final amount = WalletAmount.lightning(
      assetId: WalletAsset.bitcoin.id,
      units: 1501,
    );
    final expiresAt = DateTime.utc(2026, 8, 11, 12);
    final preview = WalletPaymentPreview(
      route: route,
      encodedDestination: 'lnbcrt1invoice',
      displayDestination: 'lnbcrt1invoice',
      amount: amount,
      expiresAt: expiresAt,
      referenceId: 'payment-hash',
    );

    expect(preview.amount?.units, 1501);
    expect(preview.requiresAmount, isFalse);
    expect(preview.isExpiredAt(expiresAt), isTrue);
    expect(preview.toString(), isNot(contains('lnbcrt1invoice')));
    expect(
      preview,
      WalletPaymentPreview(
        route: route,
        encodedDestination: 'lnbcrt1invoice',
        displayDestination: 'lnbcrt1invoice',
        amount: amount,
        expiresAt: expiresAt,
        referenceId: 'payment-hash',
      ),
    );
    expect(
      () => WalletSendCommand(
        route: const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.onchain,
        ),
        destination: 'bcrt1destination',
        amount: amount,
      ),
      throwsArgumentError,
    );
  });

  test(
    'protocol text accepts visible ASCII and rejects deceptive wire data',
    () {
      expect(
        WalletProtocolText.isEncodedValue(
          'bitcoin:address?message=Payment%20for%20order%231',
        ),
        isTrue,
      );
      expect(WalletProtocolText.isIdentifier('txid:0'), isTrue);

      for (final value in <String>[
        '',
        ' invoice',
        'invoice ',
        'invoice\nnext',
        'invoice\u007f',
        'invoice\u200bhidden',
        'invoice\u202ereversed',
        'invoic\u00e9',
      ]) {
        expect(
          WalletProtocolText.isEncodedValue(value),
          isFalse,
          reason: value.codeUnits.toString(),
        );
        expect(
          WalletProtocolText.isIdentifier(value),
          isFalse,
          reason: value.codeUnits.toString(),
        );
      }
      expect(
        WalletProtocolText.isEncodedValue(
          'a' * (WalletProtocolText.maximumEncodedCharacters + 1),
        ),
        isFalse,
      );
      expect(
        WalletProtocolText.isIdentifier(
          'a' * (WalletProtocolText.maximumIdentifierCharacters + 1),
        ),
        isFalse,
      );

      const route = PaymentRoute(
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.lightning,
      );
      expect(
        () => WalletPaymentPreview(
          route: route,
          encodedDestination: 'lnbcrt1invoice\u202e',
          displayDestination: 'lnbcrt1invoice',
        ),
        throwsArgumentError,
      );
      expect(
        () => WalletActivity(
          id: 'activity-${'f' * 64}',
          source: WalletActivitySource.lightningPayment,
          operation: WalletActivityOperation.lightningPayment,
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.lightning,
          direction: WalletActivityDirection.received,
          status: WalletActivityStatus.pending,
          paymentHash: 'payment\u200bhash',
        ),
        throwsArgumentError,
      );
    },
  );

  test('onchain commands require typed fees and Lightning forbids them', () {
    final observedAt = DateTime.utc(2026, 8, 11, 10);
    final fee = WalletFeeRateEstimate(
      targetBlocks: 6,
      satsPerVbyte: 3,
      observedAt: observedAt,
    );
    const onchain = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );
    const lightning = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    final onchainAmount = WalletAmount.onchain(
      assetId: WalletAsset.bitcoin.id,
      units: 1,
    );
    final lightningAmount = WalletAmount.lightning(
      assetId: WalletAsset.bitcoin.id,
      units: 1000,
    );

    final command = WalletSendCommand(
      route: onchain,
      destination: 'bcrt1destination',
      amount: onchainAmount,
      feeRate: fee,
    );
    expect(command.feeRate, fee);
    expect(fee.isStaleAt(observedAt.add(const Duration(minutes: 2))), isFalse);
    expect(
      fee.isStaleAt(
        observedAt.add(const Duration(minutes: 2, microseconds: 1)),
      ),
      isTrue,
    );
    expect(
      fee.isStaleAt(observedAt.subtract(const Duration(seconds: 1))),
      isTrue,
    );
    expect(
      () => WalletSendCommand(
        route: onchain,
        destination: 'bcrt1destination',
        amount: onchainAmount,
      ),
      throwsArgumentError,
    );
    expect(
      () => WalletSendCommand(
        route: lightning,
        destination: 'lnbcrt1invoice',
        amount: lightningAmount,
        feeRate: fee,
      ),
      throwsArgumentError,
    );
  });

  test('portfolio exposes only configured product balances', () {
    final bitcoin = _balanceFor(WalletAsset.bitcoin);
    final usdtAsset = WalletAsset.rgbUsdt(
      assetId: 'rgb:configured-usdt',
      precision: 6,
    );
    final usdt = _balanceFor(usdtAsset);
    final portfolio = WalletPortfolio(bitcoin: bitcoin, usdt: usdt);

    expect(portfolio.balances, [bitcoin, usdt]);
    expect(portfolio.balanceFor(WalletAssetKind.bitcoin), bitcoin);
    expect(portfolio.balanceFor(WalletAssetKind.usdt), usdt);
    expect(portfolio, WalletPortfolio(bitcoin: bitcoin, usdt: usdt));
    expect(WalletPortfolio(bitcoin: bitcoin).balances, [bitcoin]);
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
    expect(() => profile('Main\u200bWallet'), throwsArgumentError);
    expect(() => profile('Main\u2060Wallet'), throwsArgumentError);
    expect(() => profile('Main\u3000Wallet'), throwsArgumentError);
    expect(
      () => profile('Main${String.fromCharCode(0xd800)}Wallet'),
      throwsArgumentError,
    );
    expect(
      () => profile('Main${String.fromCharCode(0xe0001)}Wallet'),
      throwsArgumentError,
    );
    expect(profile('Jos\u00e9 Wallet').name, 'Jos\u00e9 Wallet');
  });

  test('human payment and native labels share one Unicode safety policy', () {
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    final unsafeValues = <String>[
      'hidden\u200btext',
      'reversed\u202etext',
      'joined\u2060text',
      'wide\u3000space',
    ];

    for (final value in unsafeValues) {
      expect(
        () => WalletPaymentPreview(
          route: route,
          encodedDestination: 'lnbcrt1invoice',
          displayDestination: 'lnbcrt1invoice',
          recipientLabel: value,
        ),
        throwsArgumentError,
        reason: value.codeUnits.toString(),
      );
      expect(
        () => WalletActivity(
          id: 'activity-${'a' * 64}',
          source: WalletActivitySource.rgbTransfer,
          operation: WalletActivityOperation.rgbReceive,
          asset: WalletAsset.rgbUsdt(
            assetId: 'rgb:configured-usdt',
            precision: 6,
          ),
          rail: PaymentRail.onchain,
          direction: WalletActivityDirection.received,
          status: WalletActivityStatus.pending,
          transferIndex: 1,
          transportEndpointCount: 1,
          transportTypes: [value],
        ),
        throwsArgumentError,
        reason: value.codeUnits.toString(),
      );
    }

    final preview = WalletPaymentPreview(
      route: route,
      encodedDestination: 'lnbcrt1invoice',
      displayDestination: 'lnbcrt1invoice',
      recipientLabel: 'Jos\u00e9 Wallet',
    );
    expect(preview.recipientLabel, 'Jos\u00e9 Wallet');
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
    expect(
      () => WalletPublicKeys(bitcoin: 'tpub\u200bhidden', rgb: 'tpub-rgb'),
      throwsArgumentError,
    );
    expect(
      () => WalletAsset.rgbUsdt(assetId: 'rgb:contract\u202e', precision: 6),
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

  test('asset kinds expose stable route slugs', () {
    expect(WalletAssetKind.bitcoin.slug, 'bitcoin');
    expect(WalletAssetKind.usdt.slug, 'usdt');
    expect(WalletAssetKind.tryParse('bitcoin'), WalletAssetKind.bitcoin);
    expect(WalletAssetKind.tryParse('usdt'), WalletAssetKind.usdt);
    expect(WalletAssetKind.tryParse('BTC'), isNull);
  });

  test('activity feed enforces opaque IDs, exact shape, and recency', () {
    final older = _bitcoinActivity(
      idCharacter: 'a',
      occurredAt: DateTime.utc(2026, 8, 10),
    );
    final newer = _bitcoinActivity(
      idCharacter: 'b',
      occurredAt: DateTime.utc(2026, 8, 11),
    );
    final feed = WalletActivityFeed(
      balance: _balanceFor(WalletAsset.bitcoin),
      networkStatus: _networkStatus(),
      activities: [newer, older],
    );

    expect(feed.findById(newer.id), newer);
    expect(() => feed.activities.add(older), throwsUnsupportedError);
    expect(newer.toString(), isNot(contains('native-txid')));
    expect(
      () => WalletActivityFeed(
        balance: _balanceFor(WalletAsset.bitcoin),
        networkStatus: _networkStatus(),
        activities: [older, newer],
      ),
      throwsArgumentError,
    );
    expect(
      () => _bitcoinActivity(idCharacter: 'x', occurredAt: null),
      throwsArgumentError,
    );
  });

  test('activity records reject cross-family operations and fields', () {
    expect(
      () => WalletActivity(
        id: 'activity-${'c' * 64}',
        source: WalletActivitySource.bitcoinTransaction,
        operation: WalletActivityOperation.lightningPayment,
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.onchain,
        direction: WalletActivityDirection.received,
        status: WalletActivityStatus.pending,
        txid: 'native-txid',
      ),
      throwsArgumentError,
    );
    expect(
      () => WalletActivity(
        id: 'activity-${'d' * 64}',
        source: WalletActivitySource.lightningPayment,
        operation: WalletActivityOperation.lightningPayment,
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.lightning,
        direction: WalletActivityDirection.internal,
        status: WalletActivityStatus.pending,
        paymentHash: 'payment-hash',
      ),
      throwsArgumentError,
    );
    expect(
      () => WalletActivity(
        id: 'activity-${'e' * 64}',
        source: WalletActivitySource.rgbTransfer,
        operation: WalletActivityOperation.rgbReceive,
        asset: WalletAsset.rgbUsdt(
          assetId: 'rgb:configured-usdt',
          precision: 6,
        ),
        rail: PaymentRail.onchain,
        direction: WalletActivityDirection.received,
        status: WalletActivityStatus.pending,
        paymentHash: 'payment-hash',
        transferIndex: 1,
      ),
      throwsArgumentError,
    );
  });
}

WalletNetworkStatus _networkStatus() => WalletNetworkStatus(
  environment: BlockchainEnvironment.regtest,
  blockHeight: 100,
  nodePublicKey: _nodePublicKey,
  channelCount: 0,
  usableChannelCount: 0,
  peerCount: 0,
);

WalletBalance _balanceFor(WalletAsset asset) {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: asset.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: asset.id, units: units);
  return WalletBalance(
    asset: asset,
    onchainSettled: onchain(1),
    onchainFuture: onchain(1),
    onchainSpendable: onchain(1),
    onchainLocked: onchain(0),
    lightningOwned: lightning(0),
    lightningSpendable: lightning(0),
    lightningReceivable: lightning(0),
  );
}

WalletActivity _bitcoinActivity({
  required String idCharacter,
  required DateTime? occurredAt,
}) {
  return WalletActivity(
    id: 'activity-${idCharacter * 64}',
    source: WalletActivitySource.bitcoinTransaction,
    operation: WalletActivityOperation.bitcoinReceive,
    asset: WalletAsset.bitcoin,
    rail: PaymentRail.onchain,
    direction: WalletActivityDirection.received,
    status: WalletActivityStatus.succeeded,
    amount: WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: 1),
    occurredAt: occurredAt,
    txid: 'native-txid',
  );
}
