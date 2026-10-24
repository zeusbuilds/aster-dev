import 'package:flutter/foundation.dart';

import '../../../../core/core.dart';
import '../../../../shared/feedback/feedback.dart';
import '../../../wallet/domain/models/models.dart';
import 'send_flow_state.dart';

/// Copy for one action response. Certainty changes wording only; mutation
/// permission remains exclusively governed by requiresReconciliation.
@immutable
final class SendFailureFeedback {
  const SendFailureFeedback._(this.title, this.message, this.variant);

  factory SendFailureFeedback.fromFailure(
    AppFailure failure, {
    SendFlowOperation? readOperation,
  }) {
    final feeReview =
        failure.code == walletFeeReviewChangedFailure.code ||
        failure.code == walletFeeReviewRequiredFailure.code ||
        failure.code == walletFeeUpdatedReviewFailure.code ||
        failure.code == 'payment_fee_refresh_required';
    final warning =
        failure.requiresReconciliation ||
        failure.kind == AppFailureKind.validation ||
        feeReview ||
        readOperation != null;
    final unknownPayment = failure.outcomeUnknown;
    final title = failure.requiresReconciliation
        ? unknownPayment
              ? 'Status unavailable'
              : failure.code == 'payment_receipt_persistence_required'
              ? 'Payment sent'
              : 'Payment not sent'
        : failure.code == 'payment_request_expired'
        ? 'Invoice expired'
        : feeReview
        ? 'Review network fee'
        : readOperation == SendFlowOperation.refreshingBalance
        ? 'Balance unavailable'
        : readOperation == SendFlowOperation.refreshingFee
        ? 'Network fee unavailable'
        : failure.kind == AppFailureKind.validation
        ? 'Check amount'
        : 'Unable to send';
    return SendFailureFeedback._(
      title,
      unknownPayment
          ? 'Check this send in Activity before trying again.'
          : failure.userMessage,
      warning ? ToastVariant.warning : ToastVariant.failure,
    );
  }

  final String title;
  final String message;
  final ToastVariant variant;
}
