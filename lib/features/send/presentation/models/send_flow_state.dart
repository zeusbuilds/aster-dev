import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../../wallet/domain/models/models.dart';

/// Mutually exclusive work owned by one route-scoped Send flow.
enum SendFlowOperation {
  readingClipboard,
  validatingDestination,
  refreshingBalance,
  refreshingFee,
  submitting,
}

/// A retained Send failure together with the operation that produced it.
///
/// Keeping provenance prevents a successful, unrelated operation from
/// laundering a terminal failure. The owning operation is the only operation
/// that may be retried without first changing the relevant payment input.
@immutable
final class SendFlowFailure {
  SendFlowFailure({required this.operation, required this.failure}) {
    if (operation == SendFlowOperation.readingClipboard ||
        operation == SendFlowOperation.refreshingFee) {
      throw ArgumentError.value(
        operation,
        'operation',
        'Clipboard and fee failures use dedicated presentation contracts.',
      );
    }
  }

  final SendFlowOperation operation;
  final AppFailure failure;

  bool get allowsDestinationEdit =>
      !failure.requiresReconciliation &&
      (operation == SendFlowOperation.validatingDestination ||
          operation == SendFlowOperation.submitting);

  bool get allowsAmountEdit =>
      !failure.requiresReconciliation &&
      operation == SendFlowOperation.submitting;

  @override
  bool operator ==(Object other) =>
      other is SendFlowFailure &&
      other.operation == operation &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(operation, failure);
}

