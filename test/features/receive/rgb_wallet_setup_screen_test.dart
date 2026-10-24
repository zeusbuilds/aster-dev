import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/models/models.dart';
import 'package:aster/features/receive/presentation/screens/receive_request_screen.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/presentation_fakes.dart';

final class _SetupViewModel extends ReceiveFlowViewModel {
  final toasts = RecordingToastPresentationService();
  AppFailure initialFailure = rgbWalletSetupRequiredFailure;
  AppFailure? prepareFailure;
  AppFailure? checkFailure;
  AppFailure? confirmationFailure;
  RgbReceiveMode receiveMode = RgbReceiveMode.blind;
  int modeChanges = 0;
  @override
  RgbReceiveMode get rgbReceiveMode => receiveMode;
  @override
  Future<void> setRgbReceiveMode(RgbReceiveMode mode) async {
    receiveMode = mode;
    modeChanges++;
    state = AsyncError(
      const AppFailureException(rgbWalletSetupRequiredFailure),
      StackTrace.current,
    );
  }

  int preparations = 0;
  int cancellations = 0;
  int confirmations = 0;
  int checks = 0;
  Completer<void>? confirmationGate;
  var review = RgbWalletSetupReview(
    id: '1' * 32,
    walletId: '2' * 32,
    network: BlockchainEnvironment.regtest,
    runtimeFingerprint: '3' * 64,
    nodePublicKey: '02${'4' * 64}',
    feeRateSatPerVbyte: 20,
    expiresAt: DateTime.utc(2026, 10, 15, 0, 2),
  );

  @override
  Future<ReceiveFlowState> build(WalletPaymentTarget target) async {
    throw AppFailureException(initialFailure);
  }

  @override
  Future<AppResult<RgbWalletSetupReview>> prepareRgbSetup() async {
    preparations++;
    if (prepareFailure case final failure?) {
      state = AsyncError(AppFailureException(failure), StackTrace.current);
      return AppResult.failure(failure);
    }
    return AppResult.success(review);
  }

  @override
  Future<void> cancelRgbSetup(RgbWalletSetupReview review) async {
    cancellations++;
  }

  @override
  Future<void> confirmRgbSetup(RgbWalletSetupReview review) async {
    confirmations++;
    await confirmationGate?.future;
    state = AsyncError(
      AppFailureException(confirmationFailure ?? rgbWalletSetupPendingFailure),
      StackTrace.current,
    );
  }

  @override
  Future<void> checkRgbSetup() async {
    checks++;
    if (checkFailure case final failure?) {
      state = AsyncError(AppFailureException(failure), StackTrace.current);
    }
  }
}

