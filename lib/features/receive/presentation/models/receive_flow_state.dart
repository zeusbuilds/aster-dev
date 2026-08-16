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
    final currentRequest = request;
    if (currentRequest == null && !route.target.requiresReceiveAmount) {
      throw ArgumentError.value(
        request,
        'request',
        'Only amount-required routes may start without a request.',
      );
    }
    if (currentRequest != null && currentRequest.route != route) {
      throw ArgumentError.value(request, 'request', 'Route mismatch.');
    }
    final appliedAmount = currentRequest?.amount;
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

  /// The currently usable request, or `null` while an amount-required target
  /// waits for its first exact amount.
  final WalletReceiveRequest? request;

  /// Pending sheet input; when present, [request] remains the encoded QR value.
  final String amountText;
  final WalletAmountInput amountInput;
  final ReceiveFlowOperation? operation;
  final ReceiveFlowFailure? retainedFailure;

  AppFailure? get failure => retainedFailure?.failure;

  bool get isBusy => operation != null;
  bool get isGenerating => operation == ReceiveFlowOperation.generatingRequest;
  bool get requiresReconciliation => failure?.requiresReconciliation ?? false;
  bool get amountRequired => route.target.requiresReceiveAmount;
  bool get canReadRequest => request != null && !isBusy;
  bool get canEditAmount =>
      !isBusy && (retainedFailure == null || retainedFailure!.allowsAmountEdit);

  /// Whether request generation may start with the current retained failure.
  bool get canGenerateRequest {
    if (isBusy) return false;
    final retained = retainedFailure;
    return retained == null ||
        (retained.operation == ReceiveFlowOperation.generatingRequest &&
            retained.failure.retryable);
  }

  /// Whether the currently rendered request may be regenerated unchanged.
  bool get canRegenerate => request != null && canGenerateRequest;

  bool get amountUsesSupportedGranularity {
    if (amountText.isEmpty) return true;
    final units = amountInput.units;
    if (units == null) return false;
    return route.target != WalletPaymentTarget.bitcoinLightning ||
        units % WalletAmount.millisatoshisPerSatoshi == 0;
  }

  bool get hasPendingAmountChange {
    final appliedUnits = request?.amount?.units;
    if (amountText.isEmpty) return !amountRequired && appliedUnits != null;
    return amountInput.isValid &&
        amountUsesSupportedGranularity &&
        amountInput.units != appliedUnits;
  }

  bool get canApplyAmount => canGenerateRequest && hasPendingAmountChange;
  bool isExpiredAt(DateTime now) => request?.isExpiredAt(now) ?? false;

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
