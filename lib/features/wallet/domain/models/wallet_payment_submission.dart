import '../../../../core/errors/app_failure.dart';
import 'wallet_payment.dart';

/// A durable dispatch marker is not evidence that native broadcast failed.
const walletPaymentSubmissionPendingFailure = AppFailure(
  code: 'payment_submission_unresolved',
  kind: AppFailureKind.conflict,
  userMessage:
      'A payment submission needs reconciliation. Activity remains available. '
      'Do not send this payment again; restarting does not resolve it.',
  retryable: false,
  outcomeUnknown: true,
);

enum WalletPaymentSubmissionPhase { submitting, accepted, rejected }

/// Read-only, wallet-bound submission evidence for support and recovery.
///
/// An accepted record contains the exact native transaction identity. A
/// submitting record has no authoritative transaction identity and must never
/// be cleared from an empty feed, a similar amount, or elapsed time.
final class WalletPaymentSubmission {
  const WalletPaymentSubmission({
    required this.id,
    required this.walletId,
    required this.command,
    required this.submittedAt,
    required this.phase,
    this.result,
    this.acknowledgementUncertain = false,
  });

  final String id;
  final String walletId;
  final WalletSendCommand command;
  final DateTime submittedAt;
  final WalletPaymentSubmissionPhase phase;
  final WalletSendResult? result;
  final bool acknowledgementUncertain;

  bool get requiresReconciliation =>
      phase == WalletPaymentSubmissionPhase.submitting ||
      acknowledgementUncertain;

  WalletPaymentSubmission withUncertainAcknowledgement() =>
      WalletPaymentSubmission(
        id: id,
        walletId: walletId,
        command: command,
        submittedAt: submittedAt,
        phase: phase,
        result: result,
        acknowledgementUncertain: true,
      );

  @override
  bool operator ==(Object other) =>
      other is WalletPaymentSubmission &&
      other.id == id &&
      other.walletId == walletId &&
      other.command == command &&
      other.submittedAt == submittedAt &&
      other.phase == phase &&
      other.result == result &&
      other.acknowledgementUncertain == acknowledgementUncertain;

  @override
  int get hashCode => Object.hash(
    id,
    walletId,
    command,
    submittedAt,
    phase,
    result,
    acknowledgementUncertain,
  );

  @override
  String toString() => 'WalletPaymentSubmission(${phase.name})';
}
