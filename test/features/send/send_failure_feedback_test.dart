import 'package:aster/core/core.dart';
import 'package:aster/features/send/presentation/models/models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:aster/shared/feedback/feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown payment copy preserves the full non-retryable fence', () {
    final failure = walletPaymentSubmissionPendingFailure;
    final feedback = SendFailureFeedback.fromFailure(failure);
    expect(feedback.title, 'Status unavailable');
    expect(
      feedback.message,
      'Check this send in Activity before trying again.',
    );
    expect(feedback.variant, ToastVariant.warning);
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.retryable, isFalse);
  });

  test('known cleanup and accepted receipt copy never imply ambiguity', () {
    for (final (code, title) in [
      ('payment_not_sent_cleanup_required', 'Payment not sent'),
      ('payment_receipt_persistence_required', 'Payment sent'),
    ]) {
      final failure = AppFailure(
        code: code,
        kind: AppFailureKind.storage,
        userMessage: 'Check this send in Activity.',
        retryable: false,
        requiresReconciliation: true,
      );
      final feedback = SendFailureFeedback.fromFailure(failure);
      expect(feedback.title, title);
      expect(feedback.message, failure.userMessage);
      expect(feedback.variant, ToastVariant.warning);
      expect(failure.requiresReconciliation, isTrue);
      expect(failure.retryable, isFalse);
    }
  });

  test(
    'ordinary action and prerequisite failure copy stays operation-owned',
    () {
      const failure = AppFailure(
        code: 'network_down',
        kind: AppFailureKind.connectivity,
        userMessage: 'Please try again.',
        retryable: true,
      );
      final sending = SendFailureFeedback.fromFailure(failure);
      expect(sending.title, 'Unable to send');
      expect(sending.variant, ToastVariant.failure);
      final balance = SendFailureFeedback.fromFailure(
        failure,
        readOperation: SendFlowOperation.refreshingBalance,
      );
      expect(balance.title, 'Balance unavailable');
      expect(balance.variant, ToastVariant.warning);
      final fee = SendFailureFeedback.fromFailure(
        failure,
        readOperation: SendFlowOperation.refreshingFee,
      );
      expect(fee.title, 'Network fee unavailable');
    },
  );
}
