import 'package:aster/core/errors/errors.dart';
import 'package:aster/features/send/presentation/models/models.dart';
import 'package:aster/features/send/presentation/view_model/view_models.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'full_wallet_qa.dart';
import 'full_wallet_test_guard.dart';

/// Enters the real Send form, rejects invalid inputs, cancels a reviewed
/// payment without spending, then submits one payment through the visible UI.
Future<WalletSendResult> qualifySendUi({
  required WidgetTester tester,
  required ProviderContainer container,
  required WalletRepository repository,
  required FullWalletQaControl control,
  required WalletPaymentTarget target,
  required String destination,
  required int amountUnits,
}) async {
  final provider = sendFlowViewModelProvider(target);
  requireQaFrameworkHealthy(tester);
  // Retain route state long enough to observe the accepted native result after
  // the production screen navigates home. This does not replace a provider.
  final subscription = container.listen(provider, (_, _) {});
  final before = requireQaSuccess(
    await repository.balance(target.assetKind),
    'ui_send_initial_balance',
  );
  try {
    container
        .read(appRouterProvider)
        .go(RoutePaths.sendAddressFor(target.slug));
    final destinationField = find.byType(TextField);
    await _until(tester, () {
      final state = container.read(provider);
      if (state.error case final AppFailureException error) {
        throw qaAppFailure('ui_send_load', error.failure);
      }
      return state.value?.canChangeDestination == true &&
          destinationField.evaluate().length == 1 &&
          tester.widget<TextField>(destinationField).enabled != false;
    });
    await tester.enterText(destinationField, 'invalid-payment-recipient');
    await _tap(tester, find.widgetWithText(CustomButton, 'Continue'));
    await _until(tester, () => container.read(provider).value?.failure != null);
    if (container.read(provider).value?.result != null) {
      throw const FullWalletQaFailure('qa_invalid_destination_accepted');
    }
    await control.event('send_invalid_destination_rejected', {
      'target': target.slug,
    });

    await tester.enterText(destinationField, destination);
    FocusManager.instance.primaryFocus?.unfocus();
    await _tap(tester, find.widgetWithText(CustomButton, 'Continue'));
    await _until(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().length == 1,
    );
    SendFlowState current() {
      final value = container.read(provider).value;
      if (value == null) {
        throw const FullWalletQaFailure('qa_send_state_missing');
      }
      return value;
    }

    final zeroButton = tester.widget<CustomButton>(
      find.widgetWithText(CustomButton, 'Send'),
    );
    if (current().amountInput.isValid || zeroButton.enabled) {
      throw const FullWalletQaFailure('qa_empty_amount_submittable');
    }
    final tooMuch = const WalletAmountInputCodec().formatUnits(
      units: current().availableUnits + 1,
      route: current().route,
      bitcoinUnit: current().bitcoinUnit,
    );
    await _amount(tester, tooMuch);
    if (tester
        .widget<CustomButton>(find.widgetWithText(CustomButton, 'Send'))
        .enabled) {
      throw const FullWalletQaFailure('qa_excess_amount_submittable');
    }
    final exact = const WalletAmountInputCodec().formatUnits(
      units: amountUnits,
      route: current().route,
      bitcoinUnit: current().bitcoinUnit,
    );
    await _amount(tester, exact);
    if (current().amountInput.units != amountUnits ||
        current().preview?.encodedDestination != destination ||
        find.text('Recipient').evaluate().isEmpty ||
        find.text('Local test fee rate').evaluate().isEmpty) {
      throw const FullWalletQaFailure('qa_send_review_mismatch');
    }
    if (current().preview?.witnessBitcoinAmountSats != null &&
        (find.text('Recipient Bitcoin output').evaluate().isEmpty ||
            find.text('1,000 sats').evaluate().isEmpty ||
            find
                .textContaining('in addition to network fee')
                .evaluate()
                .isEmpty)) {
      throw const FullWalletQaFailure('qa_witness_bitcoin_disclosure_missing');
    }
    await _tap(tester, find.byTooltip('Back'));
    await _until(tester, () => destinationField.evaluate().length == 1);
    final afterCancel = requireQaSuccess(
      await repository.balance(target.assetKind),
      'ui_send_cancel_balance',
    );
    if (afterCancel != before || current().result != null) {
      throw const FullWalletQaFailure('qa_send_cancel_changed_balance');
    }
    await control.event('send_amount_cancel_passed', {'target': target.slug});
    await _tap(tester, find.widgetWithText(CustomButton, 'Continue'));
    await _until(
      tester,
      () => find.byType(AsterNumericKeypad).evaluate().length == 1,
    );
    await _amount(tester, exact);
    await _until(tester, () => current().canSubmitAt(DateTime.now().toUtc()));
    await control.event('send_ui_confirm_requested', {
      'target': target.slug,
      'amount_units': amountUnits,
    });
    // Exactly one tap enters the real production submission owner. Never retry
    // this action on a timeout, error, route change or missing acknowledgement.
    await _tap(tester, find.widgetWithText(CustomButton, 'Send'));
    await _until(tester, () {
      final value = current();
      if (value.failure case final failure?) {
        throw qaAppFailure('ui_send_submit', failure);
      }
      return value.result != null;
    });
    final result = current().result!;
    if (result.amount.units != amountUnits || result.route.target != target) {
      throw const FullWalletQaFailure('qa_send_ui_result_mismatch');
    }
    await control.event('send_ui_accepted', {
      'target': target.slug,
      'amount_units': amountUnits,
      'txid': result.referenceId,
    });
    return result;
  } finally {
    subscription.close();
  }
}

Future<void> _amount(WidgetTester tester, String text) async {
  final keypad = find.byType(AsterNumericKeypad);
  if (tester.widget<AsterNumericKeypad>(keypad).value.isNotEmpty) {
    final clear = find.bySemanticsLabel('Delete digit').hitTestable();
    await tester.ensureVisible(clear);
    await tester.longPress(clear);
    await tester.pump(const Duration(milliseconds: 200));
  }
  for (final character in text.split('')) {
    await _tap(
      tester,
      find.descendant(of: keypad, matching: find.text(character)),
    );
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, () => finder.evaluate().length == 1);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 250));
  await _until(tester, () => finder.hitTestable().evaluate().length == 1);
  requireQaFrameworkHealthy(tester);
  await tester.tap(finder.hitTestable(), warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 250));
  requireQaFrameworkHealthy(tester);
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(deadline)) {
    requireQaFrameworkHealthy(tester);
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw const FullWalletQaFailure('qa_send_ui_timeout');
}
