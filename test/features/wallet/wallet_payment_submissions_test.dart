import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:aster/features/wallet/data/repository/repository.dart';
import 'package:aster/features/wallet/data/runtime/runtime.dart';
import 'package:aster/features/wallet/data/storage/storage.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart'
    show RecoverableSendStorageException, RlnOperationTimeoutException;

import '../../support/wallet_fakes.dart';

part 'wallet_payment_expiry_cases.dart';
part 'wallet_payment_marker_recovery_cases.dart';

const _id = '11111111111111111111111111111111';
const _storageToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _destination = 'mipcBbFg9gMiCh81Kj8tqqdgoZub1ZJRfn';
const _services = WalletServiceConfiguration(
  environment: BlockchainEnvironment.regtest,
  sdkNetwork: 'regtest',
  usdtAsset: RgbAssetConfiguration(
    contractId: 'rgb:configured-usdt',
    precision: 6,
    requiresEvmValidation: false,
  ),
);
final _now = DateTime.utc(2026, 10, 16);
final _txid = 'b' * 64;

void main() {
  group('native operation recovery v3', () {
    _expiryRecoveryCases();
    _markerRecoveryCases();
    test('request preflight deadline restores the owner without creating a phantom payment or retry', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine
        ..paymentOperationRequestError = const RlnOperationTimeoutException(
          operation: 'nodeInfo',
          timeout: Duration(seconds: 120),
        )
        ..paymentOperationRequestRequiresReopen = true;
      final result = await h.send() as AppFailureResult<WalletSendResult>;
      expect(result.failure.outcomeUnknown, isFalse);
      expect(result.failure.requiresReconciliation, isFalse);
      expect(result.failure.code, 'payment_not_dispatched');
      expect(h.store.writes, isEmpty);
      expect(h.paymentOperations.operationCount, 0);
      expect(h.paymentOperations.dispatchCount, 0);
      expect(
        h.engine.calls.where((call) => call == 'paymentOperationRequest'),
        hasLength(1),
      );
      expect(
        h.engine.calls,
        containsAllInOrder(['paymentOperationRequest', 'openPersisted']),
      );
      expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
      expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
      expect(
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value,
        isNull,
      );
    });

    test('failed owner recovery after preflight timeout keeps a stronger owner quarantine without payment dispatch', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine
        ..paymentOperationRequestError = const RlnOperationTimeoutException(
          operation: 'nodeInfo',
          timeout: Duration(seconds: 120),
        )
        ..paymentOperationRequestRequiresReopen = true
        ..openPersistedError = StateError('Owner reopen unavailable');
      final result = await h.send() as AppFailureResult<WalletSendResult>;
      expect(result.failure.requiresReconciliation, isTrue);
      expect(h.store.writes, isEmpty);
      expect(h.paymentOperations.operationCount, 0);
      expect(h.paymentOperations.dispatchCount, 0);
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
      expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
      expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
    });

    test('marker failure is definitely not submitted even when rejection cannot be saved', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store.failWriteNumbers.addAll([1, 2]);
      final result = await h.send() as AppFailureResult<WalletSendResult>;
      expect(result.failure.code, 'payment_not_sent_cleanup_required');
      expect(result.failure.outcomeUnknown, isFalse);
      expect(result.failure.requiresReconciliation, isTrue);
      final record =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(record.outcome, WalletPaymentSubmissionOutcome.notSubmitted);
      expect(record.requiresReconciliation, isTrue);
      expect(h.paymentOperations.operationCount, 0);
      expect(h.paymentOperations.dispatchCount, 0);
    });

    test(
      'lost Prepare reply remains known not submitted before and after restart',
      () async {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.engine.preparePaymentOperationError = StateError(
          'Lost prepare reply',
        );
        final result = await h.send() as AppFailureResult<WalletSendResult>;
        expect(result.failure.code, 'payment_not_sent_cleanup_required');
        expect(result.failure.outcomeUnknown, isFalse);
        expect(
          (jsonDecode(h.store.documents[_id]!) as Map)['commitAttempted'],
          isFalse,
        );
        await h.restart();
        final record =
            (await h.repository.paymentSubmissionStatus()
                    as AppSuccess<WalletPaymentSubmission?>)
                .value!;
        expect(record.outcome, WalletPaymentSubmissionOutcome.notSubmitted);
        expect(h.runtime.snapshot.failure?.outcomeUnknown, isFalse);
        expect(h.paymentOperations.dispatchCount, 0);
      },
    );

    test('Commit boundary storage failure never enters Commit and retains precise live certainty', () async {
      for (final committed in [false, true]) {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.store.failWriteNumber = 2;
        h.store.commitBeforeError = committed;
        final result = await h.send() as AppFailureResult<WalletSendResult>;
        expect(result.failure.code, 'payment_not_sent_cleanup_required');
        expect(result.failure.outcomeUnknown, isFalse);
        expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
        expect(h.paymentOperations.dispatchCount, 0);
        final live =
            (await h.repository.paymentSubmissionStatus()
                    as AppSuccess<WalletPaymentSubmission?>)
                .value!;
        expect(live.outcome, WalletPaymentSubmissionOutcome.notSubmitted);
        await h.restart();
        final disk =
            (await h.repository.paymentSubmissionStatus()
                    as AppSuccess<WalletPaymentSubmission?>)
                .value!;
        expect(
          disk.outcome,
          committed
              ? WalletPaymentSubmissionOutcome.unknown
              : WalletPaymentSubmissionOutcome.notSubmitted,
        );
        expect(
          await h.repository.reconcilePaymentSubmission(),
          isA<AppSuccess<void>>(),
        );
        expect(h.paymentOperations.dispatchCount, 0);
      }
    });

    test('lost Commit acknowledgement inspects exactly once and returns known accepted success', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.commitPaymentOperationReplyError = StateError('Lost reply');
      final result = await h.send() as AppSuccess<WalletSendResult>;
      expect(result.value.referenceId, _txid);
      expect(
        h.engine.calls.where((call) => call == 'inspectPaymentOperation'),
        hasLength(1),
      );
      expect(
        h.engine.calls.where((call) => call == 'commitPaymentOperation'),
        hasLength(1),
      );
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expect(h.paymentOperations.dispatchCount, 1);
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    });

    test(
      'returned Committing inspects once and presents exact accepted success',
      () async {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.engine
          ..commitPaymentOperationResult = WalletPaymentRecoveryStatus(
            phase: WalletPaymentRecoveryPhase.committing,
            endAuthorized: true,
            referenceId: _txid,
          )
          ..inspectPaymentOperationResult = WalletPaymentRecoveryStatus(
            phase: WalletPaymentRecoveryPhase.accepted,
            endAuthorized: true,
            referenceId: _txid,
          );
        final result = await h.send() as AppSuccess<WalletSendResult>;
        expect(result.value.referenceId, _txid);
        expect(h.runtime.hasPaymentSubmissionFence, isFalse);
        expect(
          h.engine.calls.where((c) => c == 'preparePaymentOperation'),
          hasLength(1),
        );
        expect(
          h.engine.calls.where((c) => c == 'commitPaymentOperation'),
          hasLength(1),
        );
        expect(
          h.engine.calls.where((c) => c == 'inspectPaymentOperation'),
          hasLength(1),
        );
        expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
        expect(h.engine.legacySendPaymentCalls, 0);
        expect(h.paymentOperations.commitAttemptCount, 1);
        final record =
            (await h.repository.paymentSubmissionStatus()
                    as AppSuccess<WalletPaymentSubmission?>)
                .value!;
        expect(record.phase, WalletPaymentSubmissionPhase.accepted);
        expect(record.result!.referenceId, _txid);
      },
    );

    test(
      'returned Committing accepts only an authoritative permanent rejection',
      () async {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.engine
          ..commitPaymentOperationResult = WalletPaymentRecoveryStatus(
            phase: WalletPaymentRecoveryPhase.committing,
            endAuthorized: true,
            referenceId: _txid,
          )
          ..inspectPaymentOperationResult = const WalletPaymentRecoveryStatus(
            phase: WalletPaymentRecoveryPhase.rejected,
            endAuthorized: false,
            failureCode: 'insufficient_bitcoins',
          );
        final result = await h.send() as AppFailureResult<WalletSendResult>;
        expect(result.failure.code, 'payment_not_dispatched');
        expect(result.failure.outcomeUnknown, isFalse);
        expect(h.runtime.hasPaymentSubmissionFence, isFalse);
        final record =
            (await h.repository.paymentSubmissionStatus()
                    as AppSuccess<WalletPaymentSubmission?>)
                .value!;
        expect(record.phase, WalletPaymentSubmissionPhase.rejected);
        expect(
          h.engine.calls.where((c) => c == 'preparePaymentOperation'),
          hasLength(1),
        );
        expect(
          h.engine.calls.where((c) => c == 'commitPaymentOperation'),
          hasLength(1),
        );
        expect(
          h.engine.calls.where((c) => c == 'inspectPaymentOperation'),
          hasLength(1),
        );
        expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      },
    );

    test('returned Committing preserves its original unknown fence for inconclusive reads', () async {
      for (final phase in [
        WalletPaymentRecoveryPhase.absent,
        WalletPaymentRecoveryPhase.preparing,
        WalletPaymentRecoveryPhase.prepared,
        WalletPaymentRecoveryPhase.committing,
        WalletPaymentRecoveryPhase.rejected,
      ]) {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.engine
          ..commitPaymentOperationResult = WalletPaymentRecoveryStatus(
            phase: WalletPaymentRecoveryPhase.committing,
            endAuthorized: true,
            referenceId: _txid,
          )
          ..inspectPaymentOperationResult = WalletPaymentRecoveryStatus(
            phase: phase,
            endAuthorized:
                phase == WalletPaymentRecoveryPhase.committing ||
                phase == WalletPaymentRecoveryPhase.rejected,
            referenceId: _txid,
          );
        _expectPending(await h.send());
        final record =
            (await h.repository.paymentSubmissionStatus()
                    as AppSuccess<WalletPaymentSubmission?>)
                .value!;
        expect(record.outcome, WalletPaymentSubmissionOutcome.unknown);
        expect(record.commitAttempted, isTrue);
        expect(h.runtime.hasPaymentSubmissionFence, isTrue);
        expect(
          h.engine.calls.where((c) => c == 'preparePaymentOperation'),
          hasLength(1),
        );
        expect(
          h.engine.calls.where((c) => c == 'commitPaymentOperation'),
          hasLength(1),
        );
        expect(
          h.engine.calls.where((c) => c == 'inspectPaymentOperation'),
          hasLength(1),
        );
        expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      }
    });

    test('returned Committing read failure never repeats Commit or clears its fence', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine
        ..commitPaymentOperationResult = WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.committing,
          endAuthorized: true,
          referenceId: _txid,
        )
        ..inspectPaymentOperationError = StateError('Observation unavailable');
      _expectPending(await h.send());
      final record =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(record.outcome, WalletPaymentSubmissionOutcome.unknown);
      expect(record.commitAttempted, isTrue);
      expect(h.runtime.hasPaymentSubmissionFence, isTrue);
      expect(
        h.engine.calls.where((c) => c == 'preparePaymentOperation'),
        hasLength(1),
      );
      expect(
        h.engine.calls.where((c) => c == 'commitPaymentOperation'),
        hasLength(1),
      );
      expect(
        h.engine.calls.where((c) => c == 'inspectPaymentOperation'),
        hasLength(1),
      );
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expect(h.paymentOperations.commitAttemptCount, 1);
    });

    test('exact accepted outcome survives required receipt failure without hiding its mutation fence', () async {
      for (final committed in [false, true]) {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.store.failWriteNumber = 3;
        h.store.commitBeforeError = committed;
        final result = await h.send() as AppSuccess<WalletSendResult>;
        expect(result.value.referenceId, _txid);
        expect(h.runtime.hasPaymentSubmissionFence, isTrue);
        expect(
          h.runtime.snapshot.failure?.code,
          'payment_receipt_persistence_required',
        );
        expect(h.runtime.snapshot.failure?.outcomeUnknown, isFalse);
        final record =
            (await h.repository.paymentSubmissionStatus()
                    as AppSuccess<WalletPaymentSubmission?>)
                .value!;
        expect(record.outcome, WalletPaymentSubmissionOutcome.accepted);
        expect(record.result, result.value);
        expect(record.requiresReconciliation, isTrue);
        _expectPending(await h.send());
        expect(h.paymentOperations.dispatchCount, 1);
        expect(
          await h.repository.reconcilePaymentSubmission(),
          isA<AppSuccess<void>>(),
        );
        expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
      }
    });

    test('accepted journal stays readable across restart while receipt archive is unavailable', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store.receiptWriteError = StateError('Archive unavailable');
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      await h.restart();
      final record =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(record.outcome, WalletPaymentSubmissionOutcome.accepted);
      expect(record.result?.referenceId, _txid);
      expect(record.requiresReconciliation, isTrue);
      expect(h.runtime.snapshot.failure?.outcomeUnknown, isFalse);
      expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
      h.store.receiptWriteError = null;
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    });

    test('certified rejection preserves allowlisted reasons and never exposes arbitrary native copy', () async {
      for (final (reason, kind, words) in [
        ('insufficient_bitcoins', AppFailureKind.validation, 'network fee'),
        (
          'insufficient_asset_balance',
          AppFailureKind.validation,
          'Not enough funds',
        ),
        ('invalid_recipient', AppFailureKind.validation, 'recipient'),
        (
          'network_unavailable',
          AppFailureKind.connectivity,
          'Nothing was sent',
        ),
        ('storage_unavailable', AppFailureKind.storage, 'Nothing was sent'),
        ('SECRET_NATIVE_PAYLOAD', AppFailureKind.unavailable, 'not sent'),
      ]) {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.engine.preparePaymentOperationResult = WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.rejected,
          endAuthorized: false,
          failureCode: reason,
        );
        final result = await h.send() as AppFailureResult<WalletSendResult>;
        expect(result.failure.kind, kind);
        expect(result.failure.userMessage, contains(words));
        expect(
          result.failure.userMessage,
          isNot(contains('SECRET_NATIVE_PAYLOAD')),
        );
        expect(result.failure.requiresReconciliation, isFalse);
        expect(result.failure.outcomeUnknown, isFalse);
        expect(h.paymentOperations.dispatchCount, 0);
        expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
      }
    });

    test('read-only Activity exposes exact accepted receipt during archive failure without trying another archive write', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store.receiptWriteError = StateError('Archive unavailable');
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      h.engine.activities = [_bitcoinActivity(txid: _txid, selfTransfer: true)];
      final writes = List<String>.of(h.store.writes);
      final feed = await h.repository.activityFeed(
        WalletAssetKind.bitcoin,
      ) as AppSuccess<WalletActivityFeed>;
      expect(feed.value.activities.single.amount?.units, 20000);
      expect(
        feed.value.activities.single.operation,
        WalletActivityOperation.bitcoinSelfTransfer,
      );
      expect(
        feed.value.paymentSubmission?.outcome,
        WalletPaymentSubmissionOutcome.accepted,
      );
      expect(feed.value.paymentSubmission?.requiresReconciliation, isTrue);
      expect(h.store.writes, writes);
      expect(h.store.receiptDocuments, isEmpty);
      expect(
        h.runtime.snapshot.failure?.code,
        'payment_receipt_persistence_required',
      );
      _expectPending(await h.send());
      expect(h.paymentOperations.dispatchCount, 1);
    });

    test('stronger owner recovery failure does not erase a known accepted receipt whose app write failed', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store.failWriteNumber = 3;
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      expect(
        (jsonDecode(h.store.documents[_id]!) as Map)['phase'],
        'submitting',
      );
      h.engine
        ..requiresPaymentReopen = true
        ..openPersistedError = StateError('Owner reopen unavailable');
      expect(
        await h.repository.balance(WalletAssetKind.bitcoin),
        isA<AppFailureResult<WalletBalance>>(),
      );
      expect(h.runtime.hasPaymentSubmissionFence, isFalse);
      expect(
        h.runtime.snapshot.failure?.code,
        'wallet_payment_owner_recovery_required',
      );
      final known =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(known.outcome, WalletPaymentSubmissionOutcome.accepted);
      expect(known.result?.referenceId, _txid);
      expect(known.requiresReconciliation, isTrue);
      final calls = List<String>.of(h.engine.calls);
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppFailureResult<void>>(),
      );
      expect(h.engine.calls, calls);
      expect(h.paymentOperations.dispatchCount, 1);
    });

    test('older v2 accepted immutable receipts remain byte-identical after upgrading journal reader', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      String downgrade(String original) {
        final value = jsonDecode(original) as Map<String, Object?>;
        value.remove('commitAttempted');
        value['version'] = 2;
        return jsonEncode(value);
      }

      h.store.documents[_id] = downgrade(h.store.documents[_id]!);
      h.store.receiptDocuments[_id] = h.store.receiptDocuments[_id]!.map(
        (key, value) => MapEntry(key, downgrade(value)),
      );
      final original = Map<String, String>.of(h.store.receiptDocuments[_id]!);
      await h.restart();
      expect(h.store.receiptDocuments[_id], original);
      final record =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(record.journalVersion, 2);
      expect(record.outcome, WalletPaymentSubmissionOutcome.accepted);
    });

    test(
      'app intent precedes prepare and one commit never calls one-shot send',
      () async {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.store.onWrite = (_, document) {
          final value = jsonDecode(document) as Map<String, Object?>;
          expect(value['version'], 3);
          expect(value['recoveryRequest'], isA<String>());
          if (value['phase'] == 'submitting' &&
              value['commitAttempted'] == false) {
            expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
            expect(h.paymentOperations.dispatchCount, 0);
          }
        };
        expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
        expect(h.paymentOperations.dispatchCount, 1);
        expect(h.engine.legacySendPaymentCalls, 0);
        expect(
          h.engine.calls.where((c) => c == 'preparePaymentOperation'),
          hasLength(1),
        );
        expect(
          h.engine.calls.where((c) => c == 'commitPaymentOperation'),
          hasLength(1),
        );
      },
    );

    test('a failed app marker can record definite non-dispatch and allow explicit retry', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store.failWriteNumber = 1;
      final result = await h.send();
      expect(
        (result as AppFailureResult<WalletSendResult>).failure.code,
        'payment_not_dispatched',
      );
      expect(h.paymentOperations.dispatchCount, 0);
      expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
      expect((jsonDecode(h.store.documents[_id]!) as Map)['phase'], 'rejected');
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      expect(h.paymentOperations.dispatchCount, 1);
    });

    test('lost marker and rejection writes recover via native cancellation certificate after restart', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store.failWriteNumbers.addAll([1, 2]);
      h.store.commitBeforeErrorNumbers.add(1);
      _expectPending(await h.send());
      expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
      await h.restart();
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(
        h.engine.calls,
        containsAllInOrder([
          'inspectPaymentOperation',
          'cancelPaymentOperation',
        ]),
      );
      expect(h.paymentOperations.dispatchCount, 0);
      expect((jsonDecode(h.store.documents[_id]!) as Map)['phase'], 'rejected');
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    });

    test('lost prepare response cancels only that exact native operation without sending', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.preparePaymentOperationError = StateError('Lost prepare reply');
      _expectPending(await h.send());
      final request =
          (jsonDecode(h.store.documents[_id]!) as Map)['recoveryRequest'];
      expect(h.paymentOperations.operationCount, 1);
      expect(h.paymentOperations.dispatchCount, 0);
      await h.restart();
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(
        h.engine.calls.where((c) => c == 'preparePaymentOperation'),
        isEmpty,
      );
      expect(
        h.engine.calls.where((c) => c == 'commitPaymentOperation'),
        isEmpty,
      );
      expect(
        (jsonDecode(h.store.documents[_id]!) as Map)['recoveryRequest'],
        request,
      );
      expect(h.paymentOperations.operationCount, 1);
      expect(h.paymentOperations.dispatchCount, 0);
    });

    test('failed cancellation remains fenced until another explicit check succeeds', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.preparePaymentOperationError = StateError('Lost prepare reply');
      _expectPending(await h.send());
      h.engine.cancelPaymentOperationError = StateError(
        'Cancellation unavailable',
      );
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppFailureResult<void>>(),
      );
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
      _expectPending(await h.send());
      h.engine.cancelPaymentOperationError = null;
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(h.paymentOperations.dispatchCount, 0);
      expect(
        h.engine.calls.where((c) => c == 'preparePaymentOperation'),
        hasLength(1),
      );
    });

    test(
      'prepared status alone cannot certify cancellation or reopen mutations',
      () async {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.engine.preparePaymentOperationError = StateError(
          'Lost prepare reply',
        );
        _expectPending(await h.send());
        h.engine.cancelPaymentOperationResult = WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.prepared,
          endAuthorized: false,
          referenceId: _txid,
        );
        _expectPending(await h.repository.reconcilePaymentSubmission());
        _expectPending(await h.send());
        expect(h.paymentOperations.dispatchCount, 0);
      },
    );

    test('lost commit reply recovers exact acceptance after restart without history guessing', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.commitPaymentOperationReplyError = StateError(
        'Lost commit reply',
      );
      h.engine.inspectPaymentOperationError = StateError('Status unavailable');
      _expectPending(await h.send());
      final request =
          (jsonDecode(h.store.documents[_id]!) as Map)['recoveryRequest'];
      expect(h.paymentOperations.dispatchCount, 1);
      await h.restart();
      h.engine.activities = const [];
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(h.engine.calls, isNot(contains('activity')));
      expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
      expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
      expect(h.engine.legacySendPaymentCalls, 0);
      expect(h.paymentOperations.dispatchCount, 1);
      final receipt =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(receipt.result?.referenceId, _txid);
      expect(receipt.command.amount.units, 20000);
      expect(receipt.recoveryRequest, request);
      expect(h.store.receiptDocuments[_id], hasLength(1));
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(h.paymentOperations.dispatchCount, 1);
    });

    test('v2 acceptance write failures recover native identity without another dispatch', () async {
      for (final commitBeforeError in [false, true]) {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.store
          ..failWriteNumber = 3
          ..commitBeforeError = commitBeforeError;
        expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
        expect(h.paymentOperations.dispatchCount, 1);
        expect(
          (jsonDecode(h.store.documents[_id]!) as Map)['phase'],
          commitBeforeError ? 'accepted' : 'submitting',
        );
        await h.restart();
        h.engine.activities = const [];
        expect(
          await h.repository.reconcilePaymentSubmission(),
          isA<AppSuccess<void>>(),
        );
        expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
        final record =
            (await h.repository.paymentSubmissionStatus()
                    as AppSuccess<WalletPaymentSubmission?>)
                .value!;
        expect(record.result?.referenceId, _txid);
        expect(record.recoveryRequest, isNotNull);
        expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
        expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
        expect(h.paymentOperations.dispatchCount, 1);
        expect(h.store.receiptDocuments[_id], hasLength(1));
      }
    });

    test('RGB acceptance retains the authoritative final batch identity for the same transaction', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final route = PaymentRoute(
        asset: WalletAsset.rgbUsdt(
          assetId: 'rgb:configured-usdt',
          precision: 6,
        ),
        rail: PaymentRail.onchain,
      );
      h.engine
        ..sentPayment = WalletSendResult(
          route: route,
          amount: WalletAmount.onchain(assetId: route.asset.id, units: 20000),
          referenceId: _txid,
          status: WalletPaymentStatus.pending,
          batchTransferIndex: 41,
        )
        ..commitPaymentOperationResult = WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.accepted,
          endAuthorized: true,
          referenceId: _txid,
          batchTransferIndex: 42,
        );
      final result = await h.repository.sendPayment(
        target: WalletPaymentTarget.usdtOnchain,
        destination: 'rgb:encoded-invoice',
        amountUnits: 20000,
        reviewedFeeRate: h.fee,
        rgbRecipientType: RgbRecipientType.witness,
        witnessBitcoinAmountSats: rgbWitnessRecipientSats,
      );
      expect(
        (result as AppSuccess<WalletSendResult>).value.batchTransferIndex,
        42,
      );
      final record =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(record.result?.referenceId, _txid);
      expect(record.result?.batchTransferIndex, 42);
      expect(h.paymentOperations.dispatchCount, 1);
      expect(h.engine.legacySendPaymentCalls, 0);
    });

    test('unknown commit never automatically retries or cancels an authorized transaction', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.sendPaymentError = StateError('Uncertain native commit');
      _expectPending(await h.send());
      await h.restart();
      for (var i = 0; i < 3; i += 1) {
        _expectPending(await h.repository.reconcilePaymentSubmission());
      }
      expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
      expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expect(h.paymentOperations.dispatchCount, 1);
    });

    test('explicit resume commits only the saved authorized operation and preserves transaction identity', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.sendPaymentError = StateError('Lost commit outcome');
      _expectPending(await h.send());
      final request =
          (jsonDecode(h.store.documents[_id]!) as Map)['recoveryRequest'];
      await h.restart();
      expect(
        await h.repository.resumePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(
        h.engine.calls,
        containsAllInOrder([
          'inspectPaymentOperation',
          'commitPaymentOperation',
        ]),
      );
      expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expect(h.engine.legacySendPaymentCalls, 0);
      expect(h.paymentOperations.commitAttemptCount, 2);
      expect(h.paymentOperations.dispatchCount, 1);
      final record =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(record.result?.referenceId, _txid);
      expect(record.recoveryRequest, request);
      expect(h.store.receiptDocuments[_id], hasLength(1));
      expect(
        await h.repository.resumePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(h.paymentOperations.commitAttemptCount, 2);
    });

    test(
      'resume cannot authorize a preparation that never entered commit',
      () async {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.engine.preparePaymentOperationError = StateError(
          'Lost prepare reply',
        );
        _expectPending(await h.send());
        await h.restart();
        _expectPending(await h.repository.resumePaymentSubmission());
        expect(h.engine.calls, contains('inspectPaymentOperation'));
        expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
        expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
        expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
        expect(h.paymentOperations.dispatchCount, 0);
        expect(h.paymentOperations.commitAttemptCount, 0);
      },
    );

    test(
      'resume never guesses a legacy unidentified payment from history',
      () async {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.engine.sendPaymentError = StateError('Lost legacy response');
        _expectPending(await h.send());
        h.store.documents[_id] = h.asLegacyJournal(submitting: true);
        await h.restart();
        h.engine.activities = [_bitcoinActivity(txid: _txid)];
        _expectPending(await h.repository.resumePaymentSubmission());
        expect(h.engine.calls, isNot(contains('inspectPaymentOperation')));
        expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
        expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
        expect(h.paymentOperations.commitAttemptCount, 1);
      },
    );

    test('changed identity during resume installs a stronger quarantine instead of accepting it later', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.sendPaymentError = StateError('Lost commit outcome');
      _expectPending(await h.send());
      await h.restart();
      h.engine.commitPaymentOperationResult = WalletPaymentRecoveryStatus(
        phase: WalletPaymentRecoveryPhase.accepted,
        endAuthorized: true,
        referenceId: 'c' * 64,
      );
      final result = await h.repository.resumePaymentSubmission();
      expect(
        (result as AppFailureResult<void>).failure.code,
        'payment_native_identity_changed',
      );
      expect(
        h.runtime.snapshot.failure?.code,
        'payment_native_identity_changed',
      );
      expect(h.store.receiptDocuments, isEmpty);
      final calls = List<String>.of(h.engine.calls);
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppFailureResult<void>>(),
      );
      expect(
        await h.repository.resumePaymentSubmission(),
        isA<AppFailureResult<void>>(),
      );
      expect(h.engine.calls, calls);
      expect(h.paymentOperations.dispatchCount, 1);
    });

    test('restored request must match the exact reviewed command before any native inspection', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.preparePaymentOperationError = StateError('Lost prepare reply');
      _expectPending(await h.send());
      final document =
          jsonDecode(h.store.documents[_id]!) as Map<String, Object?>;
      final request = jsonDecode(
        document['recoveryRequest']! as String,
      ) as Map<String, Object?>;
      request['amount'] = 19999;
      document['recoveryRequest'] = jsonEncode(request);
      h.store.documents[_id] = jsonEncode(document);
      await h.restart();
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppFailureResult<void>>(),
      );
      expect(h.engine.calls, isNot(contains('inspectPaymentOperation')));
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expect(h.paymentOperations.dispatchCount, 0);
    });

    test('accepted native status requires valid identity and broadcast authorization', () async {
      for (final status in [
        const WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.accepted,
          endAuthorized: true,
          referenceId: 'invalid',
        ),
        WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.accepted,
          endAuthorized: false,
          referenceId: _txid,
        ),
        WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.accepted,
          endAuthorized: true,
          referenceId: _txid,
          batchTransferIndex: 9,
        ),
      ]) {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        h.engine.sendPaymentError = StateError('Uncertain native commit');
        _expectPending(await h.send());
        h.engine.inspectPaymentOperationResult = status;
        expect(
          await h.repository.reconcilePaymentSubmission(),
          isA<AppFailureResult<void>>(),
        );
        expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
        expect(h.store.receiptDocuments, isEmpty);
        expect(h.paymentOperations.dispatchCount, 1);
      }
    });
  });

  test('an archive commit with a lost acknowledgement never allows another payment', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store
      ..receiptCommitBeforeError = true
      ..receiptWriteError = StateError('Lost archive commit acknowledgement');
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    expect(h.store.receiptDocuments[_id], hasLength(1));
    _expectPending(await h.send());
    expect(h.engine.calls.where((c) => c == 'sendPayment:start'), hasLength(1));
    h.store.receiptWriteError = null;
    h.engine.activities = [_bitcoinActivity(txid: _txid, selfTransfer: true)];
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect(h.store.receiptDocuments[_id], hasLength(1));
    expect(h.engine.calls.where((c) => c == 'sendPayment:start'), hasLength(1));
  });

  test('one reviewed receipt never enriches duplicate native transaction identities', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    h.engine.activities = [
      _bitcoinActivity(txid: _txid, selfTransfer: true),
      _bitcoinActivity(txid: _txid, index: 2, selfTransfer: true),
    ];
    final feed = await h.repository.activityFeed(WalletAssetKind.bitcoin);
    expect(
      (feed as AppFailureResult<WalletActivityFeed>).failure,
      walletActivityConsistencyFailure,
    );
    expect(h.engine.activities.every((a) => a.amount == null), isTrue);
  });

  test(
    'two accepted self-transfer amounts survive a newer send and restart',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      final secondTx = 'c' * 64;
      h.engine.sentPayment = WalletSendResult(
        route: const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.onchain,
        ),
        amount: WalletAmount.onchain(
          assetId: WalletAsset.bitcoin.id,
          units: 30000,
        ),
        referenceId: secondTx,
        status: WalletPaymentStatus.pending,
      );
      expect(
        await h.send(amountUnits: 30000),
        isA<AppSuccess<WalletSendResult>>(),
      );
      expect(h.store.receiptDocuments[_id], hasLength(2));
      await h.restart();
      h.engine.activities = [
        _bitcoinActivity(txid: _txid, selfTransfer: true),
        _bitcoinActivity(txid: secondTx, index: 2, selfTransfer: true),
      ];
      final feed = (await h.repository.activityFeed(
        WalletAssetKind.bitcoin,
      ) as AppSuccess<WalletActivityFeed>).value;
      expect(feed.activities.map((a) => a.amount?.units), [20000, 30000]);
      expect(
        feed.activities.every(
          (a) => a.direction == WalletActivityDirection.internal,
        ),
        isTrue,
      );
      expect(
        feed.activities.every((a) => a.status == WalletActivityStatus.pending),
        isTrue,
      );
      expect(h.engine.activities.every((a) => a.amount == null), isTrue);
      expect(h.engine.calls, isNot(contains('sendPayment:start')));
    },
  );

  test(
    'legacy v1 accepted journal backfills before a newer receipt replaces it',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      final legacy = h.asLegacyJournal();
      h.store.documents[_id] = legacy;
      expect((jsonDecode(legacy) as Map)['version'], 1);
      h.store.receiptDocuments.clear();
      await h.restart();
      expect(h.store.receiptDocuments[_id], hasLength(1));
      expect(h.store.documents[_id], legacy);
      final originalArchive = Map<String, String>.from(
        h.store.receiptDocuments[_id]!,
      );
      await h.repository.paymentSubmissionStatus();
      await h.repository.paymentSubmissionStatus();
      expect(h.store.receiptDocuments[_id], originalArchive);
      h.engine.sentPayment = WalletSendResult(
        route: const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.onchain,
        ),
        amount: WalletAmount.onchain(
          assetId: WalletAsset.bitcoin.id,
          units: 20000,
        ),
        referenceId: 'c' * 64,
        status: WalletPaymentStatus.pending,
      );
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      expect(h.store.receiptDocuments[_id], hasLength(2));
      for (final entry in originalArchive.entries) {
        expect(h.store.receiptDocuments[_id]![entry.key], entry.value);
      }
    },
  );

  test('archive failure after native acceptance fences replay and recovers from accepted journal', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store.receiptWriteError = DurableStorageCommitException([
      StateError('Lost archive acknowledgement'),
    ]);
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    expect((jsonDecode(h.store.documents[_id]!) as Map)['phase'], 'accepted');
    expect(h.store.writes, hasLength(3));
    _expectPending(await h.send());
    expect(h.engine.calls.where((c) => c == 'sendPayment:start'), hasLength(1));
    h.store.receiptWriteError = null;
    h.engine.activities = [_bitcoinActivity(txid: _txid, selfTransfer: true)];
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect(h.store.receiptDocuments[_id], hasLength(1));
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(h.engine.activities.single.amount, isNull);
    expect(h.engine.calls.where((c) => c == 'sendPayment:start'), hasLength(1));
  });

  test('accepted backfill failure before a newer Send retains known acceptance rather than unknown owner quarantine', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    h.store.receiptDocuments.clear();
    h.store.receiptWriteError = DurableStorageCommitException([
      StateError('Archive unavailable'),
    ]);
    final result = await h.send() as AppFailureResult<WalletSendResult>;
    expect(result.failure.code, 'payment_receipt_persistence_required');
    expect(result.failure.outcomeUnknown, isFalse);
    expect(h.runtime.hasPaymentSubmissionFence, isTrue);
    final record =
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    expect(record.outcome, WalletPaymentSubmissionOutcome.accepted);
    expect(record.result?.referenceId, _txid);
    expect(h.paymentOperations.dispatchCount, 1);
    h.store.receiptWriteError = null;
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
  });

  test('accepted archive failure cannot overwrite legacy journal or enter native again', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    final accepted = h.store.documents[_id];
    h.store.receiptDocuments.clear();
    h.store.receiptWriteError = StateError('Archive unavailable');
    expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
    expect(h.store.documents[_id], accepted);
    expect(h.store.writes, hasLength(3));
    expect(h.engine.calls.where((c) => c == 'sendPayment:start'), hasLength(1));
  });

  test(
    'reviewed history never replaces a conflicting native external amount',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      h.engine.activities = [_bitcoinActivity(txid: _txid, amount: 19999)];
      final feed = await h.repository.activityFeed(WalletAssetKind.bitcoin);
      expect(
        (feed as AppFailureResult<WalletActivityFeed>).failure,
        walletActivityConsistencyFailure,
      );
      expect(h.engine.activities.single.amount?.units, 19999);
    },
  );

  test('an unknown self-transfer cannot recover a requested amount from outputs or balance', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine.activities = [_bitcoinActivity(txid: _txid, selfTransfer: true)];
    final feed = (await h.repository.activityFeed(
      WalletAssetKind.bitcoin,
    ) as AppSuccess<WalletActivityFeed>).value;
    expect(feed.activities.single.amount, isNull);
    expect(h.store.receiptDocuments, isEmpty);
  });

  test('receipt key and wallet/network binding corruption fail bootstrap before native opens', () async {
    for (final corruptKey in [false, true]) {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      final receipt = h.store.receiptDocuments[_id]!.entries.single;
      if (corruptKey) {
        h.store.receiptDocuments[_id] = {'f' * 64: receipt.value};
      } else {
        final decoded = jsonDecode(receipt.value) as Map<String, Object?>;
        decoded['network'] = 'mainnet';
        h.store.receiptDocuments[_id]![receipt.key] = jsonEncode(decoded);
      }
      // The old journal is absent to ensure archive validation is independent.
      h.store.documents.clear();
      final boot = await h.restart(expectSuccess: false);
      expect(
        (boot as AppFailureResult<WalletRegistry>).failure.code,
        'stored_data_invalid',
      );
      expect(h.engine.calls, isNot(contains('openPersisted')));
    }
  });

  test('an earlier accepted receipt cannot resolve a different legacy submitting marker', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    final previous =
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    final nextId = previous.id == 'f' * 32 ? 'e' * 32 : 'f' * 32;
    h.store.documents[_id] = h.asLegacyJournal(
      submitting: true,
      operationId: nextId,
    );
    await h.restart();
    final pending =
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    expect(pending.id, isNot(previous.id));
    expect(pending.phase, WalletPaymentSubmissionPhase.submitting);
    h.engine.activities = [_bitcoinActivity(txid: _txid)];
    _expectPending(await h.repository.reconcilePaymentSubmission());
    expect(
      h.engine.calls.where((call) => call == 'sendPayment:start'),
      isEmpty,
    );
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
  });

  test(
    'failed native cleanup escalates payment audit to a full quarantine',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store
        ..failWriteNumber = 3
        ..commitBeforeError = true;
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      h.engine
        ..destroyError = StateError('Lost destroy response')
        ..activities = [_bitcoinActivity(txid: _txid)];
      expect(await h.repository.dispose(), isA<AppFailureResult<void>>());
      expect(h.runtime.snapshot.failure?.code, 'wallet_native_cleanup_failed');
      final calls = h.engine.calls.toList();
      expect(
        await h.repository.activityFeed(WalletAssetKind.bitcoin),
        isA<AppFailureResult<WalletActivityFeed>>(),
      );
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppFailureResult<void>>(),
      );
      expect(await h.send(), isA<AppFailureResult<WalletSendResult>>());
      expect(h.engine.calls, calls);
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
      h.engine.destroyError = null;
    },
  );

  test(
    'strong native audit failure cannot be repaired by matching a receipt',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.store
        ..failWriteNumber = 3
        ..commitBeforeError = true;
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      h.engine.activityError = const AppFailureException(
        AppFailure(
          code: 'native_owner_state_invalid',
          kind: AppFailureKind.storage,
          userMessage: 'Wallet recovery required.',
          retryable: false,
          requiresReconciliation: true,
        ),
      );
      expect(
        await h.repository.activityFeed(WalletAssetKind.bitcoin),
        isA<AppFailureResult<WalletActivityFeed>>(),
      );
      expect(h.runtime.snapshot.failure?.code, 'native_owner_state_invalid');
      h.engine
        ..activityError = null
        ..activities = [_bitcoinActivity(txid: _txid)];
      final calls = h.engine.calls.toList();
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppFailureResult<void>>(),
      );
      expect(h.engine.calls, calls);
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    },
  );

  test('durable accepted receipt remains identifiable after lost local ack and restart', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store
      ..failWriteNumber = 3
      ..commitBeforeError = true;
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    await h.restart();
    final feed = await h.repository.activityFeed(WalletAssetKind.bitcoin);
    final receipt =
        (feed as AppSuccess<WalletActivityFeed>).value.paymentSubmission!;
    expect(receipt.phase, WalletPaymentSubmissionPhase.accepted);
    expect(receipt.result?.referenceId, _txid);
    expect(receipt.command.destination, _destination);
    expect(receipt.requiresReconciliation, isFalse);
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
  });

  test('malformed native transaction receipts never become accepted', () async {
    for (final receipt in [
      ('not-a-txid', null),
      ('a' * 63, null),
      ('a' * 64, 0),
    ]) {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      const route = PaymentRoute(
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.onchain,
      );
      h.engine.sentPayment = WalletSendResult(
        route: route,
        amount: WalletAmount.onchain(assetId: route.asset.id, units: 20000),
        referenceId: receipt.$1,
        batchTransferIndex: receipt.$2,
        status: WalletPaymentStatus.pending,
      );
      _expectPending(await h.send());
      expect(h.store.writes, hasLength(1));
      await h.restart();
      _expectPending(await h.send());
      expect(h.engine.calls, isNot(contains('sendPayment:start')));
    }
  });

  test('durable reviewed intent precedes dispatch and exact acceptance precedes success', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store.onWrite = (_, document) {
      final value = jsonDecode(document) as Map<String, Object?>;
      if (value['phase'] == 'submitting') {
        expect(h.engine.calls, isNot(contains('sendPayment:start')));
      } else {
        expect(h.engine.calls, contains('sendPayment:end'));
      }
    };
    final result = await h.send();
    expect(result, isA<AppSuccess<WalletSendResult>>());
    expect(h.store.writes, hasLength(3));
    final intent = jsonDecode(h.store.writes.first) as Map<String, Object?>;
    final command = intent['command']! as Map<String, Object?>;
    expect(intent['walletId'], _id);
    expect(intent['storageToken'], _storageToken);
    expect(intent['network'], 'regtest');
    expect(command['destination'], _destination);
    expect(command['amount'], 20000);
    expect(command['feeRate'], 2);
    expect(command['feeTarget'], 6);
    final status = await h.repository.paymentSubmissionStatus();
    final record = (status as AppSuccess<WalletPaymentSubmission?>).value!;
    expect(record.command, h.engine.sentPaymentCommand);
    expect(record.phase, WalletPaymentSubmissionPhase.accepted);
    expect(record.result?.referenceId, _txid);
    expect(record.toString(), isNot(contains(_destination)));
    expect(record.toString(), isNot(contains(_txid)));
    await h.restart();
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(
      (await h.repository.paymentSubmissionStatus()
              as AppSuccess<WalletPaymentSubmission?>)
          .value
          ?.result
          ?.referenceId,
      _txid,
    );
  });

  test('lost native response fences all mutations and leaves Activity readable across restart', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine.sendPaymentError = const WalletMutationOutcomeUnknownException(
      FailureDiagnostic(sourceType: 'LostReply'),
    );
    _expectPending(await h.send());
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppSuccess<WalletActivityFeed>>(),
    );
    expect(
      await h.repository.balance(WalletAssetKind.bitcoin),
      isA<AppSuccess<WalletBalance>>(),
    );
    expect(await h.repository.portfolio(), isA<AppSuccess<WalletPortfolio>>());
    expect(
      await h.repository.networkStatus(),
      isA<AppSuccess<WalletNetworkStatus>>(),
    );
    await h.restart();
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    final before = h.engine.calls.toList();
    _expectPending(await h.send());
    expect(
      await h.repository.createReceiveRequest(
        WalletPaymentTarget.bitcoinOnchain,
      ),
      isA<AppSuccess<WalletReceiveRequest>>(),
    );
    _expectPending(
      await h.repository.createReceiveRequest(WalletPaymentTarget.usdtOnchain),
    );
    _expectPending(await h.repository.prepareRgbWalletSetup());
    expect(
      await h.repository.switchWallet('2' * 32),
      isA<AppFailureResult<WalletRegistry>>(),
    );
    _expectPending(
      await h.repository.createFromMnemonic(mnemonic: 'invalid', name: 'New'),
    );
    expect(
      await h.repository.publicKeys(),
      isA<AppSuccess<WalletPublicKeys>>(),
    );
    expect(await h.repository.recoveryMnemonic(_id), isA<AppSuccess<String>>());
    expect(h.engine.calls.where((call) => !before.contains(call)), [
      'createReceiveRequest:start',
      'createReceiveRequest:end',
      'publicKeys',
    ]);
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppSuccess<WalletActivityFeed>>(),
    );
    _expectPending(await h.repository.reconcilePaymentSubmission());
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    expect(h.store.writes, hasLength(2));
  });

  test('empty or similar native history never identifies an unknown Bitcoin submission', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine.sendPaymentError = StateError('A native response disappeared');
    _expectPending(await h.send());
    await h.restart();
    for (final history in <List<WalletActivity>>[
      [],
      [_bitcoinActivity(txid: 'c' * 64)],
      [_bitcoinActivity(txid: _txid)],
    ]) {
      h.engine.activities = history;
      expect(
        await h.repository.activityFeed(WalletAssetKind.bitcoin),
        isA<AppSuccess<WalletActivityFeed>>(),
      );
      _expectPending(await h.repository.reconcilePaymentSubmission());
      _expectPending(await h.send());
    }
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
    expect(h.store.writes, hasLength(2));
  });

  test('legacy v1 committed submitting marker never replays native after restart', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store
      ..failWriteNumber = 1
      ..commitBeforeError = true;
    final result = await h.send();
    expect(
      (result as AppFailureResult<WalletSendResult>).failure.code,
      'payment_not_dispatched',
    );
    // Simulate the marker left by the previous v1 implementation. It did not
    // retain the native request/proof needed for the v2 cancellation protocol.
    h.store.documents[_id] = h.asLegacyJournal(submitting: true);
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
    await h.restart();
    _expectPending(await h.send());
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
  });

  test('lost acceptance commit retains the submitting marker and never retries native', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store.failWriteNumber = 3;
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    h.store.documents[_id] = h.asLegacyJournal(submitting: true);
    expect(
      h.engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    await h.restart();
    h.engine.activities = [_bitcoinActivity(txid: _txid)];
    _expectPending(await h.repository.reconcilePaymentSubmission());
    _expectPending(await h.send());
    expect(h.engine.calls, isNot(contains('sendPayment:start')));
  });

  test('durably accepted lost acknowledgement resolves only the exact native transaction', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store
      ..failWriteNumber = 3
      ..commitBeforeError = true;
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    // Explicit legacy data keeps this exact-history regression meaningful.
    h.store.documents[_id] = h.asLegacyJournal();
    for (final history in <List<WalletActivity>>[
      [],
      [_bitcoinActivity(txid: 'c' * 64)],
      [_bitcoinActivity(txid: _txid, amount: 19999)],
      [_bitcoinActivity(txid: _txid), _bitcoinActivity(txid: _txid, index: 2)],
    ]) {
      h.engine.activities = history;
      _expectPending(await h.repository.reconcilePaymentSubmission());
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    }
    h.engine.activities = [_bitcoinActivity(txid: _txid)];
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(
      h.engine.calls.where((call) => call == 'sendPayment:start'),
      hasLength(1),
    );
    expect(h.store.writes, hasLength(3));
  });

  test('RGB journal retains recipient policy and resolves only matching asset, txid, and native batch', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store
      ..failWriteNumber = 3
      ..commitBeforeError = true;
    final route = PaymentRoute(
      asset: WalletAsset.rgbUsdt(assetId: 'rgb:configured-usdt', precision: 6),
      rail: PaymentRail.onchain,
    );
    h.engine.sentPayment = WalletSendResult(
      route: route,
      amount: WalletAmount.onchain(assetId: route.asset.id, units: 20000),
      referenceId: _txid,
      status: WalletPaymentStatus.pending,
      batchTransferIndex: 42,
    );
    expect(
      await h.repository.sendPayment(
        target: WalletPaymentTarget.usdtOnchain,
        destination: 'rgb:encoded-invoice',
        amountUnits: 20000,
        reviewedFeeRate: h.fee,
        rgbRecipientType: RgbRecipientType.witness,
        witnessBitcoinAmountSats: rgbWitnessRecipientSats,
      ),
      isA<AppSuccess<WalletSendResult>>(),
    );
    h.store.documents[_id] = h.asLegacyJournal();
    final intent =
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    expect(intent.command.rgbRecipientType, RgbRecipientType.witness);
    expect(intent.command.witnessBitcoinAmountSats, 1000);
    h.engine.activities = [_rgbActivity(route, batch: 43)];
    _expectPending(await h.repository.reconcilePaymentSubmission());
    h.engine.activities = [_rgbActivity(route, batch: 42)];
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
  });

  test('review or confirmed local validation rejection permits a fresh explicit submission', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final missingReview = await h.repository.sendPayment(
      target: WalletPaymentTarget.bitcoinOnchain,
      destination: _destination,
      amountUnits: 20000,
    );
    expect(
      (missingReview as AppFailureResult<WalletSendResult>).failure,
      walletFeeReviewRequiredFailure,
    );
    expect(h.store.writes, isEmpty);
    h.engine.sendPaymentError =
        const WalletPaymentRejectedBeforeDispatchException(
          AppFailure(
            code: 'wallet_validation',
            kind: AppFailureKind.validation,
            userMessage: 'Check the entered information and try again.',
            retryable: false,
          ),
        );
    final rejected = await h.send();
    expect(
      (rejected as AppFailureResult<WalletSendResult>).failure.outcomeUnknown,
      isFalse,
    );
    expect(
      (await h.repository.paymentSubmissionStatus()
              as AppSuccess<WalletPaymentSubmission?>)
          .value
          ?.phase,
      WalletPaymentSubmissionPhase.rejected,
    );
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    h.engine.sendPaymentError = null;
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
  });

  test(
    'native mismatched acknowledgement cannot clear the durable intent',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      const route = PaymentRoute(
        asset: WalletAsset.bitcoin,
        rail: PaymentRail.onchain,
      );
      h.engine.sentPayment = WalletSendResult(
        route: route,
        amount: WalletAmount.onchain(
          assetId: WalletAsset.bitcoin.id,
          units: 19999,
        ),
        referenceId: _txid,
        status: WalletPaymentStatus.pending,
      );
      _expectPending(await h.send());
      expect(h.store.writes, hasLength(2));
      _expectPending(await h.repository.reconcilePaymentSubmission());
    },
  );

  test(
    'a queued second send cannot cross the first unresolved dispatch',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine
        ..sendPaymentGate = Completer<void>()
        ..sendPaymentError = StateError('Lost response');
      final first = h.send();
      await Future<void>.delayed(Duration.zero);
      final second = h.send();
      h.engine.sendPaymentGate!.complete();
      _expectPending(await first);
      _expectPending(await second);
      expect(
        h.engine.calls.where((call) => call == 'sendPayment:start'),
        hasLength(1),
      );
      expect(h.store.writes, hasLength(2));
    },
  );

  test('background shutdown and resume preserve the read-only fence', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine.sendPaymentError = StateError('Lost response');
    _expectPending(await h.send());
    expect(await h.repository.suspend(), isA<AppSuccess<void>>());
    expect(h.engine.calls, contains('shutdown'));
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppFailureResult<WalletActivityFeed>>(),
    );
    expect(
      h.runtime.snapshot.failure?.code,
      walletPaymentSubmissionPendingFailure.code,
    );
    expect(await h.repository.resume(), isA<AppSuccess<void>>());
    expect(h.engine.calls, contains('openPersisted'));
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppSuccess<WalletActivityFeed>>(),
    );
    _expectPending(await h.send());
  });

  test('uncertain shutdown never leaves a readable native lease', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine
      ..sendPaymentError = StateError('Lost response')
      ..shutdownError = StateError('Lost shutdown response');
    _expectPending(await h.send());
    expect(await h.repository.suspend(), isA<AppFailureResult<void>>());
    expect(
      await h.repository.activityFeed(WalletAssetKind.bitcoin),
      isA<AppFailureResult<WalletActivityFeed>>(),
    );
    _expectPending(await h.send());
    h.engine.shutdownError = null;
  });

  test('storage binding, schema, and malformed intent fail bootstrap before native open', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    final original = h.store.documents[_id]!;
    for (final change in <void Function(Map<String, Object?>)>[
      (value) => value['walletId'] = '2' * 32,
      (value) => value['storageToken'] = 'c' * 32,
      (value) => value['network'] = 'mainnet',
      (value) => value['version'] = 4,
      (value) => value['phase'] = 'forgotten',
      (value) => value['extra'] = true,
      (value) => value['result'] = null,
      (value) => (value['result']! as Map<String, Object?>)['referenceId'] =
          'not-a-txid',
      (value) =>
          (value['result']! as Map<String, Object?>)['batchTransferIndex'] = 0,
      (value) => (value['command']! as Map<String, Object?>)['amount'] = 0,
      (value) => (value['command']! as Map<String, Object?>)['feeRate'] = 0,
    ]) {
      final modified = jsonDecode(original) as Map<String, Object?>;
      change(modified);
      h.store.documents[_id] = jsonEncode(modified);
      final boot = await h.restart(expectSuccess: false);
      expect(
        (boot as AppFailureResult<WalletRegistry>).failure.code,
        'stored_data_invalid',
      );
      expect(h.engine.calls, isNot(contains('openPersisted')));
    }
  });

  test(
    'wallet sends fail closed when no durable journal has been configured',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final repository = h.buildRepository(withJournal: false);
      final result = await repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: _destination,
        amountUnits: 20000,
        reviewedFeeRate: h.fee,
      );
      expect(
        (result as AppFailureResult<WalletSendResult>).failure.code,
        'payment_journal_unavailable',
      );
      expect(h.engine.calls, isNot(contains('sendPayment:start')));
    },
  );

  test('IO financial journal never falls back from a corrupt newest slot to an older accepted document', () async {
    final root = await Directory.systemTemp.createTemp(
      'aster-payment-journal-',
    );
    addTearDown(() => root.delete(recursive: true));
    final security = MemoryWalletStorageSecurity();
    final store = IoWalletPaymentJournalStore(root.path, security);
    await store.write(_id, '{"phase":"accepted"}');
    await store.write(_id, '{"phase":"submitting"}');
    await File('${root.path}/$_id/wallet_registry.b.json')
        .writeAsString('{truncated', flush: true);
    final freshStore = IoWalletPaymentJournalStore(root.path, security);
    await expectLater(
      freshStore.read(_id),
      throwsA(isA<StoredDataCorruptionException>()),
    );
    await expectLater(
      store.read('../escape'),
      throwsA(isA<StoredDataCorruptionException>()),
    );
  });
}