/// Typed state for one asset-and-rail Send flow.
///
/// Destination text remains route-scoped and is deliberately omitted from
/// diagnostics. Monetary values are canonical integers owned by wallet-domain
/// contracts; [amountText] exists only to preserve the user's editable text.
@immutable
final class SendFlowState {
  SendFlowState({
    required this.route,
    required this.bitcoinUnit,
    required this.currencyCode,
    required this.balance,
    required this.destination,
    required this.amountText,
    required this.amountInput,
    this.preview,
    this.feeEstimate,
    this.feeFailure,
    this.operation,
    this.retainedFailure,
    this.result,
  }) {
    if (amountInput.text != amountText) {
      throw ArgumentError.value(
        amountInput,
        'amountInput',
        'Parsed text must match editable text.',
      );
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode)) {
      throw ArgumentError.value(currencyCode, 'currencyCode');
    }
    if (balance.asset != route.asset) {
      throw ArgumentError.value(balance, 'balance', 'Asset mismatch.');
    }
    final currentPreview = preview;
    if (currentPreview != null && currentPreview.route != route) {
      throw ArgumentError.value(preview, 'preview', 'Route mismatch.');
    }
    if (currentPreview != null && destination.isEmpty) {
      throw ArgumentError.value(destination, 'destination');
    }
    final encodedAmount = currentPreview?.amount;
    if (encodedAmount != null && amountInput.units != encodedAmount.units) {
      throw ArgumentError.value(
        amountInput,
        'amountInput',
        'Must preserve the destination-encoded amount.',
      );
    }
    if (route.rail == PaymentRail.lightning &&
        (feeEstimate != null || feeFailure != null)) {
      throw ArgumentError('Lightning state cannot contain on-chain fee data.');
    }
    if (feeEstimate != null && feeFailure != null) {
      throw ArgumentError('Fee data cannot be successful and failed.');
    }
    if (operation != null && retainedFailure != null) {
      throw ArgumentError('Active work cannot retain a previous failure.');
    }
    final completed = result;
    if (completed != null &&
        (completed.route != route ||
            completed.amount.units != amountInput.units ||
            operation != null ||
            retainedFailure != null ||
            feeFailure != null)) {
      throw ArgumentError.value(completed, 'result', 'Result mismatch.');
    }
  }

  final PaymentRoute route;
  final BitcoinUnit bitcoinUnit;
  final String currencyCode;
  final WalletBalance balance;

  /// Raw user input. Never include this value in logs or route arguments.
  final String destination;
  final WalletPaymentPreview? preview;

  final String amountText;
  final WalletAmountInput amountInput;
  final WalletFeeRateEstimate? feeEstimate;
  final AppFailure? feeFailure;
  final SendFlowOperation? operation;
  final SendFlowFailure? retainedFailure;
  final WalletSendResult? result;

  AppFailure? get failure => retainedFailure?.failure;

  /// Returns a retained failure only to the surface that owns it.
  AppFailure? failureFor(SendFlowOperation owner) {
    final retained = retainedFailure;
    return retained?.operation == owner ? retained?.failure : null;
  }

  bool get isBusy => operation != null;
  bool get requiresReconciliation => failure?.requiresReconciliation ?? false;
  bool get canEditPayment =>
      !isBusy && result == null && !requiresReconciliation;
  bool get canChangeDestination =>
      canEditPayment &&
      (retainedFailure == null || retainedFailure!.allowsDestinationEdit);
  bool get canChangeAmount =>
      canEditPayment &&
      (retainedFailure == null || retainedFailure!.allowsAmountEdit);
  bool get canReadClipboard => canChangeDestination;

  /// Whether [candidate] may start without changing payment input first.
  bool canStart(SendFlowOperation candidate) {
    if (!canEditPayment) return false;
    final retained = retainedFailure;
    return retained == null ||
        (retained.operation == candidate && retained.failure.retryable);
  }

  bool get canRefreshFee =>
      route.rail == PaymentRail.onchain &&
      canStart(SendFlowOperation.refreshingFee) &&
      (feeFailure == null || feeFailure!.retryable);
  bool get hasValidatedDestination => preview != null;
  bool get amountIsLocked => preview?.amount != null;
  bool get amountUsesSupportedGranularity {
    final units = amountInput.units;
    if (units == null) return false;
    return route.target != WalletPaymentTarget.bitcoinLightning ||
        amountIsLocked ||
        units % WalletAmount.millisatoshisPerSatoshi == 0;
  }

  bool get hasSufficientBalance {
    final units = amountInput.units;
    return units != null && units <= availableUnits;
  }

  int get availableUnits => switch (route.rail) {
    PaymentRail.onchain => balance.onchainSpendable.units,
    PaymentRail.lightning => balance.lightningSpendable.units,
  };

  bool isExpiredAt(DateTime now) => preview?.isExpiredAt(now) ?? false;

  bool canSubmitAt(DateTime now) {
    final retained = retainedFailure;
    if (isBusy ||
        result != null ||
        (retained != null &&
            (retained.operation != SendFlowOperation.submitting ||
                !retained.failure.retryable)) ||
        preview == null ||
        !amountInput.isValid ||
        !amountUsesSupportedGranularity ||
        !hasSufficientBalance ||
        isExpiredAt(now)) {
      return false;
    }
    if (route.rail == PaymentRail.lightning) return true;
    final estimate = feeEstimate;
    return feeFailure == null && estimate != null && !estimate.isStaleAt(now);
  }

  SendFlowState copyWith({
    WalletBalance? balance,
    String? destination,
    Object? preview = _unchanged,
    String? amountText,
    WalletAmountInput? amountInput,
    Object? feeEstimate = _unchanged,
    Object? feeFailure = _unchanged,
    Object? operation = _unchanged,
    Object? retainedFailure = _unchanged,
    Object? result = _unchanged,
  }) {
    return SendFlowState(
      route: route,
      bitcoinUnit: bitcoinUnit,
      currencyCode: currencyCode,
      balance: balance ?? this.balance,
      destination: destination ?? this.destination,
      preview: identical(preview, _unchanged)
          ? this.preview
          : preview as WalletPaymentPreview?,
      amountText: amountText ?? this.amountText,
      amountInput: amountInput ?? this.amountInput,
      feeEstimate: identical(feeEstimate, _unchanged)
          ? this.feeEstimate
          : feeEstimate as WalletFeeRateEstimate?,
      feeFailure: identical(feeFailure, _unchanged)
          ? this.feeFailure
          : feeFailure as AppFailure?,
      operation: identical(operation, _unchanged)
          ? this.operation
          : operation as SendFlowOperation?,
      retainedFailure: identical(retainedFailure, _unchanged)
          ? this.retainedFailure
          : retainedFailure as SendFlowFailure?,
      result: identical(result, _unchanged)
          ? this.result
          : result as WalletSendResult?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SendFlowState &&
      other.route == route &&
      other.bitcoinUnit == bitcoinUnit &&
      other.currencyCode == currencyCode &&
      other.balance == balance &&
      other.destination == destination &&
      other.preview == preview &&
      other.amountText == amountText &&
      other.amountInput == amountInput &&
      other.feeEstimate == feeEstimate &&
      other.feeFailure == feeFailure &&
      other.operation == operation &&
      other.retainedFailure == retainedFailure &&
      other.result == result;

  @override
  int get hashCode => Object.hash(
    route,
    bitcoinUnit,
    currencyCode,
    balance,
    destination,
    preview,
    amountText,
    amountInput,
    feeEstimate,
    feeFailure,
    operation,
    retainedFailure,
    result,
  );
}

const _unchanged = Object();
