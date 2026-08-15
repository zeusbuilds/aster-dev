import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../shared/formatting/bitcoin_unit.dart';
import '../../../wallet/domain/models/models.dart';

/// Mutually exclusive request work owned by one route-scoped Receive flow.
enum ReceiveFlowOperation { generatingRequest, copyingRequest, sharingRequest }

/// A retained Receive failure together with the operation that produced it.
///
/// Copy and share failures are transient presentation results and are never
/// retained here. Request-generation provenance prevents a successful
/// read-only action from erasing a terminal or reconciliation-required failure.
@immutable
final class ReceiveFlowFailure {
  ReceiveFlowFailure({required this.operation, required this.failure}) {
    if (operation != ReceiveFlowOperation.generatingRequest) {
      throw ArgumentError.value(
        operation,
        'operation',
        'Only request-generation failures may be retained.',
      );
    }
  }

  final ReceiveFlowOperation operation;
  final AppFailure failure;

  /// Whether changing the amount creates a safely distinct request command.
  bool get allowsAmountEdit => !failure.requiresReconciliation;

  @override
  bool operator ==(Object other) =>
      other is ReceiveFlowFailure &&
      other.operation == operation &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(operation, failure);
}

/// Typed state for one asset-and-rail Receive flow.
@immutable
final class ReceiveFlowState {
  ReceiveFlowState({
    required this.route,
    required this.bitcoinUnit,
    required this.request,
    required this.amountText,
    required this.amountInput,
    this.operation,
    this.retainedFailure,
  }) {
    if (amountInput.text != amountText) {
      throw ArgumentError.value(
        amountInput,
        'amountInput',
        'Parsed text must match editable text.',
      );
    }
    if (request.route != route) {
      throw ArgumentError.value(request, 'request', 'Route mismatch.');
    }
    final appliedAmount = request.amount;
    if (appliedAmount != null && appliedAmount.assetId != route.asset.id) {
      throw ArgumentError.value(request, 'request', 'Asset mismatch.');
    }
    if (operation == ReceiveFlowOperation.generatingRequest &&
        retainedFailure != null) {
      throw ArgumentError(
        'Request generation cannot retain a previous generation failure.',
      );
    }
  }

  final PaymentRoute route;
  final BitcoinUnit bitcoinUnit;
  final WalletReceiveRequest request;

  /// Pending sheet input; [request] remains the currently encoded QR value.
  final String amountText;
  final WalletAmountInput amountInput;
  final ReceiveFlowOperation? operation;
  final ReceiveFlowFailure? retainedFailure;

  AppFailure? get failure => retainedFailure?.failure;

  bool get isBusy => operation != null;
  bool get isGenerating => operation == ReceiveFlowOperation.generatingRequest;
  bool get requiresReconciliation => failure?.requiresReconciliation ?? false;
  bool get canReadRequest => !isBusy;
  bool get canEditAmount =>
      !isBusy && (retainedFailure == null || retainedFailure!.allowsAmountEdit);

  /// Whether the same request-generation command may start again.
  bool get canRegenerate {
    if (isBusy) return false;
    final retained = retainedFailure;
    return retained == null ||
        (retained.operation == ReceiveFlowOperation.generatingRequest &&
            retained.failure.retryable);
  }

  bool get amountUsesSupportedGranularity {
    if (amountText.isEmpty) return true;
    final units = amountInput.units;
    if (units == null) return false;
    return route.target != WalletPaymentTarget.bitcoinLightning ||
        units % WalletAmount.millisatoshisPerSatoshi == 0;
  }

  bool get hasPendingAmountChange {
    final appliedUnits = request.amount?.units;
    if (amountText.isEmpty) return appliedUnits != null;
    return amountInput.isValid &&
        amountUsesSupportedGranularity &&
        amountInput.units != appliedUnits;
  }

  bool get canApplyAmount => canRegenerate && hasPendingAmountChange;
  bool isExpiredAt(DateTime now) => request.isExpiredAt(now);

  ReceiveFlowState copyWith({
    WalletReceiveRequest? request,
    String? amountText,
    WalletAmountInput? amountInput,
    Object? operation = _unchanged,
    Object? retainedFailure = _unchanged,
  }) {
    return ReceiveFlowState(
      route: route,
      bitcoinUnit: bitcoinUnit,
      request: request ?? this.request,
      amountText: amountText ?? this.amountText,
      amountInput: amountInput ?? this.amountInput,
      operation: identical(operation, _unchanged)
          ? this.operation
          : operation as ReceiveFlowOperation?,
      retainedFailure: identical(retainedFailure, _unchanged)
          ? this.retainedFailure
          : retainedFailure as ReceiveFlowFailure?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReceiveFlowState &&
      other.route == route &&
      other.bitcoinUnit == bitcoinUnit &&
      other.request == request &&
      other.amountText == amountText &&
      other.amountInput == amountInput &&
      other.operation == operation &&
      other.retainedFailure == retainedFailure;

  @override
  int get hashCode => Object.hash(
    route,
    bitcoinUnit,
    request,
    amountText,
    amountInput,
    operation,
    retainedFailure,
  );
}

const _unchanged = Object();
