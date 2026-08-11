import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../../wallet/domain/models/models.dart';

/// Mutually exclusive request work owned by one route-scoped Receive flow.
enum ReceiveFlowOperation { generatingRequest, copyingRequest, sharingRequest }

/// Typed state for one asset-and-rail Receive flow.
@immutable
final class ReceiveFlowState {
  ReceiveFlowState({
    required this.route,
    required this.bitcoinUnit,
    required this.currencyCode,
    required this.request,
    required this.amountText,
    required this.amountInput,
    this.operation,
    this.failure,
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
    if (request.route != route) {
      throw ArgumentError.value(request, 'request', 'Route mismatch.');
    }
    final appliedAmount = request.amount;
    if (appliedAmount != null && appliedAmount.assetId != route.asset.id) {
      throw ArgumentError.value(request, 'request', 'Asset mismatch.');
    }
    if (operation != null && failure != null) {
      throw ArgumentError('Active work cannot retain a previous failure.');
    }
  }

  final PaymentRoute route;
  final BitcoinUnit bitcoinUnit;
  final String currencyCode;
  final WalletReceiveRequest request;

  /// Pending sheet input; [request] remains the currently encoded QR value.
  final String amountText;
  final WalletAmountInput amountInput;
  final ReceiveFlowOperation? operation;
  final AppFailure? failure;

  bool get isBusy => operation != null;
  bool get isGenerating => operation == ReceiveFlowOperation.generatingRequest;
  bool get hasPendingAmountChange {
    final appliedUnits = request.amount?.units;
    if (amountText.isEmpty) return appliedUnits != null;
    return amountInput.isValid && amountInput.units != appliedUnits;
  }

  bool get canApplyAmount => !isBusy && hasPendingAmountChange;
  bool isExpiredAt(DateTime now) => request.isExpiredAt(now);

  ReceiveFlowState copyWith({
    WalletReceiveRequest? request,
    String? amountText,
    WalletAmountInput? amountInput,
    Object? operation = _unchanged,
    Object? failure = _unchanged,
  }) {
    return ReceiveFlowState(
      route: route,
      bitcoinUnit: bitcoinUnit,
      currencyCode: currencyCode,
      request: request ?? this.request,
      amountText: amountText ?? this.amountText,
      amountInput: amountInput ?? this.amountInput,
      operation: identical(operation, _unchanged)
          ? this.operation
          : operation as ReceiveFlowOperation?,
      failure: identical(failure, _unchanged)
          ? this.failure
          : failure as AppFailure?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReceiveFlowState &&
      other.route == route &&
      other.bitcoinUnit == bitcoinUnit &&
      other.currencyCode == currencyCode &&
      other.request == request &&
      other.amountText == amountText &&
      other.amountInput == amountInput &&
      other.operation == operation &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(
    route,
    bitcoinUnit,
    currencyCode,
    request,
    amountText,
    amountInput,
    operation,
    failure,
  );
}

const _unchanged = Object();
