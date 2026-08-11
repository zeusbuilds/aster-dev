import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/send/presentation/models/models.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/viewmodels.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('locks an invoice amount and never requests an on-chain fee', () async {
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.lightning,
    );
    final invoiceAmount = WalletAmount.lightning(
      assetId: WalletAsset.bitcoin.id,
      units: 1001,
    );
    final engine = FakeWalletEngine()
      ..balance = _balance(onchainSpendable: 1000, lightningSpendable: 5000)
      ..decodedInvoice = WalletPaymentPreview(
        route: route,
        encodedDestination: 'lnbcrt1invoice',
        displayDestination: 'lnbcrt1invoice',
        amount: invoiceAmount,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      );
    final harness = await PaymentFlowTestHarness.create(engine: engine);
    addTearDown(harness.dispose);
    final provider = sendFlowViewModelProvider(
      WalletPaymentTarget.bitcoinLightning,
    );
    final subscription = harness.container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await harness.container.read(provider.future);
    final notifier = harness.container.read(provider.notifier);

    notifier.updateDestination('lnbcrt1invoice');
    expect(await notifier.validateDestination(), isTrue);
    final locked = harness.container.read(provider).requireValue;
    expect(locked.amountIsLocked, isTrue);
    expect(locked.amountText, '0.00000001001');
    notifier.updateAmount('10');
    expect(
      harness.container.read(provider).requireValue.amountText,
      locked.amountText,
    );

    expect(await notifier.submit(), isTrue);
    expect(engine.sentPaymentCommand?.amount, invoiceAmount);
    expect(engine.sentPaymentCommand?.feeRate, isNull);
    expect(engine.calls, isNot(contains('estimateFeeRate')));
  });

  test(
    'stale fee and insufficient funds fail before native mutation',
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
        harness.container.read(provider).requireValue.failure?.code,
        'payment_fee_refresh_required',
      );
      expect(engine.calls, isNot(contains('sendPayment:start')));
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
        ..sendPaymentError = const WalletValidationException(
          'Injected send failure.',
          field: 'amount',
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
      expect(failed.failure?.kind, AppFailureKind.validation);
      await Future<void>.delayed(Duration.zero);
      expect(harness.haptics.intents, [HapticIntent.error]);
    },
  );

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

      final capabilities = await harness.container.read(
        walletPaymentCapabilitiesProvider.future,
      );

      expect(
        capabilities.map((capability) => capability.target),
        WalletPaymentTarget.values,
      );
      expect(capabilities.map((capability) => capability.isAvailable), [
        true,
        true,
        false,
        false,
      ]);
    },
  );
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
