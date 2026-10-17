import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/models/models.dart';
import 'package:aster/features/home/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  test('initial retry is inert for an already-loaded portfolio', () async {
    final engine = FakeWalletEngine()..balance = _bitcoinBalance();
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final subscription = harness.container.listen(
      homeViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    final initial = await harness.container.read(homeViewModelProvider.future);
    final callsBefore = List<String>.of(engine.calls);

    await harness.container.read(homeViewModelProvider.notifier).retry();

    expect(harness.container.read(homeViewModelProvider).requireValue, initial);
    expect(engine.calls, callsBefore);
  });

  test('terminal initial portfolio failure cannot be retried', () async {
    final engine = FakeWalletEngine()
      ..balance = _bitcoinBalance()
      ..balanceError = StateError('terminal wallet state');
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
      harness.container.read(homeViewModelProvider),
      isA<AsyncError<HomeState>>(),
    );
    expect(engine.calls.where((call) => call == 'balance'), hasLength(1));
  });

  test('reloads the read-only portfolio after a confirmed resume', () async {
    final engine = FakeWalletEngine()..balance = _bitcoinBalance();
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final subscription = harness.container.listen(
      homeViewModelProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    await harness.container.read(homeViewModelProvider.future);
    final lifecycle = harness.container.read(
      walletLifecycleViewModelProvider.notifier,
    );
    expect(await lifecycle.handle(AppLifecycleState.paused), isTrue);
    expect(await lifecycle.handle(AppLifecycleState.resumed), isTrue);
    await harness.container.read(homeViewModelProvider.future);

    expect(engine.calls.where((call) => call == 'balance'), hasLength(2));
    expect(engine.calls, containsAllInOrder(['shutdown', 'openPersisted']));
  });

  test('refresh cannot publish retained data or queue sync during a portfolio reload', () async {
    final engine = FakeWalletEngine()..balance = _bitcoinBalance();
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    final publications = <AsyncValue<HomeState>>[];
    final subscription = harness.container.listen<AsyncValue<HomeState>>(
      homeViewModelProvider,
      (previous, next) => publications.add(next),
    );
    final balanceGate = Completer<void>();
    addTearDown(() async {
      if (!balanceGate.isCompleted) balanceGate.complete();
      subscription.close();
      await harness.dispose();
    });
    final initial = await harness.container.read(homeViewModelProvider.future);
    final newerBalance = _bitcoinBalance(additionalConfirmedSatoshis: 10000000);
    engine
      ..balance = newerBalance
      ..balanceGate = balanceGate;

    harness.container.invalidate(homeViewModelProvider);
    await _waitFor(
      () =>
          harness.container.read(homeViewModelProvider).isLoading &&
          engine.calls.where((call) => call == 'balance').length == 2,
    );
    final reloading = harness.container.read(homeViewModelProvider);
    expect(reloading.value, same(initial));
    publications.clear();
    final callsBeforeRefresh = List<String>.of(engine.calls);
    bool? refreshResult;
    final refresh = harness.container
        .read(homeViewModelProvider.notifier)
        .refresh()
        .then((result) {
          refreshResult = result;
          return result;
        });

    await _waitFor(() => refreshResult != null);

    expect(refreshResult, isFalse);
    expect(harness.container.read(homeViewModelProvider), same(reloading));
    expect(publications, isEmpty);
    expect(engine.calls, callsBeforeRefresh);

    balanceGate.complete();
    final rebuilt = await harness.container.read(homeViewModelProvider.future);
    expect(await refresh, isFalse);
    expect(rebuilt.portfolio.bitcoin, newerBalance);
    expect(rebuilt.portfolio, isNot(initial.portfolio));
    expect(rebuilt.refreshing, isFalse);
    expect(rebuilt.refreshFailure, isNull);
    expect(engine.calls.where((call) => call == 'balance'), hasLength(2));
    expect(engine.calls.where((call) => call == 'sync'), isEmpty);
  });

  test('stale refresh cannot overwrite a newer provider generation', () async {
    final engine = FakeWalletEngine();
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    final subscription = harness.container.listen<AsyncValue<HomeState>>(
      homeViewModelProvider,
      (previous, next) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      await harness.dispose();
    });
    await harness.container.read(homeViewModelProvider.future);

    final syncGate = Completer<void>();
    engine.syncGate = syncGate;
    final refresh = harness.container
        .read(homeViewModelProvider.notifier)
        .refresh();
    await _waitFor(
      () => engine.calls.where((call) => call == 'sync').length == 1,
    );

    final balanceGate = Completer<void>();
    engine.balanceGate = balanceGate;
    harness.container.invalidate(homeViewModelProvider);
    await _waitFor(
      () => harness.container.read(homeViewModelProvider).isLoading,
    );

    engine.syncError = StateError('stale refresh failure');
    syncGate.complete();
    expect(await refresh, isFalse);
    await _waitFor(
      () => engine.calls.where((call) => call == 'balance').length >= 2,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      harness.container.read(homeViewModelProvider).isLoading,
      isTrue,
      reason: 'The newer build must retain publication ownership.',
    );

    balanceGate.complete();
    final rebuilt = await harness.container.read(homeViewModelProvider.future);
    expect(rebuilt.refreshFailure, isNull);
    expect(rebuilt.refreshing, isFalse);
  });

  test(
    'stale refresh cannot publish after the active wallet identity changes',
    () async {
      final engine = FakeWalletEngine()..balance = _bitcoinBalance();
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      final publications = <AsyncValue<HomeState>>[];
      final subscription = harness.container.listen<AsyncValue<HomeState>>(
        homeViewModelProvider,
        (previous, next) => publications.add(next),
      );
      final syncGate = Completer<void>();
      final balanceGate = Completer<void>();
      addTearDown(() async {
        if (!syncGate.isCompleted) syncGate.complete();
        if (!balanceGate.isCompleted) balanceGate.complete();
        subscription.close();
        await harness.dispose();
      });
      final initial = await harness.container.read(
        homeViewModelProvider.future,
      );
      final originalWallet = harness.container
          .read(walletViewModelProvider)
          .requireValue
          .activeWallet!;
      engine.syncGate = syncGate;
      final oldRefresh = harness.container
          .read(homeViewModelProvider.notifier)
          .refresh();
      await _waitFor(
        () => engine.calls.where((call) => call == 'sync').length == 1,
      );

      final nextWallet = WalletProfile(
        id: '22222222222222222222222222222222',
        name: 'Next',
        createdAt: originalWallet.createdAt,
        updatedAt: originalWallet.updatedAt,
        environment: originalWallet.environment,
        state: WalletProfileState.ready,
        storageToken: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      engine.balanceGate = balanceGate;
      // The registry emission owns this test's wallet change. The fake engine
      // supplies both snapshots; a native wallet switch is outside this scope.
      harness.container
          .read(walletViewModelProvider.notifier)
          .adoptCommittedRegistry(
            WalletRegistry(
              profiles: [originalWallet, nextWallet],
              activeWalletId: nextWallet.id,
            ),
          );
      await _waitFor(
        () => harness.container.read(homeViewModelProvider).isLoading,
      );
      final reloading = harness.container.read(homeViewModelProvider);
      publications.clear();

      engine.syncError = StateError('stale wallet refresh failure');
      syncGate.complete();
      expect(await oldRefresh, isFalse);
      await _waitFor(
        () => engine.calls.where((call) => call == 'balance').length == 2,
      );

      expect(
        harness.container
            .read(walletViewModelProvider)
            .requireValue
            .activeWallet,
        nextWallet,
      );
      expect(harness.container.read(homeViewModelProvider), same(reloading));
      expect(publications, isEmpty);
      final nextBalance = _bitcoinBalance(
        additionalConfirmedSatoshis: 10000000,
      );
      engine.balance = nextBalance;
      balanceGate.complete();

      final rebuilt = await harness.container.read(
        homeViewModelProvider.future,
      );
      expect(rebuilt.portfolio.bitcoin, nextBalance);
      expect(rebuilt.portfolio, isNot(initial.portfolio));
      expect(rebuilt.refreshFailure, isNull);
      expect(rebuilt.refreshing, isFalse);
      expect(engine.calls.where((call) => call == 'balance'), hasLength(2));
      expect(engine.calls.where((call) => call == 'sync'), hasLength(1));
    },
  );
}

WalletBalance _bitcoinBalance({int additionalConfirmedSatoshis = 0}) {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: units);
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: onchain(2000 + additionalConfirmedSatoshis),
    onchainFuture: onchain(2100 + additionalConfirmedSatoshis),
    onchainSpendable: onchain(1500 + additionalConfirmedSatoshis),
    onchainLocked: onchain(600),
    lightningOwned: lightning(1500),
    lightningSpendable: lightning(1000),
    lightningReceivable: lightning(2500),
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for Home ViewModel state.');
}
