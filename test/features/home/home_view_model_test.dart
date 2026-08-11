import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  test(
    'loads one truthful cross-rail portfolio for the active wallet',
    () async {
      final engine = FakeWalletEngine()..balance = _bitcoinBalance();
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);

      final state = await harness.container.read(homeViewModelProvider.future);

      expect(state.portfolio.bitcoin.totalBitcoinMillisatoshis, 2001500);
      expect(state.portfolio.bitcoin.availableBitcoinMillisatoshis, 1501000);
      expect(state.portfolio.usdt, isNull);
      expect(engine.calls.where((call) => call == 'balance'), hasLength(1));
    },
  );

  test('refresh preserves content on failure and suppresses overlap', () async {
    final engine = FakeWalletEngine()..balance = _bitcoinBalance();
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final subscription = harness.container.listen(
      homeViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    final initial = await harness.container.read(homeViewModelProvider.future);
    final notifier = harness.container.read(homeViewModelProvider.notifier);

    engine.syncGate = Completer<void>();
    final firstRefresh = notifier.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(
      harness.container.read(homeViewModelProvider).value?.refreshing,
      isTrue,
    );
    expect(await notifier.refresh(), isFalse);
    engine.syncGate!.complete();
    expect(await firstRefresh, isTrue);

    engine.syncGate = null;
    engine.syncError = TimeoutException('sensitive transport detail');
    expect(await notifier.refresh(), isFalse);
    final failed = harness.container.read(homeViewModelProvider).requireValue;
    expect(failed.portfolio, initial.portfolio);
    expect(failed.refreshing, isFalse);
    expect(failed.refreshFailure?.userMessage, isNot(contains('sensitive')));
    expect(engine.calls.where((call) => call == 'sync'), hasLength(2));
  });

  test(
    'initial portfolio failure can retry without bypassing wallet state',
    () async {
      final engine = FakeWalletEngine()
        ..balance = _bitcoinBalance()
        ..balanceError = TimeoutException('temporary native timeout');
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        homeViewModelProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await expectLater(
        harness.container.read(homeViewModelProvider.future),
        throwsA(isA<AppFailureException>()),
      );
      engine.balanceError = null;

      await harness.container.read(homeViewModelProvider.notifier).retry();

      expect(
        harness.container.read(homeViewModelProvider).requireValue.portfolio,
        isA<WalletPortfolio>(),
      );
      expect(engine.calls.where((call) => call == 'balance'), hasLength(2));
    },
  );
}

WalletBalance _bitcoinBalance() {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: units);
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: onchain(2000),
    onchainFuture: onchain(2100),
    onchainSpendable: onchain(1500),
    onchainLocked: onchain(500),
    lightningOwned: lightning(1500),
    lightningSpendable: lightning(1000),
    lightningReceivable: lightning(2500),
  );
}
