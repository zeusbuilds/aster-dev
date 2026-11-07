part of 'wallet_payment_submissions_test.dart';

void _revocationCases() {
  Future<WalletPaymentSubmission> unknownRgb(_Harness h) async {
    h.engine
      ..sentPayment = null
      ..sendPaymentError = StateError('Lost reply after native RGB handoff');
    _expectPending(
      await h.repository.sendPayment(
        target: WalletPaymentTarget.usdtOnchain,
        destination: 'rgb:exact-witness-invoice',
        amountUnits: 50,
        reviewedFeeRate: h.fee,
        rgbRecipientType: RgbRecipientType.witness,
        witnessBitcoinAmountSats: rgbWitnessRecipientSats,
      ),
    );
    return (await h.repository.paymentSubmissionStatus()
            as AppSuccess<WalletPaymentSubmission?>)
        .value!;
  }

  test(
    'revocation eligibility and Check never cancel an authorized handoff',
    () async {
      final h = await _Harness.create(revocableRgb: true);
      addTearDown(h.dispose);
      final expected = await unknownRgb(h);
      expect(
        (await h.repository.canRevokePaymentSubmission(
          expected,
        ) as AppSuccess<bool>).value,
        isTrue,
      );
      _expectPending(await h.repository.reconcilePaymentSubmission());
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expect(h.engine.calls, isNot(contains('revokeDispatchedRgbOperation')));
      expect(
        h.engine.calls.where((call) => call == 'commitPaymentOperation'),
        hasLength(1),
      );
    },
  );

  test(
    'Check cannot revoke if dispatch races a precommit observation',
    () async {
      final h = await _Harness.create(revocableRgb: true);
      addTearDown(h.dispose);
      await unknownRgb(h);
      h.engine.inspectPaymentOperationResult = WalletPaymentRecoveryStatus(
        phase: WalletPaymentRecoveryPhase.prepared,
        endAuthorized: false,
        referenceId: _txid,
        batchTransferIndex: 1,
      );
      _expectPending(await h.repository.reconcilePaymentSubmission());
      expect(
        h.engine.calls.where((call) => call == 'cancelPaymentOperation'),
        hasLength(1),
      );
      expect(h.engine.calls, isNot(contains('revokeDispatchedRgbOperation')));
      expect(
        h.engine.calls.where((call) => call == 'commitPaymentOperation'),
        hasLength(1),
      );
    },
  );

  test('legacy capability cannot invoke dispatched cancellation', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final expected = await unknownRgb(h);
    expect(
      (await h.repository.canRevokePaymentSubmission(
        expected,
      ) as AppSuccess<bool>).value,
      isFalse,
    );
    expect(
      (await h.repository.revokePaymentSubmission(
        expected,
      ) as AppFailureResult<void>).failure.code,
      'payment_cancellation_unavailable',
    );
    expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
    expect(h.engine.calls, isNot(contains('revokeDispatchedRgbOperation')));
    _expectPending(await h.send());
  });

  test('signed native cancellation certificate persists before reopening mutations', () async {
    final h = await _Harness.create(revocableRgb: true);
    addTearDown(h.dispose);
    final expected = await unknownRgb(h);
    (h.engine as FakeRevocableWalletEngine).revocationResult =
        const WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.rejected,
          endAuthorized: false,
          failureCode: 'cancelled',
        );
    expect(
      await h.repository.revokePaymentSubmission(expected),
      isA<AppSuccess<void>>(),
    );
    final record =
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value!;
    expect(record.outcome, WalletPaymentSubmissionOutcome.notSubmitted);
    expect(record.requiresReconciliation, isFalse);
    expect(record.recoveryRequest, expected.recoveryRequest);
    expect(
      h.engine.calls.where((call) => call == 'revokeDispatchedRgbOperation'),
      hasLength(1),
    );
    expect(
      h.engine.calls.where((call) => call == 'commitPaymentOperation'),
      hasLength(1),
    );
    expect(
      (await h.repository.canRevokePaymentSubmission(
        expected,
      ) as AppSuccess<bool>).value,
      isFalse,
    );
    await h.restart();
    expect(
      (await h.repository.paymentSubmissionStatus()
              as AppSuccess<WalletPaymentSubmission?>)
          .value
          ?.outcome,
      WalletPaymentSubmissionOutcome.notSubmitted,
    );
  });

  test(
    'already accepted outcome wins over cancellation without another commit',
    () async {
      final h = await _Harness.create(revocableRgb: true);
      addTearDown(h.dispose);
      final expected = await unknownRgb(h);
      (h.engine as FakeRevocableWalletEngine).revocationResult =
          WalletPaymentRecoveryStatus(
            phase: WalletPaymentRecoveryPhase.accepted,
            endAuthorized: true,
            referenceId: _txid,
            batchTransferIndex: 1,
          );
      expect(
        await h.repository.revokePaymentSubmission(expected),
        isA<AppSuccess<void>>(),
      );
      final record =
          (await h.repository.paymentSubmissionStatus()
                  as AppSuccess<WalletPaymentSubmission?>)
              .value!;
      expect(record.outcome, WalletPaymentSubmissionOutcome.accepted);
      expect(record.result?.amount.units, 50);
      expect(h.store.receiptDocuments[_id], hasLength(1));
      expect(
        h.engine.calls.where((call) => call == 'commitPaymentOperation'),
        hasLength(1),
      );
    },
  );

  test('unknown, released, malformed rejection and unavailable revocation keep the fence', () async {
    for (final response in [
      const WalletPaymentRecoveryStatus(
        phase: WalletPaymentRecoveryPhase.committing,
        endAuthorized: true,
        failureCode: 'cancellation_unavailable',
      ),
      const WalletPaymentRecoveryStatus(
        phase: WalletPaymentRecoveryPhase.committing,
        endAuthorized: true,
        failureCode: 'cancellation_not_safe',
      ),
      const WalletPaymentRecoveryStatus(
        phase: WalletPaymentRecoveryPhase.rejected,
        endAuthorized: false,
        failureCode: 'released',
      ),
      const WalletPaymentRecoveryStatus(
        phase: WalletPaymentRecoveryPhase.rejected,
        endAuthorized: true,
        failureCode: 'cancelled',
      ),
    ]) {
      final h = await _Harness.create(revocableRgb: true);
      addTearDown(h.dispose);
      final expected = await unknownRgb(h);
      (h.engine as FakeRevocableWalletEngine).revocationResult = response;
      _expectPending(await h.repository.revokePaymentSubmission(expected));
      _expectPending(await h.send());
      expect(
        (await h.repository.paymentSubmissionStatus()
                as AppSuccess<WalletPaymentSubmission?>)
            .value
            ?.outcome,
        WalletPaymentSubmissionOutcome.unknown,
      );
      expect(
        h.engine.calls.where((call) => call == 'commitPaymentOperation'),
        hasLength(1),
      );
    }
  });

  test('certificate acknowledgement failure stays fenced and Check completes without a second Cancel', () async {
    final h = await _Harness.create(revocableRgb: true);
    addTearDown(h.dispose);
    final expected = await unknownRgb(h);
    (h.engine as FakeRevocableWalletEngine).revocationResult =
        const WalletPaymentRecoveryStatus(
          phase: WalletPaymentRecoveryPhase.rejected,
          endAuthorized: false,
          failureCode: 'cancelled',
        );
    h.store.failWriteNumber = h.store.writes.length + 1;
    expect(
      await h.repository.revokePaymentSubmission(expected),
      isA<AppFailureResult<void>>(),
    );
    _expectPending(await h.send());
    h.store.failWriteNumber = null;
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect(
      h.engine.calls.where((call) => call == 'revokeDispatchedRgbOperation'),
      hasLength(1),
    );
    expect(
      h.engine.calls.where((call) => call == 'commitPaymentOperation'),
      hasLength(1),
    );
  });

  test(
    'stale details request cannot revoke a different immutable command',
    () async {
      final h = await _Harness.create(revocableRgb: true);
      addTearDown(h.dispose);
      final expected = await unknownRgb(h);
      final stale = WalletPaymentSubmission(
        id: expected.id,
        walletId: expected.walletId,
        command: expected.command,
        submittedAt: expected.submittedAt,
        phase: expected.phase,
        recoveryRequest: '${expected.recoveryRequest} ',
      );
      expect(
        (await h.repository.canRevokePaymentSubmission(
          stale,
        ) as AppSuccess<bool>).value,
        isFalse,
      );
      expect(
        (await h.repository.revokePaymentSubmission(
          stale,
        ) as AppFailureResult<void>).failure.code,
        'payment_cancellation_context_changed',
      );
      expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
      expect(h.engine.calls, isNot(contains('revokeDispatchedRgbOperation')));
    },
  );

  test(
    'queued duplicate revocation cannot repeat native cancellation',
    () async {
      final h = await _Harness.create(revocableRgb: true);
      addTearDown(h.dispose);
      final expected = await unknownRgb(h);
      final engine = h.engine as FakeRevocableWalletEngine;
      engine.revocationGate = Completer<void>();
      engine.revocationResult = const WalletPaymentRecoveryStatus(
        phase: WalletPaymentRecoveryPhase.rejected,
        endAuthorized: false,
        failureCode: 'cancelled',
      );
      final first = h.repository.revokePaymentSubmission(expected);
      final second = h.repository.revokePaymentSubmission(expected);
      for (
        var n = 0;
        n < 30 && !engine.calls.contains('revocation:start');
        n += 1
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      engine.revocationGate!.complete();
      await first;
      await second;
      expect(
        engine.calls.where((call) => call == 'revokeDispatchedRgbOperation'),
        hasLength(1),
      );
      expect(
        engine.calls.where((call) => call == 'commitPaymentOperation'),
        hasLength(1),
      );
    },
  );
}
