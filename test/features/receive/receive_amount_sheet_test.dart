import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/screens/screens.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/receive/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

enum _Dismissal { outside, drag, close }

void main() {
  Future<PaymentFlowTestHarness> mount(
    WidgetTester tester, {
    WalletPaymentTarget target = WalletPaymentTarget.bitcoinOnchain,
    bool duoCover = false,
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
    tester.view.physicalSize = duoCover
        ? const Size(466, 678)
        : const Size(390, 1000);
    if (duoCover) {
      const channel = EventChannel('com.aster.wallet/cover_navigation');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (_, events) =>
              events.success({'width': 466.0, 'height': 678.0}),
        ),
      );
      const padding = FakeViewPadding(right: 84, bottom: 34);
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(() => messenger.setMockStreamHandler(channel, null));
    }
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: harness.container,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => AsterFeedbackScope(
            haptics: harness.haptics,
            toasts: harness.toasts,
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ReceiveRequestScreen(target: target),
                  ),
                ),
                child: const Text('Open receive'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open receive'));
    final provider = receiveFlowViewModelProvider(target);
    for (var frame = 0; frame < 40; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      if (harness.container.read(provider).hasValue) break;
    }
    expect(harness.container.read(provider).hasValue, isTrue);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Set amount'));
    await tester.tap(find.text('Set amount'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiveAmountSheet), findsOneWidget);
    return harness;
  }

  Future<void> dismiss(WidgetTester tester, _Dismissal dismissal) async {
    switch (dismissal) {
      case _Dismissal.outside:
        await tester.tapAt(const Offset(20, 40));
      case _Dismissal.drag:
        final header = find.descendant(
          of: find.byType(ReceiveAmountSheet),
          matching: find.byType(AsterSheetHeader),
        );
        await tester.drag(header, const Offset(0, 650));
      case _Dismissal.close:
        await tester.tap(find.byTooltip('Close amount editor'));
    }
    await tester.pumpAndSettle();
    expect(find.byType(ReceiveAmountSheet), findsNothing);
    expect(find.byType(ReceiveRequestScreen), findsOneWidget);
  }

  for (final target in [
    WalletPaymentTarget.bitcoinOnchain,
    WalletPaymentTarget.usdtOnchain,
  ]) {
    for (final dismissal in _Dismissal.values) {
      testWidgets('${target.name} amount editor dismisses by $dismissal', (
        tester,
      ) async {
        final harness = await mount(tester, target: target);
        final provider = receiveFlowViewModelProvider(target);
        final initial = harness.container.read(provider).requireValue.request;
        final callsBefore = harness.engine.calls.length;
        harness.container.read(provider.notifier).updateAmount('1');
        await tester.pump();
        await dismiss(tester, dismissal);
        expect(harness.container.read(provider).requireValue.request, initial);
        expect(harness.engine.calls.length, callsBefore);
        expect(harness.toasts.messages, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final dismissal in _Dismissal.values) {
    for (final succeeds in [true, false]) {
      testWidgets(
        'in-flight amount editor dismisses by $dismissal; late ${succeeds ? 'success' : 'failure'} cannot pop Receive',
        (tester) async {
          final harness = await mount(tester);
          final provider = receiveFlowViewModelProvider(
            WalletPaymentTarget.bitcoinOnchain,
          );
          final gate = Completer<void>();
          harness.engine.createReceiveGate = gate;
          if (!succeeds) {
            harness.engine.createReceiveError = const AppFailureException(
              AppFailure(
                code: 'request_unavailable',
                kind: AppFailureKind.connectivity,
                userMessage: 'Could not create request.',
                retryable: true,
              ),
            );
          }
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          final callsBefore = harness.engine.calls
              .where((call) => call == 'createReceiveRequest:start')
              .length;
          harness.container.read(provider.notifier).updateAmount('0.0001');
          await tester.pump();
          await tester.tap(find.widgetWithText(CustomButton, 'Set amount'));
          for (var frame = 0; frame < 20; frame += 1) {
            await tester.pump(const Duration(milliseconds: 16));
            if (harness.engine.calls
                    .where((call) => call == 'createReceiveRequest:start')
                    .length >
                callsBefore) {
              break;
            }
          }
          expect(
            harness.container.read(provider).requireValue.isGenerating,
            isTrue,
          );
          await dismiss(tester, dismissal);
          gate.complete();
          await tester.pumpAndSettle();
          expect(find.byType(ReceiveRequestScreen), findsOneWidget);
          expect(find.text('Open receive'), findsNothing);
          expect(
            harness.container.read(provider).requireValue.isGenerating,
            isFalse,
          );
          expect(
            harness.engine.calls
                .where((call) => call == 'createReceiveRequest:start')
                .length,
            callsBefore + 1,
          );
          expect(harness.toasts.messages, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('completion during the dismissal animation cannot pop Receive', (
    tester,
  ) async {
    final harness = await mount(tester);
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    final gate = Completer<void>();
    harness.engine.createReceiveGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    harness.container.read(provider.notifier).updateAmount('0.0001');
    await tester.pump();
    await tester.tap(find.widgetWithText(CustomButton, 'Set amount'));
    for (var frame = 0; frame < 20; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      if (harness.engine.calls.last == 'createReceiveRequest:start') break;
    }
    expect(harness.container.read(provider).requireValue.isGenerating, isTrue);
    await tester.tapAt(const Offset(20, 40));
    // The sheet is still mounted until its reverse animation completes.
    expect(find.byType(ReceiveAmountSheet), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ReceiveAmountSheet), findsNothing);
    expect(find.byType(ReceiveRequestScreen), findsOneWidget);
    expect(find.text('Open receive'), findsNothing);
    expect(harness.toasts.messages, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry failure during dismissal has no orphaned feedback', (
    tester,
  ) async {
    final harness = await mount(tester);
    final provider = receiveFlowViewModelProvider(
      WalletPaymentTarget.bitcoinOnchain,
    );
    harness.engine.createReceiveError = const AppFailureException(
      AppFailure(
        code: 'request_unavailable',
        kind: AppFailureKind.connectivity,
        userMessage: 'Could not create request.',
        retryable: true,
      ),
    );
    harness.container.invalidate(provider);
    await tester.pumpAndSettle();
    expect(find.text('Amount editor unavailable'), findsOneWidget);
    final gate = Completer<void>();
    harness.engine.createReceiveGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final callsBefore = harness.engine.calls
        .where((call) => call == 'createReceiveRequest:start')
        .length;
    await tester.tap(
      find.descendant(
        of: find.byType(ReceiveAmountSheet),
        matching: find.widgetWithText(CustomButton, 'Retry'),
      ),
    );
    for (var frame = 0; frame < 20; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      if (harness.engine.calls
              .where((call) => call == 'createReceiveRequest:start')
              .length >
          callsBefore) {
        break;
      }
    }
    expect(harness.container.read(provider).isLoading, isTrue);
    await tester.tapAt(const Offset(20, 40));
    expect(find.byType(ReceiveAmountSheet), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ReceiveAmountSheet), findsNothing);
    expect(find.byType(ReceiveRequestScreen), findsOneWidget);
    expect(harness.toasts.messages, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('amount card is compact and uses the shared selector title', (
    tester,
  ) async {
    await mount(tester);
    final sheet = find.byType(ReceiveAmountSheet);
    final header = find.descendant(
      of: sheet,
      matching: find.byType(AsterSheetHeader),
    );
    final title = find.descendant(
      of: header,
      matching: find.text('Set amount'),
    );
    final titleStyle = tester.widget<Text>(title).style!;
    expect(titleStyle.fontSize, 18);
    expect(titleStyle.fontWeight, FontWeight.w600);
    final card = find
        .ancestor(
          of: find.byType(WalletAmountEntry),
          matching: find.byType(Squircle),
        )
        .first;
    expect(tester.getTopLeft(card).dy - tester.getBottomLeft(header).dy, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Duo cover amount editor fits at rest and scrolls above the keyboard',
    (tester) async {
      final harness = await mount(tester, duoCover: true);
      harness.container
          .read(
            receiveFlowViewModelProvider(WalletPaymentTarget.bitcoinOnchain)
                .notifier,
          )
          .updateAmount('0.0001');
      await tester.pumpAndSettle();
      final sheet = find.byType(ReceiveAmountSheet);
      final viewport = find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.vertical,
        ),
      );
      final submit = find.descendant(
        of: sheet,
        matching: find.widgetWithText(CustomButton, 'Set amount'),
      );
      final scrollable = Scrollable.of(tester.element(submit));

      expect(scrollable.position.maxScrollExtent, 0);
      expect(tester.getSize(sheet).height, lessThan(678 * 0.85));
      expect(tester.getRect(viewport).bottom, closeTo(678, 0.5));
      expect(tester.getRect(submit).bottom, closeTo(628, 0.5));
      expect(submit.hitTestable(), findsOneWidget);

      // The modal rises above the keyboard once. The home indicator no longer
      // overlaps the visible scroll area, so just the design gap remains.
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      tester.view.padding = const FakeViewPadding(right: 84);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(viewport).bottom, closeTo(498, 0.5));
      expect(tester.getRect(submit).bottom, closeTo(482, 0.5));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