void _expectPending<T>(AppResult<T> result) {
  expect(result, isA<AppFailureResult<T>>());
  final failure = (result as AppFailureResult<T>).failure;
  expect(isWalletPaymentSubmissionFenceFailure(failure), isTrue);
  expect(failure.retryable, isFalse);
  expect(failure.requiresReconciliation, isTrue);
  expect(
    failure.outcomeUnknown,
    failure.code == walletPaymentSubmissionPendingFailure.code,
  );
}

WalletActivity _bitcoinActivity({
  required String txid,
  int amount = 20000,
  int index = 1,
  bool selfTransfer = false,
}) => WalletActivity(
  id: 'activity-${index.toRadixString(16).padLeft(64, '0')}',
  source: WalletActivitySource.bitcoinTransaction,
  operation: selfTransfer
      ? WalletActivityOperation.bitcoinSelfTransfer
      : WalletActivityOperation.bitcoinSend,
  asset: WalletAsset.bitcoin,
  rail: PaymentRail.onchain,
  direction: selfTransfer
      ? WalletActivityDirection.internal
      : WalletActivityDirection.sent,
  status: WalletActivityStatus.pending,
  amount: selfTransfer
      ? null
      : WalletAmount.onchain(assetId: WalletAsset.bitcoin.id, units: amount),
  txid: txid,
);

