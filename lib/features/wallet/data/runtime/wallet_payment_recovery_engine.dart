import '../../domain/models/models.dart';

/// A native, wallet-bound outbox. Preparing never releases a transaction to a
/// recipient, proxy or broadcaster. Inspection never repeats a payment.
abstract interface class WalletPaymentRecoveryEngine {
  /// Performs non-sending validation and encodes the immutable native request.
  /// The repository persists this document before [preparePaymentOperation].
  Future<String> paymentOperationRequest(
    String operationId,
    WalletSendCommand command,
  );

  /// Verifies that a restored native request still describes this exact app
  /// intent. It must not enforce current invoice/fee freshness for past sends.
  Future<void> validatePaymentOperationRequest(
    String request,
    String operationId,
    WalletSendCommand command,
  );

  Future<WalletPaymentRecoveryStatus> preparePaymentOperation(String request);
  Future<WalletPaymentRecoveryStatus> commitPaymentOperation(String request);
  Future<WalletPaymentRecoveryStatus> inspectPaymentOperation(String request);
  Future<WalletPaymentRecoveryStatus> cancelPaymentOperation(String request);
}

/// A deadline is not cancellation of native work. Exact non-sending inspection
/// may drain and observe it, while regular native work requires a deliberate
/// lifecycle reopen by the runtime that owns the secure credentials.
abstract interface class WalletPaymentDeadlineRecovery {
  bool get requiresPaymentReopen;
}

enum WalletPaymentRecoveryPhase {
  absent,
  preparing,
  prepared,
  committing,
  accepted,
  rejected,
}

/// Identity is established before commit. Only [WalletPaymentRecoveryPhase.accepted] is a receipt;
/// prepared/committing identity must never be presented as payment success.
final class WalletPaymentRecoveryStatus {
  const WalletPaymentRecoveryStatus({
    required this.phase,
    required this.endAuthorized,
    this.referenceId,
    this.batchTransferIndex,
    this.failureCode,
  });

  final WalletPaymentRecoveryPhase phase;
  final bool endAuthorized;
  final String? referenceId;
  final int? batchTransferIndex;

  /// Native machine state, never a stand-alone nonexecution certificate.
  /// In particular, an expired prepared invoice still needs cancellation and
  /// a matching rejected status before the app's mutation fence can be cleared.
  final String? failureCode;
}

/// Optional authoritative discovery when the app's own marker is missing.
/// Implementations return only native-authenticated exact commands for the
/// currently opened wallet/source/cohort. Discovery never grants Commit.
abstract interface class WalletPaymentDiscoveryEngine {
  Future<List<WalletDiscoveredPaymentOperation>>
  discoverPendingPaymentOperations();

  /// Validates a reconstructed app record against its exact native request.
  /// This compares reviewed native fields without inventing an original invoice.
  Future<void> validateDiscoveredPaymentOperation(
    String request,
    String operationId,
    WalletSendCommand command,
  );
}

final class WalletDiscoveredPaymentOperation {
  const WalletDiscoveredPaymentOperation({
    required this.operationId,
    required this.request,
    required this.command,
    required this.status,
  });

  final String operationId;
  final String request;
  final WalletSendCommand command;
  final WalletPaymentRecoveryStatus status;
}

/// Explicit, archive-verified support for revoking an already-dispatched RGB
/// handoff. Presence of ordinary pre-commit Cancel is not this capability.
abstract interface class WalletDispatchedRgbRevocationEngine {
  Future<bool> supportsDispatchedRgbRevocation();

  /// Explicit permission to revoke a handoff; ordinary Cancel never does this.
  Future<WalletPaymentRecoveryStatus> revokeDispatchedRgbOperation(
    String request,
  );
}
