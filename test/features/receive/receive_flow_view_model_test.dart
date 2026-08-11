import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/models/models.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/feedback/feedback.dart';
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
}
