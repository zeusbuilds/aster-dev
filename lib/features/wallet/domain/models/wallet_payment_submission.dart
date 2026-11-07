import '../../../../core/errors/app_failure.dart';
import 'wallet_payment.dart';

/// An unknown payment remains guarded until its exact native outcome is known.
const walletPaymentSubmissionPendingFailure = AppFailure(
  code: 'payment_submission_unresolved',
  kind: AppFailureKind.conflict,
  userMessage: 'Check this payment in Activity before sending again.',
  retryable: false,
  outcomeUnknown: true,
);

enum WalletPaymentSubmissionPhase { submitting, accepted, rejected }

/// Payment execution certainty is independent of required storage/cleanup work.
enum WalletPaymentSubmissionOutcome { notSubmitted, unknown, accepted }

bool isWalletPaymentSubmissionFenceFailure(AppFailure failure) =>
    failure.requiresReconciliation &&
    const {
      'payment_submission_unresolved',
      'payment_not_sent_cleanup_required',
      'payment_receipt_persistence_required',
    }.contains(failure.code);

/// Read-only, wallet-bound submission evidence for support and recovery.
///
/// An accepted record contains the exact native transaction identity. A
/// legacy submitting record has no authoritative transaction identity. Version
/// 2 links to a native durable operation; neither version can be cleared from
/// an empty feed, a similar amount, or elapsed time.
final class WalletPaymentSubmission {
  const WalletPaymentSubmission({
    required this.id,
    required this.walletId,
    required this.command,
    required this.submittedAt,
    required this.phase,
    this.result,
    this.recoveryRequest,
    this.acknowledgementUncertain = false,
    this.commitAttempted = true,
    this.journalVersion = 3,
    this.nativeDiscovered = false,
  });

  final String id;
  final String walletId;
  final WalletSendCommand command;

  /// Local intent time, or discovery time when [nativeDiscovered] is true.
  /// Discovery time must not be presented as the original payment time.
  final DateTime submittedAt;

  DateTime? get paymentSubmittedAt => nativeDiscovered ? null : submittedAt;
  final WalletPaymentSubmissionPhase phase;
  final WalletSendResult? result;

  /// Version 2 native operation request. Null identifies a legacy one-shot
  /// attempt; absence in the new native outbox cannot resolve such an attempt.
  final String? recoveryRequest;
  final bool acknowledgementUncertain;

  /// Recorded durably before entering Commit. Older journals conservatively
  /// default to true because they did not record this boundary. Prepare alone
  /// cannot release a payment, although it may retain reservations to clean up.
  final bool commitAttempted;

  /// Preserve immutable receipt bytes written by an older journal schema.
  final int journalVersion;

  /// Reconstructed from authenticated native inventory after app marker loss.
  /// Its destination may be a native RGB recipient reference, not the original
  /// invoice text. This record never authorizes Commit, even on explicit Resume.
  final bool nativeDiscovered;

  WalletPaymentSubmissionOutcome get outcome => switch (phase) {
    WalletPaymentSubmissionPhase.accepted =>
      WalletPaymentSubmissionOutcome.accepted,
    WalletPaymentSubmissionPhase.rejected =>
      WalletPaymentSubmissionOutcome.notSubmitted,
    WalletPaymentSubmissionPhase.submitting =>
      commitAttempted
          ? WalletPaymentSubmissionOutcome.unknown
          : WalletPaymentSubmissionOutcome.notSubmitted,
  };

  AppFailure get reconciliationFailure => switch (outcome) {
    WalletPaymentSubmissionOutcome.unknown =>
      walletPaymentSubmissionPendingFailure,
    WalletPaymentSubmissionOutcome.notSubmitted => const AppFailure(
      code: 'payment_not_sent_cleanup_required',
      kind: AppFailureKind.storage,
      userMessage:
          'Nothing was sent. Check this send in Activity before trying again.',
      retryable: false,
      requiresReconciliation: true,
    ),
    WalletPaymentSubmissionOutcome.accepted => const AppFailure(
      code: 'payment_receipt_persistence_required',
      kind: AppFailureKind.storage,
      userMessage:
          'Payment sent. Check this send in Activity before sending again.',
      retryable: false,
      requiresReconciliation: true,
    ),
  };

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
        recoveryRequest: recoveryRequest,
        acknowledgementUncertain: true,
        commitAttempted: commitAttempted,
        journalVersion: journalVersion,
        nativeDiscovered: nativeDiscovered,
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
      other.recoveryRequest == recoveryRequest &&
      other.acknowledgementUncertain == acknowledgementUncertain &&
      other.commitAttempted == commitAttempted &&
      other.journalVersion == journalVersion &&
      other.nativeDiscovered == nativeDiscovered;

  @override
  int get hashCode => Object.hash(
    id,
    walletId,
    command,
    submittedAt,
    phase,
    result,
    recoveryRequest,
    acknowledgementUncertain,
    commitAttempted,
    journalVersion,
    nativeDiscovered,
  );

  @override
  String toString() => 'WalletPaymentSubmission(${phase.name})';
}