WalletActivity _rgbActivity(PaymentRoute route, {required int batch}) =>
    WalletActivity(
      id: 'activity-${'1' * 64}',
      source: WalletActivitySource.rgbTransfer,
      operation: WalletActivityOperation.rgbSend,
      asset: route.asset,
      rail: PaymentRail.onchain,
      direction: WalletActivityDirection.sent,
      status: WalletActivityStatus.waitingConfirmations,
      amount: WalletAmount.onchain(assetId: route.asset.id, units: 20000),
      txid: _txid,
      transferIndex: 1,
      batchTransferIndex: batch,
    );

final class _Harness {
  final store = MemoryWalletPaymentJournalStore();
  final paymentOperations = FakeWalletPaymentOperationStore();
  final profiles = WalletProfileStore(
    MemoryWalletRegistryDocumentStore(),
    clock: () => _now,
  );
  final directories = FakeWalletDirectoryManager();
  final secrets = WalletSecretStore(MemorySecureStore());
  late WalletRuntime runtime;
  late WalletRepository repository;
  late FakeWalletEngine engine;
  late WalletFeeRateEstimate fee;

  static Future<_Harness> create() async {
    final h = _Harness();
    h._newRuntime();
    final profile = WalletProfile(
      id: _id,
      name: 'Test',
      createdAt: _now,
      updatedAt: _now,
      environment: BlockchainEnvironment.regtest,
      state: WalletProfileState.provisioning,
      storageToken: _storageToken,
    );
    expect(
      await h.profiles.stageProvision(profile),
      isA<AppSuccess<WalletRegistry>>(),
    );
    expect(
      await h.runtime.provision(
        profile: profile,
        mnemonic: 'test mnemonic',
        databasePassword: 'password',
      ),
      isA<AppSuccess<void>>(),
    );
    expect(
      await h.profiles.commitProvision(_id),
      isA<AppSuccess<WalletRegistry>>(),
    );
    h.repository = h.buildRepository();
    return h;
  }

