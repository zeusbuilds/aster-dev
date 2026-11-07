import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';
import '../runtime/runtime.dart';
import '../storage/storage.dart';

/// Used exclusively within WalletRepository's command queue. Storage commits
/// and native dispatch remain inside the same runtime lease as fee review.
final class WalletPaymentSubmissions {
  WalletPaymentSubmissions(
    this.runtime,
    this.store, {
    required this.receipts,
    required this.newId,
    required this.clock,
  });

  final WalletRuntime runtime;
  final WalletPaymentJournalStore? store;
  final WalletPaymentReceiptStore? receipts;
  final String Function() newId;
  final DateTime Function() clock;
  // Per-wallet volatile evidence survives a safe switch to another wallet.
  // An acceptance/known non-submission must not be downgraded merely because
  // a different wallet begins its own independent send.
  final Map<String, WalletPaymentSubmission> _retainedAttempts = {};

  WalletPaymentSubmission? get _unconfirmedAttempt =>
      _retainedAttempts[runtime.activeProfile?.id];

  set _unconfirmedAttempt(WalletPaymentSubmission? value) {
    if (value != null) {
      _retainedAttempts[value.walletId] = value;
    } else {
      _retainedAttempts.remove(runtime.activeProfile?.id);
    }
  }

  Future<void> validateProfiles(Iterable<WalletProfile> profiles) async {
    if (store == null) return;
    for (final profile in profiles) {
      await _read(profile, archiveAccepted: false);
      await _archived(profile);
    }
  }

  /// Reapply the durable mutation fence after native startup, keeping the
  /// existing wallet readable. Corrupt records fail application bootstrap.
  Future<void> restoreFence() async {
    final profile = runtime.activeProfile;
    if (profile == null || store == null) return;
    var record = await _read(profile, archiveAccepted: false);
    record = await _discoverNativeAttempt(profile, record) ?? record;
    final retained = _unconfirmedAttempt;
    if (retained != null &&
        (record == null ||
            record.id == retained.id ||
            !record.requiresReconciliation)) {
      await runtime.retainUnresolvedPayment(
        failure: retained.reconciliationFailure,
      );
      return;
    }
    if (record == null) return;
    if (record.phase == WalletPaymentSubmissionPhase.accepted) {
      try {
        await _archive(record, profile);
      } on StoredDataCorruptionException {
        rethrow;
      } catch (_) {
        // Exact acceptance survives a process restart even while its required
        // archive remains unavailable. Restore a storage fence, not ambiguity.
        _unconfirmedAttempt = record.withUncertainAcknowledgement();
        await runtime.retainUnresolvedPayment(
          failure: record.reconciliationFailure,
        );
        return;
      }
    }
    if (record.requiresReconciliation) {
      _unconfirmedAttempt = record;
      await runtime.retainUnresolvedPayment(
        failure: record.reconciliationFailure,
      );
    }
  }

  Future<WalletPaymentSubmission?> _discoverNativeAttempt(
    WalletProfile profile,
    WalletPaymentSubmission? existing,
  ) async {
    final result = await runtime.readPaymentState((engine) async {
      if (engine is! WalletPaymentDiscoveryEngine) {
        return const <WalletDiscoveredPaymentOperation>[];
      }
      return (engine as WalletPaymentDiscoveryEngine)
          .discoverPendingPaymentOperations();
    });
    if (result case AppFailureResult<List<WalletDiscoveredPaymentOperation>>(
      :final failure,
    )) {
      throw AppFailureException(failure);
    }
    final operations =
        (result as AppSuccess<List<WalletDiscoveredPaymentOperation>>).value;
    if (operations.isEmpty) return null;
    // Product mutation serialization permits one unresolved native operation.
    // Multiple entries cannot be silently selected or dropped.
    if (operations.length != 1) throw const StoredDataCorruptionException();
    final operation = operations.single;
    if (existing?.requiresReconciliation == true) {
      if (existing!.id != operation.operationId ||
          existing.recoveryRequest != operation.request) {
        throw const StoredDataCorruptionException();
      }
      return null;
    }
    if (existing?.id == operation.operationId) {
      // A terminal app receipt cannot be downgraded by an older native copy.
      throw const StoredDataCorruptionException();
    }
    if (existing?.phase == WalletPaymentSubmissionPhase.accepted) {
      await _archive(existing!, profile);
    }
    if (operation.status.phase != WalletPaymentRecoveryPhase.preparing &&
        operation.status.phase != WalletPaymentRecoveryPhase.prepared &&
        operation.status.phase != WalletPaymentRecoveryPhase.committing) {
      throw const StoredDataCorruptionException();
    }
    if (operation.status.endAuthorized !=
        (operation.status.phase == WalletPaymentRecoveryPhase.committing)) {
      throw const StoredDataCorruptionException();
    }
    final discovered = WalletPaymentSubmission(
      id: operation.operationId,
      walletId: profile.id,
      command: operation.command,
      submittedAt: clock().toUtc(),
      phase: WalletPaymentSubmissionPhase.submitting,
      recoveryRequest: operation.request,
      commitAttempted: operation.status.endAuthorized,
      journalVersion: 4,
      nativeDiscovered: true,
    );
    // Validate the complete app-owned representation before retaining it or
    // replacing a terminal journal. Discovery is evidence, never authorization.
    if (_decode(_encode(discovered, profile), profile) != discovered) {
      throw const StoredDataCorruptionException();
    }
    _unconfirmedAttempt = discovered;
    await runtime.retainUnresolvedPayment(
      failure: discovered.reconciliationFailure,
    );
    await _write(discovered, profile, WalletPaymentSubmissionPhase.submitting);
    final persisted = await _read(profile, archiveAccepted: false);
    if (persisted != discovered) throw const StoredDataCorruptionException();
    return persisted;
  }

