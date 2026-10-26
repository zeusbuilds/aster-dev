import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/screens/receive_request_screen.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

const _failure = AppFailure(
  code: 'request_generation_unavailable',
  kind: AppFailureKind.connectivity,
  userMessage: 'Could not connect. Try again.',
  retryable: true,
);

void main() {
  Future<PaymentFlowTestHarness> mount(
    WidgetTester tester, {
    AppFailure? failure,
  }) async {
    final engine = FakeWalletEngine();
    if (failure != null) {
      engine.createReceiveError = AppFailureException(failure);
    }
    final harness = await PaymentFlowTestHarness.create(
      engine: engine,
      services: testRgbServices,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final disposal = harness.dispose();
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
      }
      await disposal;
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AsterFeedbackScope(
            haptics: harness.haptics,
            toasts: harness.toasts,
            child: const ReceiveRequestScreen(
              target: WalletPaymentTarget.usdtOnchain,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  void expectNoReceivePreparation() {
    for (final label in [
      'Witness receive',
      'Blind receive',
      'Use blind receive',
      'Use witness receive',
      'Prepare wallet',
      'Check preparation',
      'Try receive again',
      'Preparation needed',
      'Preparation pending',
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }
  }

  testWidgets(
    'USDT opens one request with no receive method or paid setup controls',
    (tester) async {
      final harness = await mount(tester);
      expect(find.text('Receive USDT'), findsOneWidget);
      expect(find.byType(ReceiveRequestQr), findsOneWidget);
      expect(find.text('Set amount'), findsOneWidget);
      expectNoReceivePreparation();
      expect(harness.toasts.messages, isEmpty);
      expect(
        harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
        hasLength(1),
      );

      await tester.ensureVisible(find.text('Generate new request'));
      await tester.tap(find.text('Generate new request'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveRequestQr), findsOneWidget);
      expectNoReceivePreparation();
      expect(
        harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'retryable failure offers only request Retry with one failure toast per action',
    (tester) async {
      final harness = await mount(tester, failure: _failure);
      expect(find.text('Request unavailable'), findsOneWidget);
      expect(find.text(_failure.userMessage), findsNothing);
      expectNoReceivePreparation();
      expect(harness.toasts.messages, isEmpty);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.message, _failure.userMessage);
      expect(
        harness.engine.calls.where((c) => c == 'createReceiveRequest:start'),
        hasLength(2),
      );
      expectNoReceivePreparation();

      harness.engine.createReceiveError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveRequestQr), findsOneWidget);
      expect(harness.toasts.messages, hasLength(1));
    },
  );

  for (final failure in [
    rgbWalletSetupRequiredFailure,
    rgbWalletSetupPendingFailure,
  ]) {
    testWidgets(
      'legacy ${failure.code} never offers a new preparation from Receive',
      (tester) async {
        await mount(tester, failure: failure);
        expect(find.text('Request unavailable'), findsOneWidget);
        expect(find.byType(ReceiveRequestQr), findsNothing);
        expect(find.text(failure.userMessage), findsNothing);
        expectNoReceivePreparation();
      },
    );
  }
}
