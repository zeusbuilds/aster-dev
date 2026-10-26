import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/full_wallet_qa.dart';
import '../../integration_test/support/full_wallet_rgb_setup.dart';

void main() {
  test('legacy bridge full campaign fails closed before funding', () {
    expect(
      () => requireQaSupportedFundingStage('full'),
      throwsA(
        isA<FullWalletQaFailure>().having(
          (value) => value.code,
          'code',
          'qa_bridge_mint_requires_external_blind_receiver',
        ),
      ),
    );
    for (final stage in [
      'lifecycle',
      'restore',
      'reconcile-mint',
      'reconcile-transfer',
    ]) {
      expect(() => requireQaSupportedFundingStage(stage), returnsNormally);
    }
  });

  testWidgets(
    'a delayed witness request is awaited without tapping any action',
    (tester) async {
      var ready = false;
      var actions = 0;
      final timer = Timer(
        const Duration(milliseconds: 350),
        () => ready = true,
      );
      addTearDown(timer.cancel);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextButton(
              onPressed: () => actions += 1,
              child: const Text('Generate new request'),
            ),
          ),
        ),
      );
      await qualifyWitnessReceiveUi(
        tester,
        isRequestReady: () => ready,
        timeout: const Duration(seconds: 2),
      );
      expect(ready, isTrue);
      expect(actions, 0);
    },
  );

  testWidgets('a ready witness request does not issue a new reservation', (
    tester,
  ) async {
    var observations = 0;
    await qualifyWitnessReceiveUi(
      tester,
      isRequestReady: () {
        observations += 1;
        return true;
      },
    );
    expect(observations, 1);
  });

  testWidgets('a request timeout fails without retrying generation', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextButton(
            onPressed: () => actions += 1,
            child: const Text('Generate new request'),
          ),
        ),
      ),
    );
    FullWalletQaFailure? failure;
    try {
      await qualifyWitnessReceiveUi(
        tester,
        isRequestReady: () => false,
        timeout: const Duration(milliseconds: 300),
      );
    } on FullWalletQaFailure catch (error) {
      failure = error;
    }
    expect(failure?.code, 'qa_witness_request_timeout');
    expect(actions, 0);
  });

  testWidgets('a generation failure stops the wait immediately', (
    tester,
  ) async {
    await expectLater(
      qualifyWitnessReceiveUi(
        tester,
        isRequestReady: () =>
            throw const FullWalletQaFailure('qa_fixture_generation_failed'),
      ),
      throwsA(
        isA<FullWalletQaFailure>().having(
          (value) => value.code,
          'code',
          'qa_fixture_generation_failed',
        ),
      ),
    );
  });
}
