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
  bool prepareRgbChangeOutputs = false,
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
    await _recipientText(tester, destinationField, 'invalid-payment-recipient');
    await _tap(tester, find.widgetWithText(CustomButton, 'Continue'));
    await _until(tester, () => container.read(provider).value?.failure != null);
    if (container.read(provider).value?.result != null) {
      throw const FullWalletQaFailure('qa_invalid_destination_accepted');
    }
    await control.event('send_invalid_destination_rejected', {
      'target': target.slug,
    });

    // Validation publishes its owned failure before the navigation command
    // releases the field. Do not write into that disabled TextField: test text
    // injection can change its controller without an accepted onChanged event.
    await _until(
      tester,
      () =>
          container.read(provider).value?.canChangeDestination == true &&
          tester.widget<TextField>(destinationField).enabled != false,
    );
    await _recipientText(tester, destinationField, destination);
    await _until(
      tester,
      () =>
          container.read(provider).value?.destination == destination &&
          tester.widget<TextField>(destinationField).controller?.text ==
              destination,
    );
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

    final lockedAmount = current().amountIsLocked;
    if (lockedAmount) {
      if (current().amountInput.units != amountUnits ||
          tester
              .widget<AsterNumericKeypad>(find.byType(AsterNumericKeypad))
              .enabled) {
        throw const FullWalletQaFailure('qa_locked_invoice_amount_changed');
      }
    } else {
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
    }
    final exact = const WalletAmountInputCodec().formatUnits(
      units: amountUnits,
      route: current().route,
      bitcoinUnit: current().bitcoinUnit,
    );
    if (!lockedAmount) await _amount(tester, exact);
    if (current().amountInput.units != amountUnits ||
        current().preview?.encodedDestination != destination ||
        find.bySemanticsLabel('Address, $destination').evaluate().isEmpty ||
        find.text('Local test fee rate').evaluate().isEmpty) {
      throw const FullWalletQaFailure('qa_send_review_mismatch');
    }
    if (current().preview?.witnessBitcoinAmountSats != null &&
        (find.text('Recipient Bitcoin output').evaluate().isEmpty ||
            find.text('1,000 sats').evaluate().isEmpty)) {
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
    if (!lockedAmount) await _amount(tester, exact);
    Future<void> reviewFreshFee() async {
      if (current().canSubmitAt(DateTime.now().toUtc())) return;
      if (!current().canAttemptSubmitAt(DateTime.now().toUtc())) {
        throw const FullWalletQaFailure('qa_send_review_not_available');
      }
      // A stale quote guarantees this action cannot dispatch. One user-owned
      // Send refreshes it; only the later reviewed Send may commit payment.
      await _tap(tester, find.widgetWithText(CustomButton, 'Send'));
      await _until(tester, () => !current().isBusy);
      if (current().result != null ||
          current().failure?.code != 'payment_fee_review_updated' ||
          !current().canSubmitAt(DateTime.now().toUtc())) {
        throw const FullWalletQaFailure('qa_fee_review_not_certified');
      }
      await control.event('send_fee_review_updated', {'target': target.slug});
    }

    await reviewFreshFee();
    if (prepareRgbChangeOutputs) {
      // These first two Send actions only review preparation. Cancel proves no
      // creation; Prepare authorizes exactly one separate Bitcoin transaction.
      await _tap(tester, find.widgetWithText(CustomButton, 'Send'));
      await _until(tester, () {
        if (current().failure case final failure?) {
          throw qaAppFailure('ui_setup_review', failure);
        }
        return find.text('Prepare wallet for USDT?').evaluate().length == 1;
      });
      await _tap(tester, find.widgetWithText(CustomButton, 'Cancel'));
      await _until(tester, () => !current().isBusy);
      final cancelled = requireQaSuccess(
        await repository.rgbWalletSetupStatus(),
        'ui_setup_cancelled',
      );
      if (cancelled.phase != RgbWalletSetupPhase.required ||
          current().result != null) {
        throw const FullWalletQaFailure('qa_setup_cancel_dispatched');
      }
      await _tap(tester, find.widgetWithText(CustomButton, 'Send'));
      await _until(tester, () {
        if (current().failure case final failure?) {
          throw qaAppFailure('ui_setup_review', failure);
        }
        return find.text('Prepare wallet for USDT?').evaluate().length == 1;
      });
      await _tap(tester, find.widgetWithText(CustomButton, 'Prepare'));
      await _until(tester, () => !current().isBusy);
      final prepared = requireQaSuccess(
        await repository.rgbWalletSetupStatus(),
        'ui_setup_submitted',
      );
      if (!{
            RgbWalletSetupPhase.pending,
            RgbWalletSetupPhase.ready,
          }.contains(prepared.phase) ||
          (prepared.phase == RgbWalletSetupPhase.pending &&
              prepared.transactionId == null) ||
          current().result != null) {
        throw const FullWalletQaFailure('qa_setup_submission_not_exact');
      }
      if (prepared.phase == RgbWalletSetupPhase.pending) {
        await control.request('rgb_setup_confirm_requested', {
          'txid': prepared.transactionId,
          'blocks': 3,
        });
      }
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      var ready = false;
      while (DateTime.now().isBefore(deadline)) {
        requireQaFrameworkHealthy(tester);
        requireQaSuccess(await repository.sync(), 'ui_setup_confirm_sync');
        final status = requireQaSuccess(
          await repository.rgbWalletSetupStatus(),
          'ui_setup_confirm_read',
        );
        if (status.phase == RgbWalletSetupPhase.ready) {
          ready = true;
          break;
        }
        await tester.pump(const Duration(milliseconds: 250));
      }
      if (!ready) {
        throw const FullWalletQaFailure('qa_setup_confirmation_timeout');
      }
      await control.event('send_change_preparation_passed', {
        'txid': prepared.transactionId,
      });
    }
    await reviewFreshFee();
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
    await _until(tester, () => find.text('Payment sent').evaluate().isNotEmpty);
    await _tap(tester, find.widgetWithText(CustomButton, 'Continue'));
    await _until(
      tester,
      () =>
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path ==
          RoutePaths.home,
    );
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

Future<void> _recipientText(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  await _until(
    tester,
    () =>
        field.evaluate().length == 1 &&
        tester.widget<TextField>(field).enabled != false,
  );
  final editable = tester.state<EditableTextState>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  // IntegrationTest uses the real platform TextInput channel. After Continue
  // unfocuses this same field, WidgetTester.showKeyboard's cached
  // focusedEditable can skip reconnecting it. Request the real editable's
  // keyboard explicitly; never mutate its controller or provider directly.
  editable.requestKeyboard();
  await tester.pump();
  await _until(tester, () => editable.widget.focusNode.hasFocus);
  await tester.enterText(field, text);
}

Future<void> _amount(WidgetTester tester, String text) async {
  final keypad = find.byType(AsterNumericKeypad);
  await _until(
    tester,
    () =>
        keypad.evaluate().length == 1 &&
        tester.widget<AsterNumericKeypad>(keypad).enabled,
  );
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
  await _until(tester, () {
    final widget = tester.widget(finder);
    return widget is! CustomButton || (widget.enabled && !widget.loading);
  });
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