  void _newRuntime() {
    fee = WalletFeeRateEstimate(
      targetBlocks: 6,
      satsPerVbyte: 2,
      observedAt: _now,
    );
    engine = FakeWalletEngine(paymentOperations: paymentOperations)
      ..feeEstimate = fee;
    runtime = WalletRuntime(
      FakeWalletEngineFactory([engine]),
      directories,
      secrets,
      _services,
    );
    const route = PaymentRoute(
      asset: WalletAsset.bitcoin,
      rail: PaymentRail.onchain,
    );
    engine.sentPayment = WalletSendResult(
      route: route,
      amount: WalletAmount.onchain(
        assetId: WalletAsset.bitcoin.id,
        units: 20000,
      ),
      referenceId: _txid,
      status: WalletPaymentStatus.pending,
    );
  }

  WalletRepository buildRepository({bool withJournal = true}) =>
      WalletRepository(
        profiles,
        runtime,
        FakeWalletKeyGenerator(),
        FakeWalletIdentityGenerator(walletId: _id),
        _services,
        clock: () => _now,
        paymentJournalStore: withJournal ? store : null,
      );

  Future<AppResult<WalletRegistry>> restart({bool expectSuccess = true}) async {
    await runtime.dispose();
    _newRuntime();
    repository = buildRepository();
    final result = await repository.bootstrap();
    if (expectSuccess) expect(result, isA<AppSuccess<WalletRegistry>>());
    return result;
  }

  String asLegacyJournal({bool submitting = false, String? operationId}) {
    final document = jsonDecode(store.documents[_id]!) as Map<String, Object?>;
    document
      ..remove('recoveryRequest')
      ..remove('commitAttempted')
      ..['version'] = 1;
    if (submitting) {
      document
        ..['phase'] = 'submitting'
        ..['result'] = null;
    }
    if (operationId != null) document['id'] = operationId;
    return jsonEncode(document);
  }

  Future<AppResult<WalletSendResult>> send({int amountUnits = 20000}) =>
      repository.sendPayment(
        target: WalletPaymentTarget.bitcoinOnchain,
        destination: _destination,
        amountUnits: amountUnits,
        reviewedFeeRate: fee,
      );

  Future<void> dispose() async => runtime.dispose();
}
