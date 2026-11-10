import 'package:aster/core/core.dart';
import 'package:aster/features/send/presentation/models/models.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';

void main() {
  test('handoff is bounded, redacted, and consumed exactly once', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final handoff = harness.container.read(
      sendDestinationHandoffProvider.notifier,
    );

    final staged = handoff.stage('  lightning:invoice  ');
    expect(staged, isA<AppSuccess<void>>());
    final value = harness.container.read(sendDestinationHandoffProvider);
    expect(value?.value, 'lightning:invoice');
    expect(value.toString(), 'SendDestinationHandoffValue(redacted)');
    expect(value.toString(), isNot(contains('invoice')));
    expect(handoff.take(value!), 'lightning:invoice');
    expect(handoff.take(value), isNull);

    final invalid = handoff.stage(
      'x' * (SendDestinationHandoffValue.maximumCharacters + 1),
    );
    expect(
      invalid,
      isA<AppFailureResult<void>>().having(
        (result) => result.failure.code,
        'code',
        'send_destination_handoff_invalid',
      ),
    );
    for (final unsafe in <String>[
      'lnbcrt1invoice\u200bhidden',
      'lnbcrt1invoice\u202ereversed',
      'lnbcrt1invoic\u00e9',
    ]) {
      expect(
        handoff.stage(unsafe),
        isA<AppFailureResult<void>>().having(
          (result) => result.failure.code,
          'code',
          'send_destination_handoff_invalid',
        ),
      );
    }
  });

  test(
    'Send adopts a staged scan only after its selected target loads',
    () async {
      final harness = await PaymentFlowTestHarness.create();
      addTearDown(harness.dispose);
      final staged = harness.container
          .read(sendDestinationHandoffProvider.notifier)
          .stage('bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh');
      expect(staged, isA<AppSuccess<void>>());

      final state = await harness.container.read(
        sendFlowViewModelProvider(WalletPaymentTarget.bitcoinOnchain).future,
      );

      expect(state.destination, 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh');
      expect(harness.container.read(sendDestinationHandoffProvider), isNull);
    },
  );

  test('an already opening Send form leaves a later scan staged', () async {
    final harness = await PaymentFlowTestHarness.create();
    addTearDown(harness.dispose);
    final opening = harness.container.read(
      sendFlowViewModelProvider(WalletPaymentTarget.bitcoinOnchain).future,
    );
    final handoff = harness.container.read(
      sendDestinationHandoffProvider.notifier,
    );
    expect(handoff.stage('rgb:later-scan'), isA<AppSuccess<void>>());

    expect((await opening).destination, isEmpty);
    expect(
      harness.container.read(sendDestinationHandoffProvider)?.value,
      'rgb:later-scan',
    );
  });
}
