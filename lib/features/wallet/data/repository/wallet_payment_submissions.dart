import 'dart:convert';

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
    required this.newId,
    required this.clock,
  });

  final WalletRuntime runtime;
  final WalletPaymentJournalStore? store;
  final String Function() newId;
  final DateTime Function() clock;
  WalletPaymentSubmission? _unconfirmedAttempt;

  Future<void> validateProfiles(Iterable<WalletProfile> profiles) async {
    if (store == null) return;
    for (final profile in profiles) {
      await _read(profile);
    }
  }

  /// Reapply the durable mutation fence after native startup, keeping the
  /// existing wallet readable. Corrupt records fail application bootstrap.
  Future<void> restoreFence() async {
    final profile = runtime.activeProfile;
    if (profile == null || store == null) return;
    final record = await _read(profile);
    if (record?.requiresReconciliation == true) {
      _unconfirmedAttempt = record;
      await runtime.retainUnresolvedPayment();
    }
  }

  Future<AppResult<void>> assertResolved() async {
    try {
      // A durable acknowledgement written just before an I/O error still
      // requires explicit exact-history reconciliation in this process.
      if (runtime.snapshot.failure?.code ==
          walletPaymentSubmissionPendingFailure.code) {
        return const AppResult.failure(walletPaymentSubmissionPendingFailure);
      }
      final profile = runtime.activeProfile;
      if (profile == null || store == null) {
        return const AppResult.success(null);
      }
      final record = await _read(profile);
      if (record?.requiresReconciliation == true) {
        return const AppResult.failure(walletPaymentSubmissionPendingFailure);
      }
      return const AppResult.success(null);
    } catch (error, stack) {
      return AppResult.failure(FailureMapper.from(error, stack));
    }
  }

  Future<AppResult<WalletPaymentSubmission?>> status() async {
    try {
      final profile = runtime.activeProfile;
      var record = profile == null || store == null
          ? null
          : await _read(profile);
      final attempt = _unconfirmedAttempt;
      if (attempt != null &&
          attempt.walletId == profile?.id &&
          runtime.snapshot.failure?.code ==
              walletPaymentSubmissionPendingFailure.code &&
          record?.id != attempt.id) {
        record = attempt;
      }
      return AppResult.success(
        record != null &&
                runtime.snapshot.failure?.code ==
                    walletPaymentSubmissionPendingFailure.code
            ? record.withUncertainAcknowledgement()
            : record,
      );
    } catch (error, stack) {
      return AppResult.failure(FailureMapper.from(error, stack));
    }
  }

  /// An exact durably recorded native response can resolve a lost journal
  /// acknowledgement. An unidentifiable submission remains unresolved forever
  /// until a separate authoritative native recovery protocol is available.
  Future<AppResult<void>> reconcile() => runtime.reconcilePaymentSubmission((
    engine,
  ) async {
    final profile = runtime.activeProfile;
    if (profile == null || store == null) return false;
    final record = await _read(profile);
    final result = record?.result;
    if (record?.phase != WalletPaymentSubmissionPhase.accepted ||
        result == null ||
        record?.id != _unconfirmedAttempt?.id) {
      return false;
    }
    final matches = (await engine.listActivity(result.route.asset)).where(
      (activity) =>
          activity.asset == result.route.asset &&
          activity.rail == PaymentRail.onchain &&
          activity.direction == WalletActivityDirection.sent &&
          activity.amount == result.amount &&
          activity.txid == result.referenceId &&
          (result.route.asset.kind == WalletAssetKind.bitcoin
              ? activity.source == WalletActivitySource.bitcoinTransaction &&
                    activity.operation == WalletActivityOperation.bitcoinSend &&
                    result.batchTransferIndex == null
              : activity.source == WalletActivitySource.rgbTransfer &&
                    activity.operation == WalletActivityOperation.rgbSend &&
                    result.batchTransferIndex != null &&
                    activity.batchTransferIndex == result.batchTransferIndex) &&
          activity.status != WalletActivityStatus.failed &&
          activity.status != WalletActivityStatus.cancelled &&
          activity.status != WalletActivityStatus.expired,
    );
    return matches.length == 1;
  });

  Future<WalletSendResult> dispatch(
    WalletEngine engine,
    WalletSendCommand command,
  ) async {
    final profile = runtime.activeProfile;
    if (store == null || profile == null) {
      throw const AppFailureException(
        AppFailure(
          code: 'payment_journal_unavailable',
          kind: AppFailureKind.configuration,
          userMessage: 'Payment submission storage is unavailable.',
          retryable: false,
        ),
      );
    }
    final previous = await _read(profile);
    if (previous?.requiresReconciliation == true) {
      throw const AppFailureException(walletPaymentSubmissionPendingFailure);
    }
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
    final intent = WalletPaymentSubmission(
      id: id,
      walletId: profile.id,
      command: command,
      submittedAt: clock().toUtc(),
      phase: WalletPaymentSubmissionPhase.submitting,
    );
    // Validate the same strict representation that must survive a restart.
    final encoded = _encode(intent, profile);
    _decode(encoded, profile);
    _unconfirmedAttempt = intent;
    try {
      await store!.write(profile.id, encoded);
    } catch (error, stack) {
      // The write may be durable despite an error. Native was not called, but
      // this marker must never be overwritten by a new submission attempt.
      _unresolved(error, stack);
    }

    final WalletSendResult result;
    try {
      result = await engine.sendPayment(command);
    } catch (error, stack) {
      if (error is AppFailureException &&
          error.failure.requiresReconciliation &&
          !error.failure.outcomeUnknown) {
        // The engine owns a stronger retained-resource quarantine. Preserve
        // that known failure, while the durable send marker still prevents a
        // replay after restart. This is not a proven payment rejection.
        Error.throwWithStackTrace(error, stack);
      }
      if (_isConfirmedPreDispatchRejection(error)) {
        // Only documented local validation failures prove no native mutation.
        // Persist that fact before allowing a new user-reviewed submission.
        try {
          await _write(intent, profile, WalletPaymentSubmissionPhase.rejected);
          _unconfirmedAttempt = null;
        } catch (storageError, storageStack) {
          _unresolved(storageError, storageStack);
        }
        Error.throwWithStackTrace(error, stack);
      }
      _unresolved(error, stack);
    }
    if (result.route != command.route ||
        result.amount != command.amount ||
        !_isValidNativeReceipt(result) ||
        (result.status != WalletPaymentStatus.pending &&
            result.status != WalletPaymentStatus.succeeded)) {
      _unresolved(const StoredDataCorruptionException(), StackTrace.current);
    }
    try {
      // No success reaches presentation before its exact native acceptance is
      // durable. A lost response after this commit is recoverable by identity.
      await _write(
        intent,
        profile,
        WalletPaymentSubmissionPhase.accepted,
        result: result,
      );
    } catch (error, stack) {
      _unresolved(error, stack);
    }
    _unconfirmedAttempt = null;
    return result;
  }

  Future<WalletPaymentSubmission?> _read(WalletProfile profile) async {
    final encoded = await store!.read(profile.id);
    return encoded == null ? null : _decode(encoded, profile);
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
      ),
      profile,
    ),
  );

  static Never _unresolved(Object error, StackTrace stack) =>
      Error.throwWithStackTrace(
        AppFailureException(
          AppFailure(
            code: walletPaymentSubmissionPendingFailure.code,
            kind: walletPaymentSubmissionPendingFailure.kind,
            userMessage: walletPaymentSubmissionPendingFailure.userMessage,
            retryable: false,
            outcomeUnknown: true,
            cause: FailureMapper.diagnosticCause(error),
            stackTrace: stack,
          ),
        ),
        stack,
      );

  static bool _isValidNativeReceipt(WalletSendResult result) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(result.referenceId) &&
      (result.route.asset.kind == WalletAssetKind.bitcoin
          ? result.batchTransferIndex == null
          : result.batchTransferIndex != null);

  static bool _isConfirmedPreDispatchRejection(Object error) =>
      (error is WalletPaymentRejectedBeforeDispatchException &&
          !error.failure.requiresReconciliation &&
          !error.failure.outcomeUnknown) ||
      (error is AppFailureException &&
          (error.failure == walletFeeReviewRequiredFailure ||
              error.failure == walletFeeReviewChangedFailure));

  static String _encode(WalletPaymentSubmission value, WalletProfile profile) {
    final command = value.command;
    final fee = command.feeRate!;
    final result = value.result;
    return jsonEncode({
      'version': 1,
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
          }) ||
          value['version'] != 1 ||
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
          data['feeTarget'] is! int ||
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
        targetBlocks: data['feeTarget']! as int,
        satsPerVbyte: data['feeRate']! as int,
        observedAt: _utcDate(data['feeObservedAt']),
        source: WalletFeeRateSource.values.byName(data['feeSource']! as String),
      );
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
