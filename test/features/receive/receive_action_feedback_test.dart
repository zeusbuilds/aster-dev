import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/screens/screens.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

const _generationFailure = AppFailure(
  code: 'request_generation_unavailable',
  kind: AppFailureKind.connectivity,
  userMessage: 'Could not connect. Try again.',
  retryable: true,
);

void main() {
  Future<PaymentFlowTestHarness> mount(
    WidgetTester tester, {
    WalletPaymentTarget target = WalletPaymentTarget.bitcoinOnchain,
  }) async {
    final harness = await PaymentFlowTestHarness.create(
      engine: FakeWalletEngine(),
      services: testRgbServices,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final disposal = harness.dispose();
      for (var frame = 0; frame < 3; frame += 1) {
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
            child: ReceiveRequestScreen(target: target),
          ),
        ),
      ),
    );
    final provider = receiveFlowViewModelProvider(target);
    for (
      var frame = 0;
      frame < 40 && !harness.container.read(provider).hasValue;
      frame += 1
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(harness.container.read(provider).hasValue, isTrue);
    await tester.pumpAndSettle();
    return harness;
  }

  for (final target in [
    WalletPaymentTarget.bitcoinOnchain,
    WalletPaymentTarget.usdtOnchain,
  ]) {
    testWidgets(
      '${target.name} regeneration keeps the previous QR without progress copy or duplicate work',
      (tester) async {
        final harness = await mount(tester, target: target);
        final provider = receiveFlowViewModelProvider(target);
        final initial = harness.container.read(provider).requireValue.request!;
        final initialQr = tester.widget<ReceiveRequestQr>(
          find.byType(ReceiveRequestQr),
        );
        final gate = Completer<void>();
        harness.engine.createReceiveGate = gate;
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final replacement = WalletReceiveRequest(
          route: initial.route,
          encodedRequest: 'replacement-${target.slug}',
          displayValue: 'replacement-${target.slug}',
        );
        harness.engine.createdReceiveRequest = replacement;
        final callsBefore = harness.engine.calls
            .where((call) => call == 'createReceiveRequest:start')
            .length;
        await tester.ensureVisible(find.text('Generate new request'));
        final regenerate = tester
            .widget<AsterOptionRow>(
              find.widgetWithText(AsterOptionRow, 'Generate new request'),
            )
            .onTap!;
        regenerate();
        // A callback from the same frame must not start a second request.
        regenerate();
        for (var frame = 0; frame < 20; frame += 1) {
          await tester.pump(const Duration(milliseconds: 16));
          if (harness.engine.calls
                  .where((call) => call == 'createReceiveRequest:start')
                  .length >
              callsBefore) {
            break;
          }
        }
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          harness.container.read(provider).requireValue.isGenerating,
          isTrue,
        );
        expect(harness.container.read(provider).requireValue.request, initial);
        expect(
          tester
              .widget<ReceiveRequestQr>(find.byType(ReceiveRequestQr))
              .encodedRequest,
          initialQr.encodedRequest,
        );
        expect(find.text('Generating'), findsNothing);
        for (final title in ['Set amount', 'Generate new request', 'Share']) {
          expect(
            tester
                .widget<AsterOptionRow>(
                  find.widgetWithText(AsterOptionRow, title),
                )
                .onTap,
            isNull,
          );
        }
        expect(
          harness.engine.calls
              .where((call) => call == 'createReceiveRequest:start')
              .length,
          callsBefore + 1,
        );
        expect(harness.toasts.messages, isEmpty);
        gate.complete();
        await tester.pumpAndSettle();
        expect(
          harness.container.read(provider).requireValue.request,
          replacement,
        );
        expect(find.text('Generating'), findsNothing);
        expect(harness.toasts.messages, isEmpty);
        expect(
          tester
              .widget<AsterOptionRow>(
                find.widgetWithText(AsterOptionRow, 'Generate new request'),
              )
              .onTap,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'regeneration failure retains valid QR and reports once only in action toast',
    (tester) async {
      final harness = await mount(tester);
      final provider = receiveFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final initial = harness.container.read(provider).requireValue.request!;
      harness.engine.createReceiveError = const AppFailureException(
        _generationFailure,
      );
      await tester.ensureVisible(find.text('Generate new request'));
      await tester.tap(find.text('Generate new request'));
      await tester.pumpAndSettle();
      expect(harness.container.read(provider).requireValue.request, initial);
      expect(find.text(initial.displayValue), findsOneWidget);
      expect(find.text(_generationFailure.userMessage), findsNothing);
      expect(harness.toasts.messages, hasLength(1));
      expect(
        harness.toasts.messages.single.title,
        'Could not regenerate request',
      );
      expect(
        harness.toasts.messages.single.message,
        _generationFailure.userMessage,
      );
    },
  );

  testWidgets(
    'new request succeeds quietly without an unsolicited success toast',
    (tester) async {
      final harness = await mount(tester);
      await tester.ensureVisible(find.text('Generate new request'));
      await tester.tap(find.text('Generate new request'));
      await tester.pumpAndSettle();
      expect(harness.toasts.messages, isEmpty);
      expect(find.text('New payment request ready'), findsNothing);
    },
  );

  testWidgets(
    'amount validation is one warning after Set amount with no inline message or generation',
    (tester) async {
      final harness = await mount(tester);
      final provider = receiveFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      await tester.ensureVisible(find.text('Set amount'));
      await tester.tap(find.text('Set amount'));
      await tester.pumpAndSettle();
      harness.container.read(provider.notifier).updateAmount('0');
      await tester.pumpAndSettle();
      final calls = List<String>.of(harness.engine.calls);
      expect(find.text('Amount must be greater than zero.'), findsNothing);
      await tester.tap(find.widgetWithText(CustomButton, 'Set amount'));
      await tester.pumpAndSettle();
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.variant, ToastVariant.warning);
      expect(
        harness.toasts.messages.single.message,
        'Amount must be greater than zero.',
      );
      expect(find.text('Amount must be greater than zero.'), findsNothing);
      expect(harness.engine.calls, calls);
    },
  );

  testWidgets(
    'amount generation failure stays in sheet and reports once without a second underlying paragraph',
    (tester) async {
      final harness = await mount(tester);
      final provider = receiveFlowViewModelProvider(
        WalletPaymentTarget.bitcoinOnchain,
      );
      final initial = harness.container.read(provider).requireValue.request!;
      await tester.ensureVisible(find.text('Set amount'));
      await tester.tap(find.text('Set amount'));
      await tester.pumpAndSettle();
      harness.container.read(provider.notifier).updateAmount('0.0001');
      harness.engine.createReceiveError = const AppFailureException(
        _generationFailure,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CustomButton, 'Set amount'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiveAmountSheet), findsOneWidget);
      expect(harness.container.read(provider).requireValue.request, initial);
      expect(find.text(_generationFailure.userMessage), findsNothing);
      expect(harness.toasts.messages, hasLength(1));
      expect(harness.toasts.messages.single.title, 'Amount not applied');
      expect(
        harness.toasts.messages.single.message,
        _generationFailure.userMessage,
      );
    },
  );
}