Future<void> _mount(WidgetTester tester, _SetupViewModel vm) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        receiveFlowViewModelProvider(WalletPaymentTarget.usdtOnchain)
            .overrideWith(() => vm),
        utcClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 15)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: AsterFeedbackScope(
          haptics: const NoopHapticFeedbackService(),
          toasts: vm.toasts,
          child: const ReceiveRequestScreen(
            target: WalletPaymentTarget.usdtOnchain,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'setup states show compact titles without operational paragraphs',
    (tester) async {
      for (final (failure, title, action) in [
        (rgbWalletSetupRequiredFailure, 'Preparation needed', 'Prepare wallet'),
        (
          rgbWalletSetupPendingFailure,
          'Preparation pending',
          'Check preparation',
        ),
      ]) {
        final vm = _SetupViewModel()..initialFailure = failure;
        await _mount(tester, vm);
        expect(find.text(title), findsOneWidget);
        expect(find.text(action), findsOneWidget);
        expect(find.text(failure.userMessage), findsNothing);
        expect(vm.toasts.messages, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'failed Prepare review gives one action toast and a compact unavailable state',
    (tester) async {
      const failure = AppFailure(
        code: 'review_network_unavailable',
        kind: AppFailureKind.connectivity,
        userMessage: 'Could not connect. Try again.',
        retryable: true,
      );
      final vm = _SetupViewModel()..prepareFailure = failure;
      await _mount(tester, vm);
      await tester.tap(find.text('Prepare wallet'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(vm.preparations, 1);
      expect(vm.confirmations, 0);
      expect(vm.toasts.messages, hasLength(1));
      expect(vm.toasts.messages.single.title, 'Could not prepare wallet');
      expect(vm.toasts.messages.single.message, failure.userMessage);
      expect(find.text('Preparation needed'), findsOneWidget);
      expect(find.text(failure.userMessage), findsNothing);
      expect(find.text('Prepare RGB wallet?'), findsNothing);
    },
  );

  testWidgets(
    'failed explicit Check gives one toast and no retained paragraph',
    (tester) async {
      const failure = AppFailure(
        code: 'setup_status_unavailable',
        kind: AppFailureKind.connectivity,
        userMessage: 'Could not check preparation. Try again.',
        retryable: true,
      );
      final vm = _SetupViewModel()
        ..initialFailure = rgbWalletSetupPendingFailure
        ..checkFailure = failure;
      await _mount(tester, vm);
      await tester.tap(find.text('Check preparation'));
      await tester.pumpAndSettle();
      expect(vm.checks, 1);
      expect(vm.confirmations, 0);
      expect(vm.toasts.messages, hasLength(1));
      expect(vm.toasts.messages.single.message, failure.userMessage);
      expect(find.text(failure.userMessage), findsNothing);
    },
  );

  testWidgets(
    'changed review inspects exact setup phase before offering fresh Prepare',
    (tester) async {
      const staleReview = AppFailure(
        code: 'rgb_wallet_setup_review_changed',
        kind: AppFailureKind.conflict,
        userMessage: 'The review expired. Prepare again before confirming.',
        retryable: false,
      );
      final vm = _SetupViewModel()
        ..confirmationFailure = staleReview
        ..checkFailure = rgbWalletSetupRequiredFailure;
      await _mount(tester, vm);
      await tester.tap(find.text('Prepare wallet'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Confirm setup'));
      await tester.pumpAndSettle();
      expect(vm.preparations, 1);
      expect(vm.confirmations, 1);
      expect(vm.checks, 1);
      expect(find.text('Preparation needed'), findsOneWidget);
      expect(find.text('Prepare wallet'), findsOneWidget);
      expect(find.text('Check preparation'), findsNothing);
      expect(find.text(staleReview.userMessage), findsNothing);
      expect(vm.toasts.messages, hasLength(1));
      expect(vm.toasts.messages.single.title, 'Review changed');
      await tester.tap(find.text('Prepare wallet'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(vm.preparations, 2);
      expect(vm.confirmations, 1);
      expect(find.text('Prepare RGB wallet?'), findsOneWidget);
    },
  );

  testWidgets(
    'changed review with unresolved native preparation retains Check and never repeats Prepare',
    (tester) async {
      const staleReview = AppFailure(
        code: 'rgb_wallet_setup_review_changed',
        kind: AppFailureKind.conflict,
        userMessage: 'The wallet or review changed.',
        retryable: false,
      );
      final vm = _SetupViewModel()
        ..confirmationFailure = staleReview
        ..checkFailure = rgbWalletSetupPendingFailure;
      await _mount(tester, vm);
      await tester.tap(find.text('Prepare wallet'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Confirm setup'));
      await tester.pumpAndSettle();
      expect(vm.checks, 1);
      expect(vm.preparations, 1);
      expect(vm.confirmations, 1);
      expect(find.text('Preparation pending'), findsOneWidget);
      expect(find.text('Check preparation'), findsOneWidget);
      expect(find.text('Prepare wallet'), findsNothing);
      expect(vm.toasts.messages, hasLength(1));
      expect(vm.toasts.messages.single.title, 'Preparation pending');
    },
  );

  testWidgets(
    'blind receipt requires an explicit choice and Cancel preserves witness mode',
    (tester) async {
      final vm = _SetupViewModel()..receiveMode = RgbReceiveMode.witness;
      await _mount(tester, vm);
      expect(find.text('Witness receive'), findsOneWidget);
      await tester.tap(find.text('Use blind receive'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.textContaining('costs a Bitcoin network fee'),
        findsOneWidget,
      );
      expect(vm.modeChanges, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(vm.rgbReceiveMode, RgbReceiveMode.witness);
      expect(vm.modeChanges, 0);
      expect(vm.preparations, 0);
      expect(vm.confirmations, 0);
      await tester.tap(find.text('Use blind receive'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(
        find.widgetWithText(TextButton, 'Use blind receive').last,
      );
      await tester.pumpAndSettle();
      expect(vm.rgbReceiveMode, RgbReceiveMode.blind);
      expect(vm.modeChanges, 1);
      expect(vm.preparations, 0);
      expect(vm.confirmations, 0);
    },
  );

  testWidgets(
    'regtest consent names the local policy instead of a network quote',
    (tester) async {
      final vm = _SetupViewModel();
      vm.review = RgbWalletSetupReview(
        id: vm.review.id,
        walletId: vm.review.walletId,
        network: vm.review.network,
        runtimeFingerprint: vm.review.runtimeFingerprint,
        nodePublicKey: vm.review.nodePublicKey,
        feeRateSatPerVbyte: 1,
        expiresAt: vm.review.expiresAt,
        feeSource: WalletFeeRateSource.localRegtestPolicy,
      );
      await _mount(tester, vm);
      await tester.tap(find.text('Prepare wallet'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Local test fee rate'), findsOneWidget);
      expect(find.textContaining('Network fee rate'), findsNothing);
      expect(find.textContaining('1 sat/vB'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(vm.confirmations, 0);
    },
  );

  testWidgets(
    'Prepare is explicit, discloses size and fee uncertainty, and Cancel never confirms',
    (tester) async {
      final vm = _SetupViewModel();
      await _mount(tester, vm);
      expect(vm.preparations, 0);
      expect(vm.confirmations, 0);
      await tester.tap(find.text('Prepare wallet'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Prepare RGB wallet?'), findsOneWidget);
      expect(find.text('Up to 4 × 20000 sat'), findsOneWidget);
      expect(find.textContaining('final fee is unknown'), findsOneWidget);
      expect(find.textContaining('No total fee cap applies'), findsOneWidget);
      expect(vm.confirmations, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(vm.cancellations, 1);
      expect(vm.confirmations, 0);
      expect(find.text('Prepare wallet'), findsOneWidget);
    },
  );

  testWidgets(
    'Confirm is single-shot; unresolved outcome exposes Check rather than replay',
    (tester) async {
      final vm = _SetupViewModel()..confirmationGate = Completer<void>();
      await _mount(tester, vm);
      await tester.tap(find.text('Prepare wallet'));
      await tester.pump(const Duration(milliseconds: 500));
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Confirm setup'),
      );
      // Two callbacks before the route transition still resolve one consent.
      button.onPressed!();
      button.onPressed!();
      await tester.pump(const Duration(milliseconds: 500));
      expect(vm.confirmations, 1);
      expect(vm.cancellations, 0);
      expect(find.text('Prepare wallet').hitTestable(), findsNothing);
      vm.confirmationGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Check preparation'), findsOneWidget);
      expect(find.text('Prepare wallet'), findsNothing);
      await tester.tap(find.text('Check preparation'));
      await tester.pumpAndSettle();
      expect(vm.checks, 1);
      expect(vm.confirmations, 1);
    },
  );
}
