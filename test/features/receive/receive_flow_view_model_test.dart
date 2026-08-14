import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/models/models.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'applies and clears an exact amount only after request success',
    () async {
      final harness = await PaymentFlowTestHarness.create();
      addTearDown(harness.dispose);
      final provider = receiveFlowViewModelProvider(
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

      expect(initial.request.amount, isNull);
      notifier.updateAmount('0.00000100');
      expect(await notifier.applyAmount(), isTrue);
      final applied = harness.container.read(provider).requireValue;
      expect(applied.request.amount?.units, 100);
      expect(applied.amountText, '0.000001');
      expect(harness.engine.createdReceiveAmount?.units, 100);

      notifier.updateAmount('');
      expect(await notifier.applyAmount(), isTrue);
      final cleared = harness.container.read(provider).requireValue;
      expect(cleared.request.amount, isNull);
      expect(cleared.amountText, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(harness.haptics.intents, [
        HapticIntent.success,
        HapticIntent.success,
      ]);
    },
  );

  test('suppresses overlap and preserves the prior QR on failure', () async {
    final engine = FakeWalletEngine();
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.bitcoinLightning,
    );
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final initial = await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);
    notifier.updateAmount('1');
    final gate = Completer<void>();
    engine.createReceiveGate = gate;

    final first = notifier.applyAmount();
    expect(await notifier.applyAmount(), isFalse);
    expect(
      harness.container.read(provider).requireValue.operation,
      ReceiveFlowOperation.generatingRequest,
    );
    engine.createReceiveError = const WalletValidationException(
      'Injected request failure.',
      field: 'amount',
    );
    gate.complete();

    expect(await first, isFalse);
    final failed = harness.container.read(provider).requireValue;
    expect(failed.request, initial.request);
    expect(failed.failure?.kind, AppFailureKind.validation);
    expect(
      engine.calls.where((call) => call == 'createReceiveRequest:start'),
      hasLength(2),
    );
    await Future<void>.delayed(Duration.zero);
    expect(harness.haptics.intents, [HapticIntent.error]);
  });

  test('invalid precision never regenerates a request', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final provider = receiveFlowViewModelProvider(
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
    final callsBefore = harness.engine.calls.length;

    notifier.updateAmount('0.000000001');

    expect(
      harness.container.read(provider).requireValue.amountInput.issue,
      WalletAmountInputIssue.precisionExceeded,
    );
    expect(await notifier.applyAmount(), isFalse);
    expect(harness.engine.calls, hasLength(callsBefore));
  });

  test(
    'Bitcoin Lightning invoice amount requires whole satoshis before native',
    () async {
      final harness = await PaymentFlowTestHarness.create();
      addTearDown(harness.dispose);
      final provider = receiveFlowViewModelProvider(
        WalletPaymentTarget.bitcoinLightning,
      );
      final subscription = harness.container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await harness.container.read(provider.future);
      final notifier = harness.container.read(provider.notifier);
      final callsBefore = harness.engine.calls.length;

      notifier.updateAmount('0.00000001001');
      final fractional = harness.container.read(provider).requireValue;
      expect(fractional.amountInput.units, 1001);
      expect(fractional.amountUsesSupportedGranularity, isFalse);
      expect(fractional.canApplyAmount, isFalse);
      expect(await notifier.applyAmount(), isFalse);
      expect(harness.engine.calls, hasLength(callsBefore));

      notifier.updateAmount('0.00000002');
      expect(await notifier.applyAmount(), isTrue);
      expect(harness.engine.createdReceiveAmount?.units, 2000);
    },
  );

  test('retryable initial request failure can recover explicitly', () async {
    final engine = FakeWalletEngine()
      ..createReceiveError = TimeoutException('temporary request timeout');
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    await expectLater(
      harness.container.read(provider.future),
      throwsA(isA<AppFailureException>()),
    );
    engine.createReceiveError = null;

    await harness.container.read(provider.notifier).retry();

    expect(
      harness.container.read(provider),
      isA<AsyncData<ReceiveFlowState>>(),
    );
    expect(
      engine.calls.where((call) => call == 'createReceiveRequest:start'),
      hasLength(2),
    );
  });

  test('terminal initial request failure cannot be retried', () async {
    final engine = FakeWalletEngine()
      ..createReceiveError = StateError('terminal request state');
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    await expectLater(
      harness.container.read(provider.future),
      throwsA(isA<AppFailureException>()),
    );
    engine.createReceiveError = null;

    await harness.container.read(provider.notifier).retry();

    expect(
      harness.container.read(provider),
      isA<AsyncError<ReceiveFlowState>>(),
    );
    expect(
      engine.calls.where((call) => call == 'createReceiveRequest:start'),
      hasLength(1),
    );
  });

  test('copy and share use injectable platform boundaries', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final state = await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);

    expect(await notifier.copyRequest(), isA<AppSuccess<void>>());
    expect(harness.clipboard.text, state.request.encodedRequest);
    const origin = ShareOrigin(left: 1, top: 2, width: 3, height: 4);
    expect(
      await notifier.shareRequest(origin: origin),
      isA<AppSuccess<ShareDisposition>>(),
    );
    expect(harness.share.sharedText, state.request.encodedRequest);
    expect(harness.share.sharedOrigin, same(origin));
    await Future<void>.delayed(Duration.zero);
    expect(harness.haptics.intents, [HapticIntent.lightImpact]);
  });
}
