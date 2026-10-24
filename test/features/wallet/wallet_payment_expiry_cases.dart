part of 'wallet_payment_submissions_test.dart';

void _expiryRecoveryCases() {
  Future<AppResult<WalletSendResult>> sendExpiredRgb(_Harness h) async {
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
    h.engine.commitPaymentOperationResult = WalletPaymentRecoveryStatus(
      phase: WalletPaymentRecoveryPhase.prepared,
      endAuthorized: false,
      referenceId: _txid,
      batchTransferIndex: 42,
      failureCode: 'invoice_expired',
    );
    return h.repository.sendPayment(
      target: WalletPaymentTarget.usdtOnchain,
      destination: 'rgb:expired-during-native-preparation',
      amountUnits: 20000,
      reviewedFeeRate: h.fee,
      rgbRecipientType: RgbRecipientType.blind,
    );
  }

  test('RGB expiry after prepare requires native cancellation before reopening mutations', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    final result = await sendExpiredRgb(h);
    final failure = (result as AppFailureResult<WalletSendResult>).failure;
    expect(failure.code, 'payment_request_expired');
    expect(failure.outcomeUnknown, isFalse);
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    expect((jsonDecode(h.store.documents[_id]!) as Map)['phase'], 'rejected');
    expect(h.paymentOperations.dispatchCount, 0);
    expect(h.paymentOperations.commitAttemptCount, 0);
    expect(h.engine.legacySendPaymentCalls, 0);
    expect(h.engine.calls.where((call) => call.endsWith('PaymentOperation')), [
      'preparePaymentOperation',
      'commitPaymentOperation',
      'cancelPaymentOperation',
    ]);
    await h.restart();
    expect(await h.send(), isA<AppSuccess<WalletSendResult>>());
    expect(h.paymentOperations.dispatchCount, 1);
  });

  test('lost expiry cancellation response stays fenced until explicit certificate recovery after restart', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    h.engine.cancelPaymentOperationReplyError = StateError(
      'Lost cancellation reply',
    );
    _expectPending(await sendExpiredRgb(h));
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
    expect((jsonDecode(h.store.documents[_id]!) as Map)['phase'], 'submitting');
    expect(h.paymentOperations.dispatchCount, 0);
    _expectPending(await h.send());
    expect(
      h.engine.calls.where((call) => call == 'cancelPaymentOperation'),
      hasLength(1),
    );
    await h.restart();
    expect(
      await h.repository.reconcilePaymentSubmission(),
      isA<AppSuccess<void>>(),
    );
    expect((jsonDecode(h.store.documents[_id]!) as Map)['phase'], 'rejected');
    expect(h.runtime.snapshot.phase, WalletRuntimePhase.active);
    expect(h.engine.calls, isNot(contains('preparePaymentOperation')));
    expect(h.engine.calls, isNot(contains('commitPaymentOperation')));
    expect(h.engine.calls, isNot(contains('cancelPaymentOperation')));
    expect(h.paymentOperations.dispatchCount, 0);
  });

  test('contradictory expiry cancellation cannot become a safe-rejection certificate', () async {
    for (final phase in [
      WalletPaymentRecoveryPhase.accepted,
      WalletPaymentRecoveryPhase.rejected,
    ]) {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.engine.cancelPaymentOperationResult = WalletPaymentRecoveryStatus(
        phase: phase,
        endAuthorized: true,
        referenceId: _txid,
        batchTransferIndex: 42,
      );
      _expectPending(await sendExpiredRgb(h));
      expect(h.runtime.snapshot.phase, WalletRuntimePhase.failed);
      expect(
        (jsonDecode(h.store.documents[_id]!) as Map)['phase'],
        'submitting',
      );
      expect(h.store.writes, hasLength(2));
      expect(h.paymentOperations.dispatchCount, 0);
      _expectPending(await h.send());
      expect(
        h.engine.calls.where((call) => call == 'preparePaymentOperation'),
        hasLength(1),
      );
      expect(
        h.engine.calls.where((call) => call == 'commitPaymentOperation'),
        hasLength(1),
      );
      expect(
        h.engine.calls.where((call) => call == 'cancelPaymentOperation'),
        hasLength(1),
      );
    }
  });
}
