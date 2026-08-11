import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/transaction/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  test('loads real balance, network, and normalized activity', () async {
    final engine = _engine();
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);

    final state = await harness.container.read(
      activityViewModelProvider(WalletAssetKind.bitcoin).future,
    );

    expect(state.feed.activities, engine.activities);
    expect(state.feed.balance.asset, WalletAsset.bitcoin);
    expect(state.feed.networkStatus.blockHeight, 100);
    expect(
      engine.calls,
      containsAllInOrder(['networkStatus', 'balance', 'activity']),
    );
  });

  test('refresh retains content on failure and suppresses overlap', () async {
    final engine = _engine();
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = activityViewModelProvider(WalletAssetKind.bitcoin);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final initial = await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);

    engine.syncGate = Completer<void>();
    final first = notifier.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(harness.container.read(provider).value?.refreshing, isTrue);
    expect(await notifier.refresh(), isFalse);
    engine.syncGate!.complete();
    expect(await first, isTrue);

    engine.syncGate = null;
    engine.syncError = TimeoutException('private native detail');
    expect(await notifier.refresh(), isFalse);
    final failed = harness.container.read(provider).requireValue;
    expect(failed.feed, initial.feed);
    expect(failed.refreshFailure?.userMessage, isNot(contains('private')));
  });

  test(
    'initial native failure retries through the same repository owner',
    () async {
      final engine = _engine()..activityError = TimeoutException('temporary');
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);
      final provider = activityViewModelProvider(WalletAssetKind.bitcoin);
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      await expectLater(
        harness.container.read(provider.future),
        throwsA(isA<AppFailureException>()),
      );
      engine.activityError = null;
      await harness.container.read(provider.notifier).retry();

      expect(
        harness.container.read(provider).requireValue.feed.activities,
        isNotEmpty,
      );
      expect(engine.calls.where((call) => call == 'activity'), hasLength(2));
    },
  );
}

FakeWalletEngine _engine() {
  final engine = FakeWalletEngine()
    ..balance = _bitcoinBalance()
    ..networkStatus = WalletNetworkStatus(
      environment: BlockchainEnvironment.regtest,
      blockHeight: 100,
      nodePublicKey:
          '020000000000000000000000000000000000000000000000000000000000000000',
      channelCount: 0,
      usableChannelCount: 0,
      peerCount: 0,
    );
  engine.activities = <WalletActivity>[
    WalletActivity(
      id: 'activity-${'a' * 64}',
      source: WalletActivitySource.bitcoinTransaction,
      operation: WalletActivityOperation.bitcoinReceive,
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
      direction: WalletActivityDirection.received,
      status: WalletActivityStatus.succeeded,
      amount: WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: 100),
      occurredAt: DateTime.utc(2026, 8, 11),
      txid: 'a' * 64,
    ),
  ];
  return engine;
}

WalletBalance _bitcoinBalance() {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: units);
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: onchain(100),
    onchainFuture: onchain(100),
    onchainSpendable: onchain(100),
    onchainLocked: onchain(0),
    lightningOwned: lightning(0),
    lightningSpendable: lightning(0),
    lightningReceivable: lightning(0),
  );
}
