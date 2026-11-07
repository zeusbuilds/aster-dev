import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/transaction/presentation/models/models.dart';
import 'package:aster/features/transaction/presentation/screens/screens.dart';
import 'package:aster/features/transaction/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/features/wallet/presentation/models/models.dart';
import 'package:aster/features/wallet/presentation/view_model/view_models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/payment_flow_harness.dart';
import '../../support/wallet_fakes.dart';

const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
  usdtAsset: RgbAssetConfiguration(
    contractId: 'rgb:fixture',
    precision: 6,
    requiresEvmValidation: false,
  ),
);

void main() {
  testWidgets(
    'only exact recovery details exposes cancellation and Keep payment does nothing',
    (tester) async {
      final h = await _harness();
      addTearDown(() => _dispose(tester, h));
      await _pump(
        tester,
        h,
        const TransactionListScreen(assetKind: WalletAssetKind.usdt),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cancel payment'), findsNothing);
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expect(h.engine.calls, isNot(contains('revokeDispatchedRgbOperation')));

      await _details(tester, h);

      await tester.ensureVisible(find.text('Cancel payment'));
      await tester.tap(find.text('Cancel payment'));
      await tester.pumpAndSettle();

      final dialog = tester.widget<AsterConfirmationDialog>(
        find.byType(AsterConfirmationDialog),
      );
      expect(dialog.confirmVariant, ButtonVariant.primary);
      expect(find.text('Keep payment'), findsOneWidget);

      await tester.tap(find.text('Keep payment'));

      await tester.pumpAndSettle();

      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expect(h.engine.calls, isNot(contains('revokeDispatchedRgbOperation')));
      expect(h.toasts.messages, isEmpty);
    },
  );

  testWidgets(
    'unqualified archive keeps the extra action hidden without feedback',
    (tester) async {
      final h = await _harness(supported: false);
      addTearDown(() => _dispose(tester, h));
      final record =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      await _pump(
        tester,
        h,
        TransactionDetailsScreen(
          assetKind: WalletAssetKind.usdt,
          activityId: PaymentSubmissionDisplay(record).id,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check status'), findsOneWidget);
      expect(find.text('Cancel payment'), findsNothing);
      expect(h.toasts.messages, isEmpty);
    },
  );

  testWidgets(
    'double taps have one review and one cancellation with an owned result toast',
    (tester) async {
      final h = await _harness();
      addTearDown(() => _dispose(tester, h));
      final engine = h.engine as FakeRevocableWalletEngine;
      engine.revocationGate = Completer<void>();
      await _details(tester, h);
      final start = tester
          .widget<CustomButton>(
            find.widgetWithText(CustomButton, 'Cancel payment'),
          )
          .onTap!;
      start();
      start();
      await tester.pumpAndSettle();
      expect(find.byType(AsterConfirmationDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AsterConfirmationDialog),
          matching: find.widgetWithText(CustomButton, 'Cancel payment'),
        ),
      );
      await tester.pump();
      await _until(tester, () => engine.calls.contains('revocation:start'));
      expect(
        tester
            .widget<CustomButton>(
              find.widgetWithText(CustomButton, 'Check status'),
            )
            .loading,
        isTrue,
      );
      engine.revocationGate!.complete();
      await _until(tester, () => h.toasts.messages.isNotEmpty);
      expect(h.toasts.messages.single.title, 'Payment cancelled');
      expect(
        engine.calls.where((call) => call == 'revokeDispatchedRgbOperation'),
        hasLength(1),
      );
      expect(
        engine.calls.where((call) => call == 'commitPaymentOperation'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['route', 'lifecycle', 'wallet']) {
    testWidgets(
      'late cancellation after $change change has no stale feedback',
      (tester) async {
        final h = await _harness();
        addTearDown(() => _dispose(tester, h));
        final engine = h.engine as FakeRevocableWalletEngine;
        engine.revocationGate = Completer<void>();
        final navigator = GlobalKey<NavigatorState>();
        final wallet = await h.container.read(walletViewModelProvider.future);
        final changedWallet = _ChangingWallet(wallet);
        final container = change == 'wallet'
            ? ProviderContainer(
                parent: h.container,
                overrides: [
                  walletViewModelProvider.overrideWith(() => changedWallet),
                  activityViewModelProvider(WalletAssetKind.usdt)
                      .overrideWith(ActivityViewModel.new),
                ],
              )
            : h.container;
        var childDisposed = false;
        if (change == 'wallet') {
          addTearDown(() async {
            if (childDisposed) return;
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            container.dispose();
            await tester.pump();
          });
        }
        await _details(tester, h, navigator: navigator, container: container);
        await tester.ensureVisible(find.text('Cancel payment'));
        await tester.tap(find.text('Cancel payment'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AsterConfirmationDialog),
            matching: find.widgetWithText(CustomButton, 'Cancel payment'),
          ),
        );
        await _until(tester, () => engine.calls.contains('revocation:start'));
        switch (change) {
          case 'route':
            navigator.currentState!.pushNamed('/other');
          case 'lifecycle':
            await h.container
                .read(walletLifecycleViewModelProvider.notifier)
                .handle(AppLifecycleState.inactive);
          case 'wallet':
            changedWallet.clearSelection();
        }
        await tester.pump();
        engine.revocationGate!.complete();
        await _until(
          tester,
          () => engine.calls.contains('revokeDispatchedRgbOperation'),
        );
        await tester.pumpAndSettle();
        expect(h.toasts.messages, isEmpty);
        expect(
          engine.calls.where((call) => call == 'revokeDispatchedRgbOperation'),
          hasLength(1),
        );
        expect(
          engine.calls.where((call) => call == 'commitPaymentOperation'),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        if (change == 'wallet') {
          container.dispose();
          childDisposed = true;
        }
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}

Future<PaymentFlowTestHarness> _harness({bool supported = true}) async {
  final now = DateTime.now().toUtc();
  final engine = FakeRevocableWalletEngine()
    ..dispatchedRgbRevocationSupported = supported
    ..sentPayment = null
    ..sendPaymentError = StateError('Lost original response')
    ..revocationResult = const WalletPaymentRecoveryStatus(
      phase: WalletPaymentRecoveryPhase.rejected,
      endAuthorized: false,
      failureCode: 'cancelled',
    )
    ..feeEstimate = WalletFeeRateEstimate(
      targetBlocks: 6,
      satsPerVbyte: 2,
      observedAt: now,
    );
  final h = await PaymentFlowTestHarness.create(
    engine: engine,
    services: _services,
    clock: () => now,
  );
  final result = await h.repository.sendPayment(
    target: WalletPaymentTarget.usdtOnchain,
    destination: 'rgb:approved-witness',
    amountUnits: 50,
    reviewedFeeRate: engine.feeEstimate,
    rgbRecipientType: RgbRecipientType.witness,
    witnessBitcoinAmountSats: rgbWitnessRecipientSats,
  );
  expect(result, isA<AppFailureResult<WalletSendResult>>());
  return h;
}

Future<void> _details(
  WidgetTester tester,
  PaymentFlowTestHarness h, {
  GlobalKey<NavigatorState>? navigator,
  ProviderContainer? container,
}) async {
  final record =
      (await h.repository.paymentSubmissionStatus()
              as AppSuccess<WalletPaymentSubmission?>)
          .value!;
  await _pump(
    tester,
    h,
    TransactionDetailsScreen(
      assetKind: WalletAssetKind.usdt,
      activityId: PaymentSubmissionDisplay(record).id,
    ),
    navigator: navigator,
    container: container,
  );
  await _until(
    tester,
    () => find.text('Cancel payment').evaluate().length == 1,
  );
}

Future<void> _pump(
  WidgetTester tester,
  PaymentFlowTestHarness h,
  Widget child, {
  GlobalKey<NavigatorState>? navigator,
  ProviderContainer? container,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container ?? h.container,
      child: MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.light(),
        builder: (context, child) => AsterFeedbackScope(
          haptics: h.haptics,
          toasts: h.toasts,
          child: child!,
        ),
        routes: {
          '/other': (context) => const Scaffold(body: Text('Other route')),
        },
        home: child,
      ),
    ),
  );
}

Future<void> _dispose(WidgetTester tester, PaymentFlowTestHarness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final disposal = h.dispose();
  await tester.pump();
  await disposal;
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var n = 0; n < 200; n += 1) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Cancellation UI did not reach its expected state.');
}

class _ChangingWallet extends WalletViewModel {
  _ChangingWallet(this.initial);
  final WalletState initial;
  @override
  Future<WalletState> build() async => initial;
  void clearSelection() =>
      state = AsyncData(initial.copyWith(activeWallet: null));
}
