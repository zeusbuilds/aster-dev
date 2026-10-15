import 'package:aster/core/core.dart';
import 'package:aster/features/receive/presentation/models/models.dart';
import 'package:aster/features/receive/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'full_wallet_qa.dart';
import 'full_wallet_test_guard.dart';

/// Uses actual Receive consent UI. Cancel proves no native transaction; Confirm
/// is tapped once. Only sync/status reads are polled after financial dispatch.
Future<WalletReceiveRequest> qualifyRgbPreparationUi({
  required WidgetTester tester,
  required ProviderContainer container,
  required WalletRepository repository,
  required FullWalletQaControl control,
}) async {
  const target = WalletPaymentTarget.usdtOnchain;
  final beforeBalance = requireQaSuccess(
    await repository.balance(WalletAssetKind.bitcoin),
    'setup_cancel_balance_before',
  );
  final beforeFeed = requireQaSuccess(
    await repository.activityFeed(WalletAssetKind.bitcoin),
    'setup_cancel_history_before',
  );
  final beforeIds = beforeFeed.activities.map((item) => item.id).toSet();
  container.read(appRouterProvider).go('/receive/${target.slug}');
  await _until(
    tester,
    () => find.text('Use blind receive').hitTestable().evaluate().length == 1,
  );
  await _tap(tester, find.text('Use blind receive'));
  await _until(
    tester,
    () => find.text('Use blind receive?').evaluate().length == 1,
  );
  await _tap(tester, find.widgetWithText(TextButton, 'Use blind receive').last);
  await control.event('blind_receive_selected_explicitly');
  await _until(tester, () {
    final receive = container.read(receiveFlowViewModelProvider(target));
    if (receive case AsyncError(:final error, :final stackTrace)) {
      final failure = FailureMapper.from(error, stackTrace);
      if (failure.code != 'rgb_wallet_setup_required') {
        throw qaAppFailure('blind_receive', failure);
      }
    }
    return find.text('Prepare wallet').hitTestable().evaluate().length == 1;
  });
  await _tap(tester, find.text('Prepare wallet'));
  await _until(
    tester,
    () => find.text('Prepare RGB wallet?').evaluate().length == 1,
  );
  if (find
              .textContaining(
                'up to 4 wallet-owned outputs of 20000 sat each at ',
              )
              .evaluate()
              .length !=
          1 ||
      find.textContaining('no total fee cap applies').evaluate().length != 1) {
    throw const FullWalletQaFailure('qa_setup_review_disclosure_missing');
  }
  await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
  await _until(
    tester,
    () => find.text('Prepare wallet').hitTestable().evaluate().length == 1,
  );
  final afterBalance = requireQaSuccess(
    await repository.balance(WalletAssetKind.bitcoin),
    'setup_cancel_balance_after',
  );
  final afterFeed = requireQaSuccess(
    await repository.activityFeed(WalletAssetKind.bitcoin),
    'setup_cancel_history_after',
  );
  final afterIds = afterFeed.activities.map((item) => item.id).toSet();
  final cancelledStatus = requireQaSuccess(
    await repository.rgbWalletSetupStatus(),
    'setup_cancel_status',
  );
  if (beforeBalance.onchainSpendable != afterBalance.onchainSpendable ||
      beforeIds.length != afterIds.length ||
      !beforeIds.every(afterIds.contains) ||
      cancelledStatus.phase != RgbWalletSetupPhase.required) {
    throw const FullWalletQaFailure('qa_setup_cancel_changed_wallet');
  }
  await control.event('rgb_setup_cancel_passed');
  await _tap(tester, find.text('Prepare wallet'));
  await _until(
    tester,
    () => find.text('Prepare RGB wallet?').evaluate().length == 1,
  );
  await _tap(tester, find.widgetWithText(TextButton, 'Confirm setup'));
  await control.event('rgb_setup_confirm_tapped');
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  String? txid;
  var recordedBitcoinBalance = false;
  while (DateTime.now().isBefore(deadline)) {
    requireQaFrameworkHealthy(tester);
    requireQaSuccess(await repository.sync(), 'setup_confirmation_sync');
    final status = requireQaSuccess(
      await repository.rgbWalletSetupStatus(),
      'setup_confirmation_status',
    );
    txid = status.transactionId ?? txid;
    if (!recordedBitcoinBalance) {
      final bitcoin = requireQaSuccess(
        await repository.balance(WalletAssetKind.bitcoin),
        'setup_bitcoin_balance',
      );
      await control.event('rgb_setup_bitcoin_balance', {
        'setup_phase': status.phase.name,
        'settled_sats': bitcoin.onchainSettled.units,
        'future_sats': bitcoin.onchainFuture.units,
        'spendable_sats': bitcoin.onchainSpendable.units,
        'locked_sats': bitcoin.onchainLocked.units,
      });
      recordedBitcoinBalance = true;
    }
    if (status.phase == RgbWalletSetupPhase.ready) {
      // This is read-only status reconciliation followed by genuine invoice
      // reservation; it never calls createUtxos again.
      await qualifyPreparedBlindReceiveUi(
        tester,
        isBlindRequestReady: () => qaBlindReceiveReady(
          container.read(receiveFlowViewModelProvider(target)),
          container
              .read(receiveFlowViewModelProvider(target).notifier)
              .rgbReceiveMode,
        ),
      );
      final request = container
          .read(receiveFlowViewModelProvider(target))
          .value!
          .request!;
      final preview = requireQaSuccess(
        await repository.previewPayment(target, request.encodedRequest),
        'prepared_blind_invoice_preview',
      );
      requireQaBlindPreview(preview);
      final current = container.read(receiveFlowViewModelProvider(target));
      if (!qaBlindReceiveReady(
            current,
            container
                .read(receiveFlowViewModelProvider(target).notifier)
                .rgbReceiveMode,
          ) ||
          current.value?.request?.encodedRequest != request.encodedRequest) {
        throw const FullWalletQaFailure('qa_prepared_blind_invoice_changed');
      }
      if (txid == null) {
        throw const FullWalletQaFailure('qa_setup_confirmation_txid_missing');
      }
      await control.event('rgb_setup_confirmed', {
        'txid': txid,
        'requested_output_count': RgbWalletSetupReview.outputCount,
        'output_sats': RgbWalletSetupReview.outputValueSats,
      });
      return request;
    }
    if (status.phase == RgbWalletSetupPhase.required) {
      throw const FullWalletQaFailure('qa_setup_confirm_did_not_dispatch');
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  throw const FullWalletQaFailure('qa_setup_confirmation_timeout');
}

/// Wait for the actual enabled preparation check, or an already completed
/// Blind request. Native status may become ready before the UI has painted
/// confirm's pending result. Visibility alone does not make its button active.
Future<void> qualifyPreparedBlindReceiveUi(
  WidgetTester tester, {
  required bool Function() isBlindRequestReady,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  var checkDispatched = false;
  final check = find.widgetWithText(CustomButton, 'Check preparation');
  while (DateTime.now().isBefore(deadline)) {
    requireQaFrameworkHealthy(tester);
    if (isBlindRequestReady()) return;
    if (!checkDispatched && check.evaluate().length == 1) {
      final button = tester.widget<CustomButton>(check);
      if (button.enabled && !button.loading && button.onTap != null) {
        await tester.ensureVisible(check);
        await tester.pump();
        // A completed request supersedes a check while scrolling or painting.
        if (isBlindRequestReady()) return;
        final visible = check.hitTestable();
        if (visible.evaluate().length == 1) {
          final current = tester.widget<CustomButton>(visible);
          if (current.enabled && !current.loading && current.onTap != null) {
            // Mark before the gesture: this helper never retries the check,
            // confirms setup again, or chooses a different receive mode.
            checkDispatched = true;
            requireQaFrameworkHealthy(tester);
            await tester.tap(visible, warnIfMissed: false);
          }
        }
      }
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw const FullWalletQaFailure('qa_setup_blind_request_timeout');
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(deadline)) {
    requireQaFrameworkHealthy(tester);
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw const FullWalletQaFailure('qa_setup_ui_timeout');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, () => finder.evaluate().length == 1);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 400));
  await _until(tester, () => finder.hitTestable().evaluate().length == 1);
  requireQaFrameworkHealthy(tester);
  await tester.tap(finder.hitTestable(), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 600));
  requireQaFrameworkHealthy(tester);
}

bool qaBlindReceiveReady(
  AsyncValue<ReceiveFlowState> state,
  RgbReceiveMode mode,
) =>
    state is AsyncData<ReceiveFlowState> &&
    !state.isLoading &&
    !state.value.isBusy &&
    state.value.request != null &&
    mode == RgbReceiveMode.blind;

void requireQaBlindPreview(WalletPaymentPreview preview) {
  if (preview.route.target != WalletPaymentTarget.usdtOnchain ||
      preview.rgbRecipientType != RgbRecipientType.blind ||
      preview.witnessBitcoinAmountSats != null) {
    throw const FullWalletQaFailure('qa_prepared_invoice_not_blind');
  }
}
