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
    this.failure,
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
    if (operation != null && failure != null) {
      throw ArgumentError('Active work cannot retain a previous failure.');
    }
    final completed = result;
    if (completed != null &&
        (completed.route != route ||
            completed.amount.units != amountInput.units ||
            operation != null)) {
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
  final AppFailure? failure;
  final WalletSendResult? result;

  bool get isBusy => operation != null;
  bool get hasValidatedDestination => preview != null;
  bool get amountIsLocked => preview?.amount != null;
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
    if (isBusy ||
        result != null ||
        preview == null ||
        !amountInput.isValid ||
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
    Object? failure = _unchanged,
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
      failure: identical(failure, _unchanged)
          ? this.failure
          : failure as AppFailure?,
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
      other.failure == failure &&
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
    failure,
    result,
  );
}

const _unchanged = Object();
