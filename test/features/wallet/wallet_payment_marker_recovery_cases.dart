part of 'wallet_payment_submissions_test.dart';

void _markerRecoveryCases() {
  Future<_Harness> lostMarker() async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.store.failWriteNumbers.addAll([1, 2]);
    _expectPending(await h.send());
    expect(h.store.documents[_id], isNull);
    expect(h.paymentOperations.operationCount, 0);
    h.engine.calls.clear();
    return h;
  }

  void expectNoDispatch(_Harness h) {
    expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
    expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
    expect(h.engine.legacySendPaymentCalls, 0);
    expect(h.paymentOperations.commitAttemptCount, 0);
    expect(h.paymentOperations.dispatchCount, 0);
  }

  test('Check cancels exact volatile v2 intent when both journal writes left no disk record', () async {
    final h = await lostMarker();
    _expectPending(await h.repository.resumePaymentSubmission());
    expect(h.engine.calls, isNot(contains('inspectPaymentOperation')));
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expectNoDispatch(h);
    expect(h.engine.calls.where((call) => call.endsWith('PaymentOperation')), [
      'inspectPaymentOperation',
      'cancelPaymentOperation',
    ]);
    expect((jsonDecode(h.store.documents[_id]!) as Map)['phase'], 'rejected');
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
  });

  test(
    'volatile intent recovery preserves a different older accepted receipt',
    () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
      final accepted = h.store.documents[_id]!;
      final oldId = (jsonDecode(accepted) as Map)['id'];
      final archived = Map<String, String>.of(h.store.receiptDocuments[_id]!);
      final next = h.store.writes.length + 1;
      h.store.failWriteNumbers.addAll([next, next + 1]);
      _expectPending(await h.send());
      expect(h.store.documents[_id], accepted);
      final current =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(current.id, isNot(oldId));
      h.engine.calls.clear();
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      final rejected = jsonDecode(h.store.documents[_id]!) as Map;
      expect(rejected['id'], current.id);
      expect(rejected['phase'], 'rejected');
      expect(h.store.receiptDocuments[_id], archived);
      expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
      expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
      expect(
        h.engine.calls.where((call) => call == 'cancelPaymentOperation'),
        hasLength(1),
      );
      expect(h.paymentOperations.dispatchCount, 1);
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    },
  );

  test(
    'volatile memory cannot replace another unresolved durable operation',
    () async {
      final h = await lostMarker();
      final other = await _Harness.create();
      addTearDown(other.dispose);
      expect(await other.send(), isA<AppSuccess<WalletSendResult>>());
      other.engine.preparePaymentOperationError = StateError(
        'Lost prepare reply',
      );
      _expectPending(await other.send());
      final unresolved = other.store.documents[_id]!;
      h.store.documents[_id] = unresolved;
      _expectPending(await h.repository.reconcilePaymentSubmission());
      expect(h.store.documents[_id], unresolved);
      expect(h.store.writes, hasLength(2));
      expect(h.engine.calls, isNot(contains('inspectPaymentOperation')));
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expectNoDispatch(h);
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    },
  );

  test('lost volatile recovery certificate acknowledgement retains fence until an explicit second Check', () async {
    for (final committed in [false, true]) {
      final h = await lostMarker();
      h.store.failWriteNumbers.add(3);
      if (committed) h.store.commitBeforeErrorNumbers.add(3);
      final failed = await h.repository.reconcilePaymentSubmission();
      expect(failed, isA<AppFailureResult<void>>());
      expect(
        (failed as AppFailureResult<void>).failure.outcomeUnknown,
        isFalse,
      );
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
      expectNoDispatch(h);
      expect(
        h.engine.calls.where((call) => call == 'cancelPaymentOperation'),
        hasLength(1),
      );
      _expectPending(await h.send());
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(
        h.engine.calls.where((call) => call == 'cancelPaymentOperation'),
        hasLength(1),
      );
      expect(
        h.engine.calls.where((call) => call == 'inspectPaymentOperation'),
        hasLength(2),
      );
      expect((jsonDecode(h.store.documents[_id]!) as Map)['phase'], 'rejected');
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
      expectNoDispatch(h);
    }
  });

  test('accepted native receipt survives lost recovery journal acknowledgement without owner quarantine or replay', () async {
    for (final committed in [false, true]) {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.commitPaymentOperationReplyError = StateError(
        'Lost commit reply',
      );
      h.engine.inspectPaymentOperationError = StateError('Status unavailable');
      _expectPending(await h.send());
      h.engine.inspectPaymentOperationError = null;
      h.store.failWriteNumbers.add(3);
      if (committed) h.store.commitBeforeErrorNumbers.add(3);
      _expectPending(await h.repository.reconcilePaymentSubmission());
      expect(
        h.runtime.snapshot.failure?.code,
        'payment_receipt_persistence_required',
      );
      _expectPending(await h.send());
      expect(
        await h.repository.reconcilePaymentSubmission(),
        isA<AppSuccess<void>>(),
      );
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
      expect((jsonDecode(h.store.documents[_id]!) as Map)['phase'], 'accepted');
      expect(h.store.receiptDocuments[_id], hasLength(1));
      expect(h.paymentOperations.dispatchCount, 1);
      expect(h.paymentOperations.commitAttemptCount, 1);
      expect(h.engine.legacySendPaymentCalls, 0);
      expect(
        h.engine.calls.where((call) => call == 'preparePaymentOperation'),
        hasLength(1),
      );
      expect(
        h.engine.calls.where((call) => call == 'commitPaymentOperation'),
        hasLength(1),
      );
      expect(
        h.engine.calls.where((call) => call == 'inspectPaymentOperation'),
        hasLength(3),
      );
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
    }
  });

  test('lost SDK outbox continuity escalates beyond the payment fence and blocks all native recovery', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine.preparePaymentOperationError = StateError('Lost prepare reply');
    _expectPending(await h.send());
    final document = h.store.documents[_id];
    h.engine.inspectPaymentOperationError =
        const RecoverableSendStorageException();
    h.engine.calls.clear();
    final result = await h.repository.reconcilePaymentSubmission();
    final failure = (result as AppFailureResult<void>).failure;
    expect(failure.code, 'payment_recovery_state_lost');
    expect(failure.requiresReconciliation, isTrue);
    expect(h.runtime.snapshot.failure?.code, 'payment_recovery_state_lost');
    final callsAfterFailure = List<String>.of(h.engine.calls);
    expect(
      callsAfterFailure.where((call) => call == 'inspectPaymentOperation'),
      hasLength(1),
    );
    final checkAgain = await h.repository.reconcilePaymentSubmission();
    final resume = await h.repository.resumePaymentSubmission();
    final sendAgain = await h.send();
    expect(
      (checkAgain as AppFailureResult<void>).failure.code,
      'payment_recovery_state_lost',
    );
    expect(
      (resume as AppFailureResult<void>).failure.code,
      'payment_recovery_state_lost',
    );
    expect(
      (sendAgain as AppFailureResult<WalletSendResult>)
          .failure
          .requiresReconciliation,
      isTrue,
    );
    expect(h.runtime.snapshot.failure?.code, 'payment_recovery_state_lost');
    expect(h.engine.calls, callsAfterFailure);
    expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
    expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
    expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
    expect(h.engine.legacySendPaymentCalls, 0);
    expect(h.paymentOperations.dispatchCount, 0);
    expect(h.store.documents[_id], document);
    expect(h.store.writes, hasLength(1));
  });
}
