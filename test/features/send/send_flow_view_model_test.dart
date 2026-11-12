import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/send/presentation/models/models.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late clipboard data cannot replace a different wallet form', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    harness.clipboard
      ..text = 'old-wallet-recipient'
      ..readGate = Completer<void>();
    final pending = harness.container
        .read(provider.notifier)
        .pasteDestination();
    final old = harness.container
        .read(walletViewModelProvider)
        .requireValue
        .activeWallet!;
    final next = WalletProfile(
      id: '2' * 32,
      name: 'Other',
      createdAt: old.createdAt,
      updatedAt: old.updatedAt,
      environment: old.environment,
      state: WalletProfileState.ready,
      storageToken: 'b' * 32,
    );
    harness.container
        .read(walletViewModelProvider.notifier)
        .adoptCommittedRegistry(
          WalletRegistry(profiles: [old, next], activeWalletId: next.id),
        );
    await harness.container.pump();
    final rebuilt = await harness.container.read(provider.future);
    harness.clipboard.readGate!.complete();
    expect(await pending, isA<AppFailureResult<String>>());
    expect(harness.container.read(provider).requireValue, same(rebuilt));
    expect(rebuilt.walletId, next.id);
    expect(rebuilt.destination, isEmpty);
    expect(harness.haptics.intents, isEmpty);
  });

  test('a retained Send form discards the old wallet review when wallet identity changes', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final initial = await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await notifier.validateDestination(), isTrue);
    final old = harness.container
        .read(walletViewModelProvider)
        .requireValue
        .activeWallet!;
    final next = WalletProfile(
      id: '2' * 32,
      name: 'Other',
      createdAt: old.createdAt,
      updatedAt: old.updatedAt,
      environment: old.environment,
      state: WalletProfileState.ready,
      storageToken: 'b' * 32,
    );
    harness.container
        .read(walletViewModelProvider.notifier)
        .adoptCommittedRegistry(
          WalletRegistry(profiles: [old, next], activeWalletId: next.id),
        );
    await harness.container.pump();
    final rebuilt = await harness.container.read(provider.future);
    expect(initial.walletId, old.id);
    expect(rebuilt.walletId, next.id);
    expect(rebuilt.preview, isNull);
    expect(rebuilt.destination, isEmpty);
    expect(await notifier.submit(), isFalse);
    expect(harness.engine.calls, isNot(contains('preparePaymentOperation')));
  });

  test('an accepted payment survives a form rebuild without publishing into the replacement form', () async {
    final now = DateTime.utc(2026, 10, 24);
    final engine = FakeWalletEngine()
      ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: now,
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => now,
    );
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await notifier.validateDestination(), isTrue);
    notifier.updateAmount('0.00000001');
    engine.sendPaymentGate = Completer<void>();
    final sending = notifier.submit();
    for (
      var turn = 0;
      turn < 100 && !engine.calls.contains('sendPayment:start');
      turn += 1
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(engine.calls, contains('sendPayment:start'));
    harness.container.invalidate(provider);
    final replacement = harness.container.read(provider.future);
    engine.sendPaymentGate!.complete();
    expect(await sending, isTrue);
    expect((await replacement).result, isNull);
    final receipt = await harness.repository.paymentSubmissionStatus();
    expect(
      (receipt as AppSuccess<WalletPaymentSubmission?>).value?.outcome,
      WalletPaymentSubmissionOutcome.accepted,
    );
    expect(engine.paymentOperations.dispatchCount, 1);
  });

  for (final feeRead in [true, false]) {
    test(
      '${feeRead ? 'fee' : 'balance'} recovery rejects completion after provider rebuild',
      () async {
        final now = DateTime.utc(2026, 10, 16);
        final engine = FakeWalletEngine()
          ..feeEstimate = WalletFeeRateEstimate(
            targetBlocks: 6,
            satsPerVbyte: 2,
            observedAt: now,
          );
        final harness = await PaymentFlowTestHarness.create(
          engine: engine,
          clock: () => now,
        );
        addTearDown(harness.dispose);
        final provider = sendFlowViewModelProvider(
          WalletPaymentTarget.bitcoinOnchain,
        );
        final subscription = harness.container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        await harness.container.read(provider.future);
        final notifier = harness.container.read(provider.notifier);
        notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
        expect(await notifier.validateDestination(), isTrue);
        final oldGate = Completer<void>();
        if (feeRead) {
          engine.feeEstimateGate = oldGate;
          engine.feeEstimateStarted = Completer<void>();
        } else {
          engine.balanceGate = oldGate;
        }
        final oldRead = feeRead
            ? notifier.refreshFee(silent: true)
            : notifier.refreshBalance(silent: true);
        if (feeRead) {
          await engine.feeEstimateStarted!.future;
        } else {
          while (engine.calls.where((call) => call == 'balance').length < 2) {
            await Future<void>.delayed(Duration.zero);
          }
        }
        final newLoadGate = Completer<void>();
        engine.feeEstimateGate = null;
        engine.balanceGate = newLoadGate;
        harness.container.invalidate(provider);
        final next = harness.container.read(provider.future);
        expect(harness.container.read(provider).isLoading, isTrue);
        expect(await notifier.refreshFee(silent: true), isFalse);
        expect(await notifier.refreshBalance(silent: true), isFalse);
        oldGate.complete();
        expect(await oldRead, isFalse);
        expect(harness.container.read(provider).isLoading, isTrue);
        newLoadGate.complete();
        final loaded = await next;
        expect(loaded.preview, isNull);
        expect(loaded.destination, isEmpty);
        expect(harness.container.read(provider).requireValue, same(loaded));
        expect(harness.haptics.intents, isEmpty);
        expect(engine.calls, isNot(contains('sendPayment:start')));
      },
    );
  }

  test('retained failures reject dedicated clipboard and fee operations', () {
    const failure = AppFailure(
      code: 'operation_failed',
      kind: AppFailureKind.unknown,
      userMessage: 'The operation failed.',
      retryable: false,
    );

    expect(
      () => SendFlowFailure(
        operation: SendFlowOperation.readingClipboard,
        failure: failure,
      ),
      throwsArgumentError,
    );
    expect(
      () => SendFlowFailure(
        operation: SendFlowOperation.refreshingFee,
        failure: failure,
      ),
      throwsArgumentError,
    );
  });

  for (final target in [
    WalletPaymentTarget.bitcoinOnchain,
    WalletPaymentTarget.usdtOnchain,
  ]) {
    test(
      'Continue prepares exactly one ${target.assetKind.name} balance and rejects overlap',
      () async {
        final rgb = target.assetKind == WalletAssetKind.usdt;
        final destination = rgb
            ? 'rgb:prepared-recipient'
            : 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
        final engine = FakeWalletEngine()
          ..balance = rgb
              ? testRgbBalance(1000)
              : _balance(onchainSpendable: 1000, lightningSpendable: 0);
        final harness = await PaymentFlowTestHarness.create(
          engine: engine,
          services: testRgbServices,
        );
        addTearDown(harness.dispose);
        final provider = sendFlowViewModelProvider(target);
        final subscription = harness.container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        await harness.container.read(provider.future);
        await harness.container.read(walletViewModelProvider.future);
        final notifier = harness.container.read(provider.notifier);
        notifier.updateDestination(destination);
        expect(await notifier.validateDestination(), isTrue);
        final validated = harness.container.read(provider).requireValue;
        expect(validated.balancePreparedForDestination, isFalse);
        expect(engine.calls.where((call) => call == 'balance'), hasLength(1));
        engine.balance = rgb
            ? testRgbBalance(2000)
            : _balance(onchainSpendable: 2000, lightningSpendable: 0);
        engine.balanceGate = Completer<void>();
        final pending = notifier.prepareAmount();
        await Future<void>.delayed(Duration.zero);
        expect(
          harness.container.read(provider).requireValue.operation,
          SendFlowOperation.preparingAmount,
        );
        expect(await notifier.prepareAmount(), isFalse);
        expect(await notifier.validateDestination(), isFalse);
        notifier.updateDestination('different recipient');
        expect(
          harness.container.read(provider).requireValue.destination,
          destination,
        );
        expect(engine.calls.where((call) => call == 'balance'), hasLength(2));
        engine.balanceGate!.complete();
        expect(await pending, isTrue);
        final prepared = harness.container.read(provider).requireValue;
        expect(prepared.preview, validated.preview);
        expect(prepared.destination, destination);
        expect(prepared.availableUnits, 2000);
        expect(prepared.balancePreparedForDestination, isTrue);
        expect(prepared.operation, isNull);
        expect(engine.requestedBalanceAsset?.kind, target.assetKind);
        expect(
          prepared.copyWith(preview: null).balancePreparedForDestination,
          isFalse,
        );
        expect(
          prepared.copyWith(balancePreparedForDestination: false),
          isNot(prepared),
        );
        expect(engine.calls, isNot(contains('sendPayment:start')));
        expect(await notifier.validateDestination(), isTrue);
        expect(
          harness.container
              .read(provider)
              .requireValue
              .balancePreparedForDestination,
          isFalse,
        );
        notifier.updateDestination('new recipient');
        expect(
          harness.container
              .read(provider)
              .requireValue
              .balancePreparedForDestination,
          isFalse,
        );
        expect(harness.container.read(provider).requireValue.preview, isNull);
      },
    );
  }

  for (final retryable in [true, false]) {
    test(
      'failed Continue balance read stays unprepared and ${retryable ? 'retries deliberately' : 'permits editing'}',
      () async {
        final engine = FakeWalletEngine()
          ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0);
        final harness = await PaymentFlowTestHarness.create(engine: engine);
        addTearDown(harness.dispose);
        final provider = sendFlowViewModelProvider(
          WalletPaymentTarget.bitcoinOnchain,
        );
        final subscription = harness.container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        await harness.container.read(provider.future);
        await harness.container.read(walletViewModelProvider.future);
        final notifier = harness.container.read(provider.notifier);
        notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
        expect(await notifier.validateDestination(), isTrue);
        engine.balanceError = retryable
            ? TimeoutException('temporary balance timeout')
            : StateError('terminal balance failure');
        expect(await notifier.prepareAmount(), isFalse);
        final failed = harness.container.read(provider).requireValue;
        expect(
          failed.failureFor(SendFlowOperation.preparingAmount)?.retryable,
          retryable,
        );
        expect(failed.balancePreparedForDestination, isFalse);
        expect(failed.availableUnits, 1000);
        expect(failed.canChangeDestination, isTrue);
        expect(
          failed.canStart(SendFlowOperation.validatingDestination),
          retryable,
        );
        expect(failed.canStart(SendFlowOperation.submitting), isFalse);
        expect(await notifier.submit(), isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(engine.calls.where((call) => call == 'balance'), hasLength(2));
        engine.balanceError = null;
        if (!retryable) {
          notifier.updateDestination(
            'bitcoin:mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
          );
        }
        expect(await notifier.validateDestination(), isTrue);
        expect(await notifier.prepareAmount(), isTrue);
        expect(
          harness.container
              .read(provider)
              .requireValue
              .balancePreparedForDestination,
          isTrue,
        );
        expect(engine.calls.where((call) => call == 'balance'), hasLength(3));
        expect(engine.calls, isNot(contains('sendPayment:start')));
      },
    );
  }

  for (final target in [
    WalletPaymentTarget.bitcoinOnchain,
    WalletPaymentTarget.usdtOnchain,
  ]) {
    test(
      'Continue rejects a different asset balance for ${target.assetKind.name} without locking input',
      () async {
        final rgb = target.assetKind == WalletAssetKind.usdt;
        final bitcoin = _balance(onchainSpendable: 1000, lightningSpendable: 0);
        final usdt = testRgbBalance(2000);
        final engine = FakeWalletEngine()..balance = rgb ? usdt : bitcoin;
        final harness = await PaymentFlowTestHarness.create(
          engine: engine,
          services: testRgbServices,
        );
        addTearDown(harness.dispose);
        final provider = sendFlowViewModelProvider(target);
        final subscription = harness.container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        await harness.container.read(provider.future);
        await harness.container.read(walletViewModelProvider.future);
        final notifier = harness.container.read(provider.notifier);
        notifier.updateDestination(
          rgb ? 'rgb:prepared-recipient' : 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
        );
        expect(await notifier.validateDestination(), isTrue);
        final validated = harness.container.read(provider).requireValue;
        engine.balanceResultOverride = rgb ? bitcoin : usdt;

        // The fake bypasses its usual matching-asset assertion deliberately.
        // A malformed adapter result must become owned failure, not escape.
        expect(await notifier.prepareAmount(), isFalse);
        final rejected = harness.container.read(provider).requireValue;
        final failure = rejected.failureFor(SendFlowOperation.preparingAmount)!;
        expect(failure.code, 'payment_balance_invalid');
        expect(failure.kind, AppFailureKind.protocol);
        expect(failure.retryable, isFalse);
        expect(failure.requiresReconciliation, isFalse);
        expect(rejected.balance, validated.balance);
        expect(rejected.availableUnits, rgb ? 2000 : 1000);
        expect(rejected.balancePreparedForDestination, isFalse);
        expect(rejected.operation, isNull);
        expect(rejected.canChangeDestination, isTrue);
        expect(
          rejected.canStart(SendFlowOperation.validatingDestination),
          isFalse,
        );
        expect(await notifier.submit(), isFalse);
        expect(engine.calls.where((call) => call == 'balance'), hasLength(2));
        expect(engine.calls, isNot(contains('sendPayment:start')));

        // The bad result never clears a terminal failure implicitly. Editing
        // the recipient permits a new deliberate, valid check.
        notifier.updateDestination(
          rgb
              ? 'rgb:another-recipient'
              : 'bitcoin:mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
        );
        engine.balanceResultOverride = null;
        expect(await notifier.validateDestination(), isTrue);
        expect(await notifier.prepareAmount(), isTrue);
        expect(
          harness.container
              .read(provider)
              .requireValue
              .balancePreparedForDestination,
          isTrue,
        );
        expect(engine.calls.where((call) => call == 'balance'), hasLength(3));
        expect(engine.calls, isNot(contains('sendPayment:start')));
      },
    );
  }

  for (final departure in ['rebuild', 'wallet', 'background']) {
    test(
      'Continue balance completion rejects $departure ownership loss',
      () async {
        final engine = FakeWalletEngine()
          ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0);
        final harness = await PaymentFlowTestHarness.create(engine: engine);
        addTearDown(harness.dispose);
        final provider = sendFlowViewModelProvider(
          WalletPaymentTarget.bitcoinOnchain,
        );
        final subscription = harness.container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        await harness.container.read(provider.future);
        await harness.container.read(walletViewModelProvider.future);
        final notifier = harness.container.read(provider.notifier);
        notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
        expect(await notifier.validateDestination(), isTrue);
        engine.balance = _balance(
          onchainSpendable: 2000,
          lightningSpendable: 0,
        );
        engine.balanceGate = Completer<void>();
        final pending = notifier.prepareAmount();
        await Future<void>.delayed(Duration.zero);
        Future<SendFlowState>? rebuilt;
        switch (departure) {
          case 'rebuild':
            harness.container.invalidate(provider);
            rebuilt = harness.container.read(provider.future);
          case 'wallet':
            final profile = WalletProfile(
              id: '33333333333333333333333333333333',
              name: 'Changed wallet',
              createdAt: DateTime.utc(2026, 10, 17),
              updatedAt: DateTime.utc(2026, 10, 17),
              environment: BlockchainEnvironment.regtest,
              state: WalletProfileState.ready,
              storageToken: '44444444444444444444444444444444',
            );
            harness.container
                .read(walletViewModelProvider.notifier)
                .adoptCommittedRegistry(
                  WalletRegistry(
                    profiles: [profile],
                    activeWalletId: profile.id,
                  ),
                );
          case 'background':
            await harness.container
                .read(walletLifecycleViewModelProvider.notifier)
                .handle(AppLifecycleState.inactive);
        }
        engine.balanceGate!.complete();
        expect(await pending, isFalse);
        if (departure == 'wallet') {
          await harness.container.pump();
          rebuilt = harness.container.read(provider.future);
        }
        if (rebuilt != null) await rebuilt;
        final discarded = harness.container.read(provider).requireValue;
        expect(discarded.balancePreparedForDestination, isFalse);
        expect(discarded.preview, isNull);
        expect(discarded.operation, isNull);
        expect(discarded.failure, isNull);
        if (departure == 'background') expect(discarded.availableUnits, 1000);
        if (departure == 'wallet') {
          expect(discarded.walletId, '33333333333333333333333333333333');
          expect(discarded.availableUnits, 2000);
        }
        expect(engine.calls, isNot(contains('sendPayment:start')));
      },
    );
  }

  test(
    'validates exact on-chain input and suppresses duplicate submit',
    () async {
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 5000)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 3,
          observedAt: DateTime.now().toUtc(),
        );
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final initial = await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);

      expect(initial.availableUnits, 1000);
      expect(initial.feeEstimate?.satsPerVbyte, 3);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.00000100');
      final ready = harness.container.read(provider).requireValue;
      expect(ready.amountInput.units, 100);
      expect(ready.canSubmitAt(DateTime.now().toUtc()), isTrue);

      final gate = Completer<void>();
      engine.sendPaymentGate = gate;
      final first = notifier.submit();
      expect(await notifier.submit(), isFalse);
      notifier.useMaxAmount();
      expect(
        harness.container.read(provider).requireValue.amountInput.units,
        100,
      );
      expect(
        harness.container.read(provider).requireValue.operation,
        SendFlowOperation.submitting,
      );
      gate.complete();

      expect(await first, isTrue);
      final completed = harness.container.read(provider).requireValue;
      expect(completed.result?.amount.units, 100);
      expect(engine.sentPaymentCommand?.amount.units, 100);
      expect(engine.sentPaymentCommand?.feeRate?.satsPerVbyte, 3);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(harness.haptics.intents, [HapticIntent.success]);
    },
  );

  for (final (unit, expected) in [('btc', '0.09989234'), ('sats', '9989234')]) {
    test('Max fills exact available Bitcoin in $unit display units', () async {
      final engine = FakeWalletEngine()
        ..balance = _balance(
          onchainSpendable: 9989234,
          lightningSpendable: 123000,
        );
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        preferenceValues: {'aster.settings.v1.bitcoin_unit': unit},
      );
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      final callsBefore = List<String>.of(engine.calls);

      notifier.useMaxAmount();

      final filled = harness.container.read(provider).requireValue;
      expect(filled.amountText, expected);
      expect(filled.amountInput.units, 9989234);
      expect(filled.amountInput.isValid, isTrue);
      expect(engine.calls, callsBefore);
    });
  }

  for (final useMax in [true, false]) {
    test(
      '${useMax ? 'Max' : 'Manually entered full balance'} warns before BTC dispatch and permits editing',
      () async {
        final now = DateTime.utc(2026, 10, 16);
        final engine = FakeWalletEngine()
          ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
          ..feeEstimate = WalletFeeRateEstimate(
            targetBlocks: 6,
            satsPerVbyte: 2,
            observedAt: now,
          );
        final harness = await PaymentFlowTestHarness.create(
          engine: engine,
          clock: () => now,
        );
        addTearDown(harness.dispose);
        final provider = sendFlowViewModelProvider(
          WalletPaymentTarget.bitcoinOnchain,
        );
        final subscription = harness.container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        await harness.container.read(provider.future);
        final notifier = harness.container.read(provider.notifier);
        notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
        expect(await notifier.validateDestination(), isTrue);
        if (useMax) {
          notifier.useMaxAmount();
        } else {
          notifier.updateAmount('0.00001000');
        }
        final callsBefore = List<String>.of(engine.calls);

        expect(await notifier.submit(), isFalse);

        final rejected = harness.container.read(provider).requireValue;
        expect(rejected.amountInput.units, 1000);
        expect(rejected.failure?.code, 'payment_amount_leaves_no_fee');
        expect(rejected.failure?.kind, AppFailureKind.validation);
        expect(
          rejected.failure?.userMessage,
          'Leave some BTC for the network fee. Lower the amount and try again.',
        );
        expect(rejected.failure?.requiresReconciliation, isFalse);
        expect(rejected.canChangeAmount, isTrue);
        expect(engine.calls, callsBefore);
        expect(
          await harness.repository.paymentSubmissionStatus(),
          isA<AppSuccess<WalletPaymentSubmission?>>().having(
            (status) => status.value,
            'journal entry',
            isNull,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(harness.haptics.intents, [HapticIntent.warning]);

        notifier.updateAmount('0.000001');
        expect(harness.container.read(provider).requireValue.failure, isNull);
        expect(await notifier.submit(), isTrue);
        expect(engine.sentPaymentCommand?.amount.units, 100);
        expect(
          engine.calls.where((call) => call == 'sendPayment:start'),
          hasLength(1),
        );
      },
    );
  }

  test(
    'Max preserves six-decimal USDT precision and permits all tokens',
    () async {
      final now = DateTime.utc(2026, 10, 16);
      const available = 9007199254740993;
      final engine = FakeWalletEngine()
        ..balance = testRgbBalance(available)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        )
        ..decodedInvoice = WalletPaymentPreview(
          route: testRgbRoute,
          encodedDestination: 'rgb:invoice',
          displayDestination: 'rgb:invoice',
        );
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        services: testRgbServices,
        clock: () => now,
      );
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.usdtOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('rgb:invoice');
      expect(await notifier.validateDestination(), isTrue);

      notifier.useMaxAmount();

      final filled = harness.container.read(provider).requireValue;
      expect(filled.amountText, '9007199254.740993');
      expect(filled.amountInput.units, available);
      expect(await notifier.submit(), isTrue);
      expect(engine.sentPaymentCommand?.amount.units, available);
      expect(harness.container.read(provider).requireValue.failure, isNull);
    },
  );

  test('locks an RGB invoice amount and uses an onchain fee', () async {
    final now = DateTime.utc(2026, 10, 13);
    final route = testRgbRoute;
    final invoiceAmount = WalletAmount.onchain(
      assetId: route.asset.id,
      units: 1001,
    );
    final engine = FakeWalletEngine()
      ..balance = testRgbBalance(5000)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: now,
      )
      ..decodedInvoice = WalletPaymentPreview(
        route: route,
        encodedDestination: 'rgb:invoice',
        displayDestination: 'rgb:invoice',
        amount: invoiceAmount,
        expiresAt: now.add(const Duration(hours: 1)),
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      services: testRgbServices,
      clock: () => now,
    );
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(WalletPaymentTarget.usdtOnchain);
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);

    notifier.updateDestination('rgb:invoice');
    expect(await notifier.validateDestination(), isTrue);
    final locked = harness.container.read(provider).requireValue;
    expect(locked.amountIsLocked, isTrue);
    expect(locked.amountText, '0.001001');
    notifier.updateAmount('10');
    notifier.useMaxAmount();
    expect(
      harness.container.read(provider).requireValue.amountText,
      locked.amountText,
    );

    expect(await notifier.submit(), isTrue);
    expect(engine.sentPaymentCommand?.amount, invoiceAmount);
    expect(engine.sentPaymentCommand?.feeRate, isNotNull);
    expect(engine.calls, contains('estimateFeeRate'));
  });

  test('Bitcoin Lightning fails closed before any payment work', () async {
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    final engine = FakeWalletEngine()
      ..balance = _balance(onchainSpendable: 0, lightningSpendable: 5000)
      ..decodedInvoice = WalletPaymentPreview(
        route: route,
        encodedDestination: 'lnbcrt1amountless',
        displayDestination: 'lnbcrt1amountless',
      );
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinLightning,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final callsBefore = List<String>.of(engine.calls);
    await expectLater(
      harness.container.read(provider.future),
      throwsA(
        isA<AppFailureException>().having(
          (error) => error.failure.code,
          'code',
          'lightning_not_released',
        ),
      ),
    );
    final notifier = harness.container.read(provider.notifier);

    notifier.updateDestination('lnbcrt1amountless');
    expect(await notifier.validateDestination(), isFalse);
    notifier.updateAmount('0.00000001001');
    expect(await notifier.submit(), isFalse);
    notifier.updateAmount('0.00000002');
    expect(await notifier.submit(), isFalse);
    await notifier.retry();
    expect(engine.calls, callsBefore);
  });

  test('suppresses overlapping destination validation', () async {
    final route = testRgbRoute;
    final gate = Completer<void>();
    final engine = FakeWalletEngine()
      ..balance = testRgbBalance(5000)
      ..decodeInvoiceGate = gate
      ..decodedInvoice = WalletPaymentPreview(
        route: route,
        encodedDestination: 'rgb:invoice',
        displayDestination: 'rgb:invoice',
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      services: testRgbServices,
    );
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(WalletPaymentTarget.usdtOnchain);
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('rgb:invoice');

    final first = notifier.validateDestination();
    await Future<void>.delayed(Duration.zero);
    expect(await notifier.validateDestination(), isFalse);
    expect(
      engine.calls.where((call) => call == 'decodeInvoice:start'),
      hasLength(1),
    );

    gate.complete();
    expect(await first, isTrue);
  });

  test(
    'destination validation cannot publish after the provider rebuilds',
    () async {
      final gate = Completer<void>();
      final engine = FakeWalletEngine()
        ..balance = testRgbBalance(5000)
        ..decodeInvoiceGate = gate
        ..decodedInvoice = WalletPaymentPreview(
          route: testRgbRoute,
          encodedDestination: 'rgb:old-invoice',
          displayDestination: 'rgb:old-invoice',
        );
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        services: testRgbServices,
      );
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.usdtOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('rgb:old-invoice');
      final pending = notifier.validateDestination();
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, contains('decodeInvoice:start'));
      harness.container.invalidate(provider);
      final rebuilt = harness.container.read(provider.future);
      gate.complete();
      expect(await pending, isFalse);
      final loaded = await rebuilt;
      expect(loaded.destination, isEmpty);
      expect(loaded.preview, isNull);
      expect(loaded.failure, isNull);
    },
  );

  test(
    'stale returned fee and insufficient funds fail before native mutation',
    () async {
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 50, lightningSpendable: 0)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 3),
          ),
        );
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);

      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('100');
      expect(await notifier.submit(), isFalse);
      expect(
        harness.container.read(provider).requireValue.failure?.code,
        'payment_balance_insufficient',
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));

      notifier.updateAmount('0.00000001');
      expect(await notifier.submit(), isFalse);
      expect(
        harness.container.read(provider).requireValue.feeFailure?.code,
        walletFeeReviewRequiredFailure.code,
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));
    },
  );

  test(
    'missing fee retries only on Send and requires review before dispatch',
    () async {
      var now = DateTime.utc(2026, 10, 17);
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
        ..feeEstimateError = TimeoutException('temporary quote read failure');
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        clock: () => now,
      );
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.000001');
      final unavailable = harness.container.read(provider).requireValue;
      expect(unavailable.canAttemptSubmitAt(now), isTrue);
      expect(unavailable.canSubmitAt(now), isFalse);
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(1),
      );

      expect(await notifier.submit(), isFalse);
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(2),
      );
      final failed = harness.container.read(provider).requireValue;
      expect(failed.feeFailure?.retryable, isTrue);
      expect(failed.canAttemptSubmitAt(now), isTrue);
      expect(failed.canSubmitAt(now), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(2),
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));

      now = now.add(const Duration(seconds: 1));
      engine.feeEstimateError = null;
      engine.feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 4,
        observedAt: now,
      );
      expect(await notifier.submit(), isFalse);
      final reviewed = harness.container.read(provider).requireValue;
      expect(reviewed.feeEstimate?.satsPerVbyte, 4);
      expect(reviewed.feeFailure, isNull);
      expect(reviewed.failure, walletFeeUpdatedReviewFailure);
      expect(
        reviewed.failure?.userMessage,
        'The fee is updated. Review it and send again.',
      );
      expect(reviewed.canSubmitAt(now), isTrue);
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(3),
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));

      expect(await notifier.submit(), isTrue);
      expect(await notifier.submit(), isFalse);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(4),
      );
    },
  );

  test(
    'stale-fee Send owns one read and rejects simultaneous attempts',
    () async {
      var now = DateTime.utc(2026, 10, 17);
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        );
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        clock: () => now,
      );
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.000001');
      now = now.add(const Duration(minutes: 3));
      engine.feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 4,
        observedAt: now,
      );
      engine.feeEstimateGate = Completer<void>();
      engine.feeEstimateStarted = Completer<void>();
      final pending = notifier.submit();
      await engine.feeEstimateStarted!.future;
      expect(
        harness.container.read(provider).requireValue.canAttemptSubmitAt(now),
        isFalse,
      );
      expect(await notifier.submit(), isFalse);
      expect(await notifier.refreshFee(), isFalse);
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(2),
      );
      engine.feeEstimateGate!.complete();
      expect(await pending, isFalse);
      expect(
        harness.container.read(provider).requireValue.failure,
        walletFeeUpdatedReviewFailure,
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));
      expect(await notifier.submit(), isTrue);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
    },
  );

  test(
    'fee expiring during pre-dispatch check refreshes without resubmitting',
    () async {
      var now = DateTime.utc(2026, 10, 17);
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        );
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        clock: () => now,
      );
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.000001');
      engine.feeEstimateGate = Completer<void>();
      engine.feeEstimateStarted = Completer<void>();
      final pending = notifier.submit();
      await engine.feeEstimateStarted!.future;
      now = now.add(const Duration(minutes: 3));
      engine.feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 5,
        observedAt: now,
      );
      engine.feeEstimateGate!.complete();
      expect(await pending, isFalse);
      final reviewed = harness.container.read(provider).requireValue;
      expect(reviewed.failure, walletFeeUpdatedReviewFailure);
      expect(reviewed.feeEstimate?.satsPerVbyte, 5);
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(3),
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));
      expect(await notifier.submit(), isTrue);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
    },
  );

  test(
    'invoice expiring during fee recovery reports expiry instead of review',
    () async {
      var now = DateTime.utc(2026, 10, 17);
      final engine = FakeWalletEngine()
        ..balance = testRgbBalance(5000)
        ..feeEstimateError = TimeoutException('temporary quote read failure')
        ..decodedInvoice = WalletPaymentPreview(
          route: testRgbRoute,
          encodedDestination: 'rgb:expiring-invoice',
          displayDestination: 'rgb:expiring-invoice',
          expiresAt: now.add(const Duration(seconds: 4)),
        );
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        services: testRgbServices,
        clock: () => now,
      );
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.usdtOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('rgb:expiring-invoice');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.001');
      engine.feeEstimateError = null;
      engine.feeEstimateGate = Completer<void>();
      engine.feeEstimateStarted = Completer<void>();
      final pending = notifier.submit();
      await engine.feeEstimateStarted!.future;
      now = now.add(const Duration(seconds: 5));
      engine.feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 4,
        observedAt: now,
      );
      engine.feeEstimateGate!.complete();
      expect(await pending, isFalse);
      final expired = harness.container.read(provider).requireValue;
      expect(expired.failure?.code, 'payment_request_expired');
      expect(
        expired.failure?.userMessage,
        'This invoice has expired. Enter a new invoice to continue.',
      );
      expect(expired.feeFailure, isNull);
      expect(expired.canAttemptSubmitAt(now), isFalse);
      expect(await notifier.submit(), isFalse);
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(2),
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));
    },
  );

  test(
    'submit fee recovery cannot publish after the provider rebuilds',
    () async {
      final now = DateTime.utc(2026, 10, 17);
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
        ..feeEstimateError = TimeoutException('temporary quote read failure');
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        clock: () => now,
      );
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.000001');
      engine.feeEstimateError = null;
      engine.feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 4,
        observedAt: now,
      );
      final oldGate = Completer<void>();
      engine.feeEstimateGate = oldGate;
      engine.feeEstimateStarted = Completer<void>();
      final pending = notifier.submit();
      await engine.feeEstimateStarted!.future;
      final nextLoadGate = Completer<void>();
      engine.balanceGate = nextLoadGate;
      engine.feeEstimateGate = null;
      harness.container.invalidate(provider);
      final rebuilt = harness.container.read(provider.future);
      expect(harness.container.read(provider).isLoading, isTrue);
      oldGate.complete();
      expect(await pending, isFalse);
      expect(harness.container.read(provider).isLoading, isTrue);
      nextLoadGate.complete();
      final loaded = await rebuilt;
      expect(loaded.preview, isNull);
      expect(loaded.failure, isNull);
      expect(engine.calls, isNot(contains('sendPayment:start')));
    },
  );

  test(
    'submitted payment completion cannot overwrite a rebuilt form',
    () async {
      final now = DateTime.utc(2026, 10, 17);
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: now,
        )
        ..sendPaymentGate = Completer<void>();
      final harness = await PaymentFlowTestHarness.create(
        engine: engine,
        clock: () => now,
      );
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.000001');
      final pending = notifier.submit();
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, contains('sendPayment:start'));
      harness.container.invalidate(provider);
      final rebuilt = harness.container.read(provider.future);
      engine.sendPaymentGate!.complete();
      expect(await pending, isTrue);
      final loaded = await rebuilt;
      expect(loaded.destination, isEmpty);
      expect(loaded.result, isNull);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
    },
  );

  test(
    'native send failure preserves review state and emits error once',
    () async {
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: DateTime.now().toUtc(),
        )
        ..sendPaymentError = const WalletPaymentRejectedBeforeDispatchException(
          AppFailure(
            code: 'wallet_validation',
            kind: AppFailureKind.validation,
            userMessage: 'Check the entered information and try again.',
            retryable: false,
          ),
        );
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.000001');

      expect(await notifier.submit(), isFalse);

      final failed = harness.container.read(provider).requireValue;
      expect(failed.destination, 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(failed.amountInput.units, 100);
      expect(failed.result, isNull);
      // The certificate preserves nonexecution without exposing raw preparation errors.
      expect(failed.failure?.kind, AppFailureKind.unavailable);
      await Future<void>.delayed(Duration.zero);
      expect(harness.haptics.intents, [HapticIntent.error]);
    },
  );

  test('outcome-unknown send quarantines every route command', () async {
    final engine = FakeWalletEngine()
      ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: DateTime.now().toUtc(),
      )
      ..sendPaymentError = const RlnOperationTimeoutException(
        operation: 'rlnSendBtc',
        timeout: Duration(minutes: 2),
      );
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    const destination = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
    notifier.updateDestination(destination);
    expect(await notifier.validateDestination(), isTrue);
    notifier.updateAmount('0.000001');

    expect(await notifier.submit(), isFalse);
    final failed = harness.container.read(provider).requireValue;
    expect(failed.failure?.outcomeUnknown, isTrue);
    expect(failed.requiresReconciliation, isTrue);
    expect(failed.canEditPayment, isFalse);
    expect(failed.canAttemptSubmitAt(DateTime.now().toUtc()), isFalse);
    expect(failed.canSubmitAt(DateTime.now().toUtc()), isFalse);
    final callsAfterFailure = List<String>.of(engine.calls);

    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfo');
    notifier.updateAmount('0.000002');
    notifier.useMaxAmount();
    expect(await notifier.validateDestination(), isFalse);
    expect(await notifier.prepareAmount(), isFalse);
    expect(await notifier.refreshBalance(), isFalse);
    expect(await notifier.refreshFee(), isFalse);
    expect(await notifier.pasteDestination(), isA<AppFailureResult<String>>());
    expect(await notifier.submit(), isFalse);

    final quarantined = harness.container.read(provider).requireValue;
    expect(quarantined, failed);
    expect(quarantined.destination, destination);
    expect(quarantined.amountText, '0.000001');
    expect(engine.calls, callsAfterFailure);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
  });

  test('known retained send state quarantines every route command', () async {
    final engine = FakeWalletEngine()
      ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: DateTime.now().toUtc(),
      )
      ..sendPaymentError = const AppFailureException(
        AppFailure(
          code: 'wallet_payment_reconciliation_required',
          kind: AppFailureKind.storage,
          userMessage: 'Restart before continuing wallet payments.',
          retryable: false,
          requiresReconciliation: true,
        ),
      );
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    const destination = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
    notifier.updateDestination(destination);
    expect(await notifier.validateDestination(), isTrue);
    notifier.updateAmount('0.000001');

    expect(await notifier.submit(), isFalse);
    final failed = harness.container.read(provider).requireValue;
    expect(failed.failure?.requiresReconciliation, isTrue);
    expect(failed.failure?.outcomeUnknown, isFalse);
    expect(failed.requiresReconciliation, isTrue);
    expect(failed.canEditPayment, isFalse);
    final callsAfterFailure = List<String>.of(engine.calls);

    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfo');
    notifier.updateAmount('0.000002');
    notifier.useMaxAmount();
    expect(await notifier.validateDestination(), isFalse);
    expect(await notifier.refreshBalance(), isFalse);
    expect(await notifier.refreshFee(), isFalse);
    expect(await notifier.submit(), isFalse);

    expect(harness.container.read(provider).requireValue, failed);
    expect(engine.calls, callsAfterFailure);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
  });

  test(
    'terminal submit failure cannot be laundered by another operation',
    () async {
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: DateTime.now().toUtc(),
        )
        ..sendPaymentError = const WalletPaymentRejectedBeforeDispatchException(
          AppFailure(
            code: 'wallet_validation',
            kind: AppFailureKind.validation,
            userMessage: 'Check the entered information and try again.',
            retryable: false,
          ),
        );
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.000001');

      expect(await notifier.submit(), isFalse);
      final failed = harness.container.read(provider).requireValue;
      expect(failed.retainedFailure?.operation, SendFlowOperation.submitting);
      expect(failed.failure?.retryable, isFalse);
      final callsAfterFailure = List<String>.of(engine.calls);
      engine.sendPaymentError = null;

      expect(await notifier.submit(), isFalse);
      expect(await notifier.validateDestination(), isFalse);
      expect(await notifier.refreshBalance(), isFalse);
      expect(await notifier.refreshFee(), isFalse);
      expect(engine.calls, callsAfterFailure);

      notifier.updateAmount('0.000002');
      expect(
        harness.container.read(provider).requireValue.retainedFailure,
        isNull,
      );
      expect(await notifier.submit(), isTrue);
      expect(
        engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(2),
      );
    },
  );

  test('a retryable engine error without proof of rejection cannot replay dispatch', () async {
    final engine = FakeWalletEngine()
      ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
      ..feeEstimate = WalletFeeRateEstimate(
        targetBlocks: 6,
        satsPerVbyte: 2,
        observedAt: DateTime.now().toUtc(),
      )
      ..sendPaymentError = const AppFailureException(
        AppFailure(
          code: 'payment_route_temporarily_unavailable',
          kind: AppFailureKind.unavailable,
          userMessage: 'The selected payment route is temporarily unavailable.',
          retryable: true,
        ),
      );
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
    expect(await notifier.validateDestination(), isTrue);
    notifier.updateAmount('0.000001');

    expect(await notifier.submit(), isFalse);
    final failed = harness.container.read(provider).requireValue;
    expect(failed.failure?.retryable, isFalse);
    expect(failed.failure?.outcomeUnknown, isTrue);
    expect(failed.canStart(SendFlowOperation.submitting), isFalse);
    expect(failed.canStart(SendFlowOperation.refreshingBalance), isFalse);
    engine.sendPaymentError = null;

    expect(await notifier.refreshBalance(), isFalse);
    expect(await notifier.submit(), isFalse);
    expect(
      engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
  });

  test(
    'balance refresh failure is recoverable only by the same operation',
    () async {
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0);
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      engine.balanceError = TimeoutException('temporary balance timeout');

      expect(await notifier.refreshBalance(), isFalse);
      final failed = harness.container.read(provider).requireValue;
      expect(
        failed.retainedFailure?.operation,
        SendFlowOperation.refreshingBalance,
      );
      expect(failed.failure?.retryable, isTrue);
      expect(failed.canChangeAmount, isFalse);
      engine.balanceError = null;

      expect(await notifier.refreshFee(), isFalse);
      expect(await notifier.refreshBalance(), isTrue);
      expect(engine.calls.where((call) => call == 'balance'), hasLength(3));
    },
  );

  test(
    'terminal fee failure cannot be promoted into a retryable quote',
    () async {
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: DateTime.now().toUtc(),
        );
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      notifier.updateDestination('mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn');
      expect(await notifier.validateDestination(), isTrue);
      notifier.updateAmount('0.000001');
      engine.feeEstimateError = StateError('terminal fee state');

      expect(await notifier.refreshFee(), isFalse);
      final failed = harness.container.read(provider).requireValue;
      expect(failed.feeFailure?.retryable, isFalse);
      expect(failed.canRefreshFee, isFalse);
      expect(failed.canAttemptSubmitAt(DateTime.now().toUtc()), isFalse);
      final feeCalls = engine.calls
          .where((call) => call == 'estimateFeeRate')
          .length;
      engine.feeEstimateError = null;

      expect(await notifier.refreshFee(), isFalse);
      expect(await notifier.submit(), isFalse);
      expect(
        harness.container.read(provider).requireValue.feeFailure,
        failed.feeFailure,
      );
      expect(
        engine.calls.where((call) => call == 'estimateFeeRate'),
        hasLength(feeCalls),
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));
    },
  );

  test(
    'retryable fee failure can refresh without changing payment input',
    () async {
      final engine = FakeWalletEngine()
        ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
        ..feeEstimate = WalletFeeRateEstimate(
          targetBlocks: 6,
          satsPerVbyte: 2,
          observedAt: DateTime.now().toUtc(),
        );
      final harness = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(harness.dispose);
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      engine.feeEstimateError = TimeoutException('temporary fee timeout');

      expect(await notifier.refreshFee(), isFalse);
      expect(
        harness.container.read(provider).requireValue.canRefreshFee,
        isTrue,
      );
      engine.feeEstimateError = null;

      expect(await notifier.refreshFee(), isTrue);
      expect(harness.container.read(provider).requireValue.feeFailure, isNull);
    },
  );

  test('retryable initial Send failure can recover explicitly', () async {
    final engine = FakeWalletEngine()
      ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
      ..balanceError = TimeoutException('temporary balance timeout');
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    await expectLater(
      harness.container.read(provider.future),
      throwsA(isA<AppFailureException>()),
    );
    engine.balanceError = null;

    await harness.container.read(provider.notifier).retry();

    expect(harness.container.read(provider), isA<AsyncData<SendFlowState>>());
    expect(engine.calls.where((call) => call == 'balance'), hasLength(2));
  });

  test('initial retry is inert for an already-loaded Send form', () async {
    final engine = FakeWalletEngine()
      ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0);
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    notifier.updateDestination('pending recipient input');
    final callsBefore = List<String>.of(engine.calls);

    await notifier.retry();

    expect(
      harness.container.read(provider).requireValue.destination,
      'pending recipient input',
    );
    expect(engine.calls, callsBefore);
  });

  test('terminal initial Send failure cannot be retried', () async {
    final engine = FakeWalletEngine()
      ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 0)
      ..balanceError = StateError('terminal balance state');
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    await expectLater(
      harness.container.read(provider.future),
      throwsA(isA<AppFailureException>()),
    );
    engine.balanceError = null;

    await harness.container.read(provider.notifier).retry();

    expect(harness.container.read(provider), isA<AsyncError<SendFlowState>>());
    expect(engine.calls.where((call) => call == 'balance'), hasLength(1));
  });

  test(
    'payment capability provider preserves all four stable choices',
    () async {
      final harness = await PaymentFlowTestHarness.create();
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        walletPaymentCapabilitiesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final capabilities = harness.container.read(
        walletPaymentCapabilitiesProvider,
      );

      expect(
        capabilities.map((capability) => capability.target),
        WalletPaymentTarget.values,
      );
      expect(capabilities.map((capability) => capability.isAvailable), [
        true,
        false,
        false,
        false,
      ]);
    },
  );

  test(
    'paste adopts bounded clipboard text without exposing a plugin',
    () async {
      final harness = await PaymentFlowTestHarness.create();
      addTearDown(harness.dispose);
      harness.clipboard.text = '  mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn  ';
      final provider = sendFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final subscription = harness.container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await harness.container.read(provider.future);

      final result = await harness.container
          .read(provider.notifier)
          .pasteDestination();

      expect(result, isA<AppSuccess<String>>());
      expect(
        harness.container.read(provider).requireValue.destination,
        'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn',
      );
      await Future<void>.delayed(Duration.zero);
      expect(harness.haptics.intents, [HapticIntent.lightImpact]);
    },
  );

  test('rejects an expired invoice against the injected UTC clock', () async {
    final now = DateTime.utc(2026, 8, 11, 12);
    final route = testRgbRoute;
    final engine = FakeWalletEngine()
      ..balance = testRgbBalance(5000)
      ..decodedInvoice = WalletPaymentPreview(
        route: route,
        encodedDestination: 'rgb:expired',
        displayDestination: 'rgb:expired',
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      clock: () => now,
      services: testRgbServices,
    );
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(WalletPaymentTarget.usdtOnchain);
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);

    notifier.updateDestination('rgb:expired');

    expect(await notifier.validateDestination(), isFalse);
    expect(
      harness.container.read(provider).requireValue.failure?.code,
      'payment_request_expired',
    );
  });
}

WalletBalance _balance({
  required int onchainSpendable,
  required int lightningSpendable,
}) {
  WalletAmount onchain(int units) =>
      WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: units);
  WalletAmount lightning(int units) =>
      WalletAmount.lightning(assetId: WalletAsset.bitcoin.id, units: units);
  return WalletBalance(
    asset: WalletAsset.bitcoin,
    onchainSettled: onchain(onchainSpendable),
    onchainFuture: onchain(onchainSpendable),
    onchainSpendable: onchain(onchainSpendable),
    onchainLocked: onchain(0),
    lightningOwned: lightning(lightningSpendable),
    lightningSpendable: lightning(lightningSpendable),
    lightningReceivable: lightning(lightningSpendable),
  );
}