  Future<AppResult<void>> assertResolved() async {
    try {
      // A durable acknowledgement written just before an I/O error still
      // requires explicit exact-history reconciliation in this process.
      if (runtime.hasPaymentSubmissionFence) {
        return AppResult.failure(runtime.snapshot.failure!);
      }
      final profile = runtime.activeProfile;
      if (profile == null || store == null) {
        return const AppResult.success(null);
      }
      final record = await _read(profile, archiveAccepted: false);
      if (record?.phase == WalletPaymentSubmissionPhase.accepted) {
        try {
          // A newer intent may not overwrite the last accepted receipt before
          // it is archived. This mutation gate owns the backfill; read-only
          // status/history never attempt it.
          await _archive(record!, profile);
        } on StoredDataCorruptionException {
          rethrow;
        } catch (_) {
          _unconfirmedAttempt = record!.withUncertainAcknowledgement();
          return await runtime.retainUnresolvedPayment(
            failure: record.reconciliationFailure,
          );
        }
      }
      if (record?.requiresReconciliation == true) {
        return AppResult.failure(record!.reconciliationFailure);
      }
      return const AppResult.success(null);
    } catch (error, stack) {
      return AppResult.failure(FailureMapper.from(error, stack));
    }
  }

  /// Pure deletion guard: never clears or retries a payment during removal.
  Future<AppResult<void>> assertWalletDeletionSafe(
    WalletProfile profile,
  ) async {
    try {
      final retained = _retainedAttempts[profile.id];
      final record = store == null
          ? null
          : await _read(profile, archiveAccepted: false);
      await _archived(profile);
      if (retained != null || record?.requiresReconciliation == true) {
        return AppResult.failure((retained ?? record!).reconciliationFailure);
      }
      return const AppResult.success(null);
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  void forgetDeletedWallet(String walletId) =>
      _retainedAttempts.remove(walletId);

  Future<AppResult<WalletPaymentSubmission?>> status() async {
    try {
      final profile = runtime.activeProfile;
      // Read-only status must not itself retry required archive writes. Exact
      // native acceptance retained in this process remains acceptance even if
      // the local receipt/archive acknowledgement is unavailable.
      final record = profile == null || store == null
          ? null
          : await _read(profile, archiveAccepted: false);
      final attempt = _unconfirmedAttempt;
      if (attempt != null &&
          attempt.walletId == profile?.id &&
          (record == null ||
              record.id == attempt.id ||
              !record.requiresReconciliation)) {
        return AppResult.success(attempt.withUncertainAcknowledgement());
      }
      return AppResult.success(record);
    } catch (error, stack) {
      return AppResult.failure(FailureMapper.from(error, stack));
    }
  }

  /// New operations query the native durable outbox by the saved immutable
  /// request. Legacy unidentified one-shot submissions retain their fence.
  Future<AppResult<void>> reconcile() =>
      _recover(resumeAuthorizedCommit: false);

  /// Deliberate recovery action for an already-authorized native operation.
  /// This never prepares a new transaction or changes its saved signed bytes.
  /// It is intentionally separate from the non-sending status check.
  Future<AppResult<void>> resume() => _recover(resumeAuthorizedCommit: true);

  Future<AppResult<void>> _recover({
    required bool resumeAuthorizedCommit,
  }) => runtime.reconcilePaymentSubmission((engine) async {
    final profile = runtime.activeProfile;
    if (profile == null || store == null) return false;
    var record = await _recoverJournalAcknowledgement(
      () => _read(profile, archiveAccepted: false),
    );
    final attempt = _unconfirmedAttempt;
    if (attempt != null && record?.id != attempt.id) {
      if (resumeAuthorizedCommit ||
          attempt.recoveryRequest == null ||
          attempt.walletId != profile.id ||
          record?.requiresReconciliation == true) {
        return false;
      }
      // Both app marker/rejection writes can fail before native entry, leaving
      // the previous terminal record or no record on disk. The non-sending
      // Check action can certify and durably close this exact in-memory intent
      // once storage recovers. It must never resolve an older receipt instead,
      // replace a different unresolved intent, or authorize commit from memory.
      record = _decode(_encode(attempt, profile), profile);
    }
    final request = record?.recoveryRequest;
    if (record != null && request != null) {
      final recoveryRecord = record;
      if (engine is! WalletPaymentRecoveryEngine) return false;
      final recovery = engine as WalletPaymentRecoveryEngine;
      if (record.nativeDiscovered) {
        if (engine is! WalletPaymentDiscoveryEngine) return false;
        await (engine as WalletPaymentDiscoveryEngine)
            .validateDiscoveredPaymentOperation(
              request,
              record.id,
              record.command,
            );
      } else {
        await recovery.validatePaymentOperationRequest(
          request,
          record.id,
          record.command,
        );
      }
      var status = await recovery.inspectPaymentOperation(request);
      if (resumeAuthorizedCommit &&
          !record.nativeDiscovered &&
          status.phase == WalletPaymentRecoveryPhase.committing &&
          status.endAuthorized) {
        final referenceId = status.referenceId;
        if (referenceId == null ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(referenceId)) {
          throw const StoredDataCorruptionException();
        }
        await runtime.recoverPaymentOwnerIfNeeded(engine);
        status = await recovery.commitPaymentOperation(request);
        if (status.referenceId != referenceId) {
          throw const AppFailureException(
            AppFailure(
              code: 'payment_native_identity_changed',
              kind: AppFailureKind.storage,
              userMessage: 'Wallet recovery is required.',
              retryable: false,
              requiresReconciliation: true,
            ),
          );
        }
      } else if ((!resumeAuthorizedCommit || record.nativeDiscovered) &&
          !status.endAuthorized &&
          (status.phase == WalletPaymentRecoveryPhase.absent ||
              status.phase == WalletPaymentRecoveryPhase.preparing ||
              status.phase == WalletPaymentRecoveryPhase.prepared)) {
        // The explicit Check action may release a proven undispatched native
        // preparation. It never commits or re-sends the user's payment.
        await runtime.recoverPaymentOwnerIfNeeded(engine);
        status = await recovery.cancelPaymentOperation(request);
      }
      if (status.phase == WalletPaymentRecoveryPhase.accepted) {
        final receipt = _recoveryReceipt(record.command, status);
        _unconfirmedAttempt = _updated(
          record,
          phase: WalletPaymentSubmissionPhase.accepted,
          result: receipt,
        ).withUncertainAcknowledgement();
        await _recoverJournalAcknowledgement(() async {
          await _write(
            recoveryRecord,
            profile,
            WalletPaymentSubmissionPhase.accepted,
            result: receipt,
          );
          // Read back and archive before reopening the mutation lease. A lost
          // write acknowledgement leaves recovery repeatable by native identity.
          final accepted = await _read(profile);
          if (accepted?.id != recoveryRecord.id ||
              accepted?.result != receipt) {
            throw const StoredDataCorruptionException();
          }
        });
        _unconfirmedAttempt = null;
        return true;
      }
      if (status.phase == WalletPaymentRecoveryPhase.rejected &&
          !status.endAuthorized) {
        _unconfirmedAttempt = _updated(
          record,
          phase: WalletPaymentSubmissionPhase.rejected,
        ).withUncertainAcknowledgement();
        await _recoverJournalAcknowledgement(() async {
          await _write(
            recoveryRecord,
            profile,
            WalletPaymentSubmissionPhase.rejected,
          );
          final rejected = await _read(profile);
          if (rejected?.id != recoveryRecord.id ||
              rejected?.phase != WalletPaymentSubmissionPhase.rejected) {
            throw const StoredDataCorruptionException();
          }
        });
        _unconfirmedAttempt = null;
        return true;
      }
      // Absence is not a cancellation certificate. Interrupted preparation may
      // own native resources, and prepared/committing are not acceptance.
      return false;
    }
    final result = record?.result;
    if (record?.phase != WalletPaymentSubmissionPhase.accepted ||
        result == null ||
        record?.id != _unconfirmedAttempt?.id) {
      return false;
    }
    // Match unmodified native history, never the archive-enriched feed. A
    // native self-transfer establishes wallet ownership but cannot report the
    // user-selected gross amount: both recipient and change remain ours.
    final matches = (await engine.listActivity(result.route.asset)).where(
      (activity) =>
          _matchesIdentity(activity, result) &&
          (activity.operation == WalletActivityOperation.bitcoinSelfTransfer
              ? activity.amount == null
              : activity.amount == result.amount),
    );
    return matches.length == 1;
  });

  /// Adds reviewed amounts only to independently observed native transactions.
  /// Native status, direction, identity, fees and wallet balances stay intact.
  Future<List<WalletActivity>> reviewedHistory(
    List<WalletActivity> activities,
  ) async {
    final profile = runtime.activeProfile;
    if (profile == null || store == null) return activities;
    // History is an audit read. A required receipt repair must not retry its
    // archive write here or hide the native entry that opens the Check action.
    final current = await _read(profile, archiveAccepted: false);
    final archive = await _archived(profile);
    final retained = _unconfirmedAttempt;
    final byIdentity = <String, WalletSendResult>{};
    for (final receipt in [
      ...archive,
      if (current?.phase == WalletPaymentSubmissionPhase.accepted) current!,
      if (retained?.phase == WalletPaymentSubmissionPhase.accepted) retained!,
    ]) {
      final result = receipt.result!;
      final key = _receiptKey(profile, result);
      final previous = byIdentity[key];
      if (previous != null && previous != result) {
        throw const AppFailureException(walletActivityConsistencyFailure);
      }
      byIdentity[key] = result;
    }
    final matched = <String>{};
    return List.unmodifiable(
      activities.map((activity) {
        final txid = activity.txid;
        if (txid == null) return activity;
        final result =
            byIdentity[_identityKey(
              profile,
              activity.asset,
              txid,
              activity.batchTransferIndex,
            )];
        if (result != null && _matchesIdentity(activity, result)) {
          if (!matched.add(_receiptKey(profile, result)) ||
              (activity.amount != null && activity.amount != result.amount)) {
            throw const AppFailureException(walletActivityConsistencyFailure);
          }
          return activity.withReviewedAmount(result.amount);
        }
        return activity;
      }),
    );
  }

  Future<WalletSendResult> dispatch(
    WalletEngine engine,
    WalletSendCommand command, {
    void Function()? assertAuthorized,
  }) async {
    assertAuthorized?.call();
    final profile = runtime.activeProfile;
    if (store == null || receipts == null || profile == null) {
      throw const AppFailureException(
        AppFailure(
          code: 'payment_journal_unavailable',
          kind: AppFailureKind.configuration,
          userMessage: 'Payment submission storage is unavailable.',
          retryable: false,
        ),
      );
    }
    if (engine is! WalletPaymentRecoveryEngine) {
      throw const AppFailureException(
        AppFailure(
          code: 'payment_recovery_unavailable',
          kind: AppFailureKind.configuration,
          userMessage: 'Safe payment recovery is unavailable.',
          retryable: false,
        ),
      );
    }
    final recovery = engine as WalletPaymentRecoveryEngine;
    final previous = await _read(profile, archiveAccepted: false);
    if (previous?.requiresReconciliation == true) {
      throw AppFailureException(previous!.reconciliationFailure);
    }
    await _archived(profile);
    String? id;
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final candidate = newId();
      if (candidate != previous?.id) {
        id = candidate;
        break;
      }
    }
    if (id == null) {
      throw const AppFailureException(
        AppFailure(
          code: 'payment_submission_id_collision',
          kind: AppFailureKind.conflict,
          userMessage: 'A unique payment submission could not be prepared.',
          retryable: false,
        ),
      );
    }
    // Command construction performs only validation/reads. No native prepare,
    // proxy post or broadcast may occur before the app intent is durable.
    final String recoveryRequest;
    try {
      recoveryRequest = await recovery.paymentOperationRequest(id, command);
    } catch (error, stack) {
      // Request construction is reads/validation only. Even a native deadline
      // here cannot mean a payment was sent: Prepare and Commit did not run.
      final failure = FailureMapper.from(error, stack);
      final deadlineNeedsReopen =
          engine is WalletPaymentDeadlineRecovery &&
          (engine as WalletPaymentDeadlineRecovery).requiresPaymentReopen;
      if (deadlineNeedsReopen) {
        // Restore only the native owner. Never retry request construction or a
        // monetary operation automatically. A failed reopen keeps its stronger
        // owner quarantine rather than installing an unidentified payment.
        await runtime.recoverPaymentOwnerIfNeeded(engine);
      }
      Error.throwWithStackTrace(
        AppFailureException(
          AppFailure(
            code: deadlineNeedsReopen ? 'payment_not_dispatched' : failure.code,
            kind: failure.kind,
            userMessage: failure.outcomeUnknown
                ? 'Nothing was sent. Try again.'
                : failure.userMessage,
            retryable: deadlineNeedsReopen || failure.retryable,
            requiresReconciliation:
                !deadlineNeedsReopen && failure.requiresReconciliation,
            outcomeUnknown: false,
            retryAfter: failure.retryAfter,
            cause: FailureMapper.diagnosticCause(error),
            stackTrace: stack,
          ),
        ),
        stack,
      );
    }
    if (recoveryRequest.isEmpty || recoveryRequest.length > 100000) {
      throw const StoredDataCorruptionException();
    }
    // Request construction cannot send. Reject a revoked foreground session
    // before creating a new durable intent or entering native preparation.
    assertAuthorized?.call();
    var intent = WalletPaymentSubmission(
      id: id,
      walletId: profile.id,
      command: command,
      submittedAt: clock().toUtc(),
      phase: WalletPaymentSubmissionPhase.submitting,
      recoveryRequest: recoveryRequest,
      commitAttempted: false,
    );
    // Validate the same strict representation that must survive a restart.
    final encoded = _encode(intent, profile);
    _decode(encoded, profile);
    _unconfirmedAttempt = intent;
    try {
      await store!.write(profile.id, encoded);
    } catch (_, stack) {
      // Native was not entered. Record a definite rejection if storage can
      // acknowledge it; otherwise retain the marker for native cancellation
      // certification on the next explicit status check.
      try {
        await _write(intent, profile, WalletPaymentSubmissionPhase.rejected);
        final rejected = await _read(profile);
        if (rejected?.id != intent.id ||
            rejected?.phase != WalletPaymentSubmissionPhase.rejected) {
          throw const StoredDataCorruptionException();
        }
        _unconfirmedAttempt = null;
      } catch (rejectionError, rejectionStack) {
        _unresolved(rejectionError, rejectionStack);
      }
      Error.throwWithStackTrace(
        const AppFailureException(
          AppFailure(
            code: 'payment_not_dispatched',
            kind: AppFailureKind.storage,
            userMessage: 'The payment could not be saved. Nothing was sent.',
            retryable: true,
          ),
        ),
        stack,
      );
    }

    final WalletSendResult result;
    var nativeRejectionRecorded = false;

    Future<void> rejectRevokedAuthorization(
      Object error,
      StackTrace stack, {
      required bool prepared,
    }) async {
      // No Commit has been entered. If native preparation happened, revoke
      // that exact request and require its nonexecution certificate before
      // recording a definite rejection. Never clear an uncertain operation.
      if (prepared) {
        final cancelled = await recovery.cancelPaymentOperation(
          recoveryRequest,
        );
        if (cancelled.phase != WalletPaymentRecoveryPhase.rejected ||
            cancelled.endAuthorized) {
          _unresolved(
            const StoredDataCorruptionException(),
            StackTrace.current,
          );
        }
      }
      await _write(intent, profile, WalletPaymentSubmissionPhase.rejected);
      final rejected = await _read(profile);
      if (rejected?.id != intent.id ||
          rejected?.phase != WalletPaymentSubmissionPhase.rejected) {
        throw const StoredDataCorruptionException();
      }
      _unconfirmedAttempt = null;
      nativeRejectionRecorded = true;
      Error.throwWithStackTrace(error, stack);
    }

    Future<void>? requireAuthorization({bool prepared = false}) {
      try {
        assertAuthorized?.call();
        return null;
      } catch (error, stack) {
        return rejectRevokedAuthorization(error, stack, prepared: prepared);
      }
    }

    try {
      final initialRevocation = requireAuthorization();
      if (initialRevocation != null) await initialRevocation;
      final prepared = await recovery.preparePaymentOperation(recoveryRequest);
      if (prepared.phase == WalletPaymentRecoveryPhase.rejected &&
          !prepared.endAuthorized) {
        _unconfirmedAttempt = _updated(
          intent,
          phase: WalletPaymentSubmissionPhase.rejected,
        ).withUncertainAcknowledgement();
        await _write(intent, profile, WalletPaymentSubmissionPhase.rejected);
        final rejected = await _read(profile);
        if (rejected?.id != intent.id ||
            rejected?.phase != WalletPaymentSubmissionPhase.rejected) {
          throw const StoredDataCorruptionException();
        }
        _unconfirmedAttempt = null;
        nativeRejectionRecorded = true;
        throw AppFailureException(_rejectionFailure(prepared.failureCode));
      }
      if (prepared.phase == WalletPaymentRecoveryPhase.accepted) {
        // Idempotent native replay returns its existing exact receipt.
        result = _recoveryReceipt(command, prepared);
      } else {
        if (prepared.phase != WalletPaymentRecoveryPhase.prepared ||
            prepared.endAuthorized) {
          _unresolved(
            const StoredDataCorruptionException(),
            StackTrace.current,
          );
        }
        _recoveryReceipt(command, prepared); // Validate pre-dispatch identity.
        final preparedRevocation = requireAuthorization(prepared: true);
        if (preparedRevocation != null) await preparedRevocation;
        // The app's durable boundary must precede native release authorization.
        // If this write fails, Commit is never called and this process retains
        // definite non-submission. A lost acknowledgement after restart is
        // conservatively resolved against the native operation, never guessed.
        final committing = _updated(intent, commitAttempted: true);
        await _write(
          committing,
          profile,
          WalletPaymentSubmissionPhase.submitting,
        );
        intent = committing;
        _unconfirmedAttempt = intent;
        final commitRevocation = requireAuthorization(prepared: true);
        if (commitRevocation != null) await commitRevocation;
        final commitStatus = await _commitWithInspection(
          recovery,
          recoveryRequest,
        );
        if (commitStatus.phase == WalletPaymentRecoveryPhase.rejected &&
            !commitStatus.endAuthorized) {
          _unconfirmedAttempt = _updated(
            intent,
            phase: WalletPaymentSubmissionPhase.rejected,
          ).withUncertainAcknowledgement();
          await _write(intent, profile, WalletPaymentSubmissionPhase.rejected);
          final rejected = await _read(profile);
          if (rejected?.id != intent.id ||
              rejected?.phase != WalletPaymentSubmissionPhase.rejected) {
            throw const StoredDataCorruptionException();
          }
          _unconfirmedAttempt = null;
          nativeRejectionRecorded = true;
          throw AppFailureException(
            _rejectionFailure(commitStatus.failureCode),
          );
        }
        if (commitStatus.phase == WalletPaymentRecoveryPhase.prepared &&
            !commitStatus.endAuthorized &&
            commitStatus.failureCode == 'invoice_expired') {
          _unconfirmedAttempt = _updated(intent, commitAttempted: false);
          // The invoice can expire after preparation. Only a durable native
          // revocation certificate proves that this exact payment cannot be
          // released later; the expiry response alone is not enough.
          final cancelled = await recovery.cancelPaymentOperation(
            recoveryRequest,
          );
          if (cancelled.phase != WalletPaymentRecoveryPhase.rejected ||
              cancelled.endAuthorized) {
            _unconfirmedAttempt = intent;
            _unresolved(
              const StoredDataCorruptionException(),
              StackTrace.current,
            );
          }
          await _write(intent, profile, WalletPaymentSubmissionPhase.rejected);
          final rejected = await _read(profile);
          if (rejected?.id != intent.id ||
              rejected?.phase != WalletPaymentSubmissionPhase.rejected) {
            throw const StoredDataCorruptionException();
          }
          _unconfirmedAttempt = null;
          nativeRejectionRecorded = true;
          throw const AppFailureException(
            AppFailure(
              code: 'payment_request_expired',
              kind: AppFailureKind.validation,
              userMessage:
                  'This invoice has expired. Enter a new invoice to continue.',
              retryable: false,
            ),
          );
        }
        final committed = _recoveryReceipt(
          command,
          commitStatus,
          requireAccepted: true,
        );
        if (committed.referenceId != prepared.referenceId) {
          throw const AppFailureException(
            AppFailure(
              code: 'payment_native_identity_changed',
              kind: AppFailureKind.storage,
              userMessage: 'Wallet recovery is required.',
              retryable: false,
              requiresReconciliation: true,
            ),
          );
        }
        result = committed;
      }
    } catch (error, stack) {
      if (nativeRejectionRecorded) Error.throwWithStackTrace(error, stack);
      if (error is AppFailureException &&
          error.failure.requiresReconciliation &&
          !error.failure.outcomeUnknown) {
        // The engine owns a stronger retained-resource quarantine. Preserve
        // that known failure, while the durable send marker still prevents a
        // replay after restart. This is not a proven payment rejection.
        Error.throwWithStackTrace(error, stack);
      }
      // Error categories are not nonexecution certificates: an error may be
      // delivered after the native operation has already released a payment.
      _unresolved(error, stack);
    }
    if (result.route != command.route ||
        result.amount != command.amount ||
        !_isValidNativeReceipt(result) ||
        (result.status != WalletPaymentStatus.pending &&
            result.status != WalletPaymentStatus.succeeded)) {
      _unresolved(const StoredDataCorruptionException(), StackTrace.current);
    }
    final acceptedEvidence = _updated(
      intent,
      phase: WalletPaymentSubmissionPhase.accepted,
      result: result,
    );
    _unconfirmedAttempt = acceptedEvidence.withUncertainAcknowledgement();
    try {
      // Native acceptance is already durable. Required app receipt persistence
      // is a separate storage responsibility, never a reason to claim that a
      // known accepted payment has become unknown or failed.
      await _write(
        intent,
        profile,
        WalletPaymentSubmissionPhase.accepted,
        result: result,
      );
      // The accepted journal remains the recovery source if the immutable
      // archive commit loses its acknowledgement. Never return success first.
      final accepted = await _read(profile);
      if (accepted?.id != intent.id || accepted?.result != result) {
        throw const StoredDataCorruptionException();
      }
    } catch (error, stack) {
      final failure = acceptedEvidence.reconciliationFailure;
      runtime.retainPaymentSubmissionFence(
        AppFailure(
          code: failure.code,
          kind: failure.kind,
          userMessage: failure.userMessage,
          retryable: false,
          requiresReconciliation: true,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stack,
        ),
      );
      // Presentation can truthfully show the accepted receipt. Further wallet
      // mutations remain fenced until the same receipt is durably repaired.
      return result;
    }
    _unconfirmedAttempt = null;
    return result;
  }

  Future<WalletPaymentSubmission?> _read(
    WalletProfile profile, {
    bool archiveAccepted = true,
  }) async {
    final encoded = await store!.read(profile.id);
    if (encoded == null) return null;
    final value = _decode(encoded, profile);
    if (archiveAccepted &&
        value.phase == WalletPaymentSubmissionPhase.accepted) {
      await _archive(value, profile);
    }
    return value;
  }

  Future<void> _archive(
    WalletPaymentSubmission receipt,
    WalletProfile profile,
  ) async {
    if (receipts == null) {
      throw const AppFailureException(
        AppFailure(
          code: 'payment_receipt_storage_unavailable',
          kind: AppFailureKind.configuration,
          userMessage: 'Payment receipt storage is unavailable.',
          retryable: false,
        ),
      );
    }
    await receipts!.writeReceipt(
      profile.id,
      _receiptKey(profile, receipt.result!),
      _encode(receipt, profile),
    );
  }

  Future<List<WalletPaymentSubmission>> _archived(WalletProfile profile) async {
    if (receipts == null) return const [];
    final documents = await receipts!.readAll(profile.id);
    return documents.entries
        .map((entry) {
          final receipt = _decode(entry.value, profile);
          if (receipt.phase != WalletPaymentSubmissionPhase.accepted ||
              _receiptKey(profile, receipt.result!) != entry.key) {
            throw const StoredDataCorruptionException();
          }
          return receipt;
        })
        .toList(growable: false);
  }

  static String _receiptKey(WalletProfile profile, WalletSendResult result) =>
      _identityKey(
        profile,
        result.route.asset,
        result.referenceId,
        result.batchTransferIndex,
      );

  static String _identityKey(
    WalletProfile profile,
    WalletAsset asset,
    String txid,
    int? batchTransferIndex,
  ) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            profile.storageToken,
            profile.environment.name,
            asset.id.value,
            asset.precision,
            txid,
            batchTransferIndex,
          ]),
        ),
      )
      .toString();

  static bool _matchesIdentity(
    WalletActivity activity,
    WalletSendResult result,
  ) {
    if (activity.asset != result.route.asset ||
        activity.rail != PaymentRail.onchain ||
        activity.txid != result.referenceId ||
        activity.status == WalletActivityStatus.failed ||
        activity.status == WalletActivityStatus.cancelled ||
        activity.status == WalletActivityStatus.expired) {
      return false;
    }
    return result.route.asset.kind == WalletAssetKind.bitcoin
        ? activity.source == WalletActivitySource.bitcoinTransaction &&
              (activity.operation == WalletActivityOperation.bitcoinSend ||
                  activity.operation ==
                      WalletActivityOperation.bitcoinSelfTransfer) &&
              result.batchTransferIndex == null &&
              (activity.status == WalletActivityStatus.pending ||
                  activity.status == WalletActivityStatus.succeeded)
        : activity.source == WalletActivitySource.rgbTransfer &&
              activity.operation == WalletActivityOperation.rgbSend &&
              result.batchTransferIndex != null &&
              activity.batchTransferIndex == result.batchTransferIndex;
  }

  /// A thrown or returned unknown Commit outcome is inspected once in Send.
  /// This only reads the exact saved native operation; it never repeats Prepare,
  /// Commit, proxy upload, broadcast or cancellation. If inspection is blocked
  /// by the engine's lifecycle or cannot establish an outcome, preserve the
  /// original error and the mutation fence.
  Future<WalletPaymentRecoveryStatus> _commitWithInspection(
    WalletPaymentRecoveryEngine recovery,
    String request,
  ) async {
    final WalletPaymentRecoveryStatus committed;
    try {
      committed = await recovery.commitPaymentOperation(request);
    } catch (error, stack) {
      try {
        final status = await recovery.inspectPaymentOperation(request);
        if (status.phase == WalletPaymentRecoveryPhase.accepted ||
            (status.phase == WalletPaymentRecoveryPhase.rejected &&
                !status.endAuthorized)) {
          return status;
        }
        if (_unconfirmedAttempt case final attempt?
            when !status.endAuthorized) {
          _unconfirmedAttempt = _updated(attempt, commitAttempted: false);
        }
      } catch (_) {
        // Failure to inspect is not evidence of payment failure or permission
        // to dispatch again. The original error remains the diagnostic cause.
      }
      Error.throwWithStackTrace(error, stack);
    }
    if (committed.phase != WalletPaymentRecoveryPhase.committing) {
      return committed;
    }
    // Native may return a durable unknown status instead of throwing after a
    // lost external reply. Observe that same operation once in this Send action;
    // unavailable/partial evidence cannot authorize another financial call or
    // downgrade the original Committing fence.
    try {
      final status = await recovery.inspectPaymentOperation(request);
      if (status.phase == WalletPaymentRecoveryPhase.accepted ||
          (status.phase == WalletPaymentRecoveryPhase.rejected &&
              !status.endAuthorized)) {
        return status;
      }
    } catch (_) {
      // The original native status remains authoritative when observation fails.
    }
    return committed;
  }

  static WalletPaymentSubmission _updated(
    WalletPaymentSubmission original, {
    WalletPaymentSubmissionPhase? phase,
    WalletSendResult? result,
    bool? commitAttempted,
  }) => WalletPaymentSubmission(
    id: original.id,
    walletId: original.walletId,
    command: original.command,
    submittedAt: original.submittedAt,
    phase: phase ?? original.phase,
    result: result,
    recoveryRequest: original.recoveryRequest,
    commitAttempted: commitAttempted ?? original.commitAttempted,
    journalVersion: original.journalVersion,
    nativeDiscovered: original.nativeDiscovered,
  );

  /// Only called after a matching permanent native rejection certificate. Raw
  /// native errors never reach user copy and never establish nonexecution.
  static AppFailure _rejectionFailure(String? code) {
    final (kind, message) = switch (code) {
      'insufficient_bitcoins' => (
        AppFailureKind.validation,
        'Not enough Bitcoin to cover this payment and the network fee.',
      ),
      'insufficient_asset_balance' => (
        AppFailureKind.validation,
        'Not enough funds to send this amount.',
      ),
      'insufficient_allocations' => (
        AppFailureKind.unavailable,
        'Prepare the wallet before sending this asset.',
      ),
      'invalid_recipient' => (
        AppFailureKind.validation,
        'Check the recipient and try again.',
      ),
      'invoice_expired' => (
        AppFailureKind.validation,
        'This invoice has expired. Enter a new invoice to continue.',
      ),
      'invalid_amount' => (AppFailureKind.validation, 'Enter a valid amount.'),
      'invalid_fee' => (
        AppFailureKind.validation,
        'Review the network fee and try again.',
      ),
      'network_unavailable' => (
        AppFailureKind.connectivity,
        'Could not connect. Nothing was sent. Try again.',
      ),
      'invalid_configuration' => (
        AppFailureKind.configuration,
        'Sending is unavailable with the current network settings.',
      ),
      'storage_unavailable' => (
        AppFailureKind.storage,
        'The payment could not be saved. Nothing was sent.',
      ),
      _ => (
        AppFailureKind.unavailable,
        'The payment was not sent. Review the details and try again.',
      ),
    };
    return AppFailure(
      code: code == 'invoice_expired'
          ? 'payment_request_expired'
          : 'payment_not_dispatched',
      kind: kind,
      userMessage: message,
      retryable: const {
        'network_unavailable',
        'storage_unavailable',
        'insufficient_allocations',
        'insufficient_bitcoins',
        'insufficient_asset_balance',
      }.contains(code),
    );
  }

  Future<void> _write(
    WalletPaymentSubmission intent,
    WalletProfile profile,
    WalletPaymentSubmissionPhase phase, {
    WalletSendResult? result,
  }) => store!.write(
    profile.id,
    _encode(
      WalletPaymentSubmission(
        id: intent.id,
        walletId: intent.walletId,
        command: intent.command,
        submittedAt: intent.submittedAt,
        phase: phase,
        result: result,
        recoveryRequest: intent.recoveryRequest,
        commitAttempted: intent.commitAttempted,
        journalVersion: intent.journalVersion,
        nativeDiscovered: intent.nativeDiscovered,
      ),
      profile,
    ),
  );

  Never _unresolved(Object error, StackTrace stack) {
    final failure =
        _unconfirmedAttempt?.reconciliationFailure ??
        walletPaymentSubmissionPendingFailure;
    return Error.throwWithStackTrace(
      AppFailureException(
        AppFailure(
          code: failure.code,
          kind: failure.kind,
          userMessage: failure.userMessage,
          retryable: false,
          requiresReconciliation: true,
          outcomeUnknown: failure.outcomeUnknown,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stack,
        ),
      ),
      stack,
    );
  }

  /// An uncertain app-journal acknowledgement retains the payment fence, not a
  /// native-owner quarantine. A later explicit Check can finish the same write.
  /// Native operation failures and corrupt records are deliberately not caught.
  Future<T> _recoverJournalAcknowledgement<T>(
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on DurableStorageCommitException catch (error, stack) {
      _unresolved(error, stack);
    }
  }

  static bool _isValidNativeReceipt(WalletSendResult result) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(result.referenceId) &&
      (result.route.asset.kind == WalletAssetKind.bitcoin
          ? result.batchTransferIndex == null
          : result.batchTransferIndex != null);

  static WalletSendResult _recoveryReceipt(
    WalletSendCommand command,
    WalletPaymentRecoveryStatus status, {
    bool requireAccepted = false,
  }) {
    if ((requireAccepted &&
            status.phase != WalletPaymentRecoveryPhase.accepted) ||
        (status.phase != WalletPaymentRecoveryPhase.accepted &&
            status.phase != WalletPaymentRecoveryPhase.prepared) ||
        (status.phase == WalletPaymentRecoveryPhase.accepted &&
            !status.endAuthorized)) {
      throw const StoredDataCorruptionException();
    }
    final receipt = WalletSendResult(
      route: command.route,
      amount: command.amount,
      referenceId: status.referenceId ?? '',
      batchTransferIndex: status.batchTransferIndex,
      status: WalletPaymentStatus.pending,
    );
    if (!_isValidNativeReceipt(receipt)) {
      throw const StoredDataCorruptionException();
    }
    return receipt;
  }

  static String _encode(WalletPaymentSubmission value, WalletProfile profile) {
    final command = value.command;
    final fee = command.feeRate!;
    final result = value.result;
    return jsonEncode({
      'version': value.recoveryRequest == null ? 1 : value.journalVersion,
      if (value.nativeDiscovered) 'nativeDiscovered': true,
      if (value.recoveryRequest != null && value.journalVersion >= 3)
        'commitAttempted': value.commitAttempted,
      if (value.recoveryRequest != null)
        'recoveryRequest': value.recoveryRequest,
      'id': value.id,
      'walletId': value.walletId,
      'storageToken': profile.storageToken,
      'network': profile.environment.name,
      'submittedAt': value.submittedAt.toIso8601String(),
      'phase': value.phase.name,
      'command': {
        'asset': command.route.asset.id.value,
        'precision': command.route.asset.precision,
        'destination': command.destination,
        'amount': command.amount.units,
        'feeTarget': fee.targetBlocks,
        'feeRate': fee.satsPerVbyte,
        'feeObservedAt': fee.observedAt.toIso8601String(),
        'feeSource': fee.source.name,
        'rgbRecipientType': command.rgbRecipientType?.name,
        'witnessBitcoinAmountSats': command.witnessBitcoinAmountSats,
      },
      'result': result == null
          ? null
          : {
              'referenceId': result.referenceId,
              'status': result.status.name,
              'batchTransferIndex': result.batchTransferIndex,
            },
    });
  }

  static WalletPaymentSubmission _decode(
    String encoded,
    WalletProfile profile,
  ) {
    try {
      if (encoded.length > 400000) throw const FormatException();
      final value = jsonDecode(encoded);
      final version = value is Map<String, Object?> ? value['version'] : null;
      if (value is! Map<String, Object?> ||
          !_hasKeys(value, {
            'version',
            'id',
            'walletId',
            'storageToken',
            'network',
            'submittedAt',
            'phase',
            'command',
            'result',
            if (version == 2 || version == 3 || version == 4) 'recoveryRequest',
            if (version == 3 || version == 4) 'commitAttempted',
            if (version == 4) 'nativeDiscovered',
          }) ||
          (version != 1 && version != 2 && version != 3 && version != 4) ||
          ((version == 3 || version == 4) &&
              value['commitAttempted'] is! bool) ||
          (version == 4 && value['nativeDiscovered'] != true) ||
          ((version == 2 || version == 3 || version == 4) &&
              (value['recoveryRequest'] is! String ||
                  (value['recoveryRequest']! as String).isEmpty ||
                  (value['recoveryRequest']! as String).length > 100000)) ||
          value['walletId'] != profile.id ||
          value['storageToken'] != profile.storageToken ||
          value['network'] != profile.environment.name ||
          value['id'] is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['id']! as String) ||
          value['phase'] is! String ||
          value['command'] is! Map<String, Object?>) {
        throw const FormatException();
      }
      final phase = WalletPaymentSubmissionPhase.values.byName(
        value['phase']! as String,
      );
      final data = value['command']! as Map<String, Object?>;
      if (!_hasKeys(data, {
            'asset',
            'precision',
            'destination',
            'amount',
            'feeTarget',
            'feeRate',
            'feeObservedAt',
            'feeSource',
            'rgbRecipientType',
            'witnessBitcoinAmountSats',
          }) ||
          data['asset'] is! String ||
          data['precision'] is! int ||
          data['destination'] is! String ||
          data['amount'] is! int ||
          (version == 4
              ? data['feeTarget'] != null
              : data['feeTarget'] is! int) ||
          data['feeRate'] is! int ||
          data['feeSource'] is! String ||
          (data['rgbRecipientType'] != null &&
              data['rgbRecipientType'] is! String) ||
          (data['witnessBitcoinAmountSats'] != null &&
              data['witnessBitcoinAmountSats'] is! int)) {
        throw const FormatException();
      }
      final asset = data['asset'] == WalletAsset.bitcoin.id.value
          ? WalletAsset.bitcoin
          : WalletAsset.rgbUsdt(
              assetId: data['asset']! as String,
              precision: data['precision']! as int,
            );
      if (asset.precision != data['precision']) throw const FormatException();
      final route = PaymentRoute(asset: asset, rail: PaymentRail.onchain);
      final fee = WalletFeeRateEstimate(
        targetBlocks: data['feeTarget'] as int?,
        satsPerVbyte: data['feeRate']! as int,
        observedAt: _utcDate(data['feeObservedAt']),
        source: WalletFeeRateSource.values.byName(data['feeSource']! as String),
      );
      if ((version == 4) !=
          (fee.source == WalletFeeRateSource.nativeRecovery)) {
        throw const FormatException();
      }
      if (fee.source == WalletFeeRateSource.localRegtestPolicy &&
          profile.environment != BlockchainEnvironment.regtest) {
        throw const FormatException();
      }
      final command = WalletSendCommand(
        route: route,
        destination: data['destination']! as String,
        amount: WalletAmount.onchain(
          assetId: asset.id,
          units: data['amount']! as int,
        ),
        feeRate: fee,
        rgbRecipientType: data['rgbRecipientType'] == null
            ? null
            : RgbRecipientType.values.byName(
                data['rgbRecipientType']! as String,
              ),
        witnessBitcoinAmountSats: data['witnessBitcoinAmountSats'] as int?,
      );
      final rawResult = value['result'];
      WalletSendResult? result;
      if (rawResult != null) {
        if (rawResult is! Map<String, Object?> ||
            !_hasKeys(rawResult, {
              'referenceId',
              'status',
              'batchTransferIndex',
            }) ||
            rawResult['referenceId'] is! String ||
            rawResult['status'] is! String ||
            (rawResult['batchTransferIndex'] != null &&
                rawResult['batchTransferIndex'] is! int)) {
          throw const FormatException();
        }
        result = WalletSendResult(
          route: route,
          amount: command.amount,
          referenceId: rawResult['referenceId']! as String,
          status: WalletPaymentStatus.values.byName(
            rawResult['status']! as String,
          ),
          batchTransferIndex: rawResult['batchTransferIndex'] as int?,
        );
      }
      if ((phase == WalletPaymentSubmissionPhase.accepted) !=
              (result != null) ||
          (result != null &&
              (!_isValidNativeReceipt(result) ||
                  (result.status != WalletPaymentStatus.pending &&
                      result.status != WalletPaymentStatus.succeeded)))) {
        throw const FormatException();
      }
      return WalletPaymentSubmission(
        id: value['id']! as String,
        walletId: profile.id,
        command: command,
        submittedAt: _utcDate(value['submittedAt']),
        phase: phase,
        result: result,
        recoveryRequest: value['recoveryRequest'] as String?,
        commitAttempted: version == 3 || version == 4
            ? value['commitAttempted']! as bool
            : true,
        journalVersion: version! as int,
        nativeDiscovered: version == 4,
      );
    } catch (_) {
      throw const StoredDataCorruptionException();
    }
  }

  static bool _hasKeys(Map<String, Object?> value, Set<String> keys) =>
      value.length == keys.length && value.keys.every(keys.contains);

  static DateTime _utcDate(Object? value) {
    if (value is! String) throw const FormatException();
    final parsed = DateTime.parse(value);
    if (!parsed.isUtc) throw const FormatException();
    return parsed;
  }
}
