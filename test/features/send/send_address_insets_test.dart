import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/send/presentation/screens/screens.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'recipient form fills bottom viewport through loading and keyboard',
    (tester) async {
      _setPhone(tester);
      final gate = Completer<void>();
      final engine = FakeWalletEngine()..balanceGate = gate;
      final h = await PaymentFlowTestHarness.create(engine: engine);
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        final disposal = h.dispose();
        for (var frame = 0; frame < 3; frame += 1) {
          await tester.pump();
        }
        await disposal;
      });
      await _mount(tester, h);
      await _until(tester, () => engine.calls.contains('balance'));
      expect(find.bySemanticsLabel('Loading recipient form'), findsOneWidget);
      _expectViewport(tester, bottom: 844, bottomPadding: 34 + 16);

      gate.complete();
      await _until(
        tester,
        () => h.container
            .read(sendFlowViewModelProvider(WalletPaymentTarget.bitcoinOnchain))
            .hasValue,
      );
      await tester.pump();
      _expectViewport(tester, bottom: 844, bottomPadding: 34 + 16);
      final continueButton = find.widgetWithText(CustomButton, 'Continue');
      expect(tester.getRect(continueButton).bottom, lessThanOrEqualTo(810));

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      tester.view.padding = const FakeViewPadding();
      await tester.pump();
      _expectViewport(tester, bottom: 524, bottomPadding: 16);
      await tester.ensureVisible(continueButton);
      await tester.pump();
      expect(tester.getRect(continueButton).bottom, lessThanOrEqualTo(524));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recipient failure remains scrollable on a compact scaled phone',
    (tester) async {
      _setPhone(tester, size: const Size(320, 568));
      const failure = AppFailure(
        code: 'fixture_balance_unavailable',
        kind: AppFailureKind.unavailable,
        userMessage: 'Balance is temporarily unavailable. Please try again.',
        retryable: true,
      );
      final h = await PaymentFlowTestHarness.create(
        engine: FakeWalletEngine()
          ..balanceError = const AppFailureException(failure),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        final disposal = h.dispose();
        for (var frame = 0; frame < 3; frame += 1) {
          await tester.pump();
        }
        await disposal;
      });
      await _mount(tester, h, scale: 2);
      await _until(
        tester,
        () => find.text(failure.userMessage).evaluate().isNotEmpty,
      );
      expect(tester.getRect(find.byType(CustomScrollView)).bottom, 568);
      expect(find.widgetWithText(CustomButton, 'Retry'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

void _setPhone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
}

Future<void> _mount(
  WidgetTester tester,
  PaymentFlowTestHarness h, {
  double scale = 1,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: h.container,
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: AsterFeedbackScope(
          haptics: h.haptics,
          toasts: ToastController(),
          child: child!,
        ),
      ),
      home: const SendAddressScreen(target: WalletPaymentTarget.bitcoinOnchain),
    ),
  ),
);

void _expectViewport(
  WidgetTester tester, {
  required double bottom,
  required double bottomPadding,
}) {
  expect(tester.getRect(find.byType(CustomScrollView)).bottom, bottom);
  final body = tester.widget<AsterFormBody>(find.byType(AsterFormBody));
  expect(body.bottomPadding, bottomPadding);
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 120; frame += 1) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Recipient state did not settle.');
}
