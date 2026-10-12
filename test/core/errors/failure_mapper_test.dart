import 'dart:io';

import 'package:aster/core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

void main() {
  test('retains redacted SDK metadata without retaining its message', () {
    const secret = 'seed invoice token must not leak';
    final failure = FailureMapper.from(
      const NetworkError(secret),
      StackTrace.current,
    );

    expect(failure.kind, AppFailureKind.connectivity);
    expect(failure.retryable, isTrue);
    expect(
      failure.cause,
      const FailureDiagnostic(
        sourceType: 'NetworkError',
        sourceCode: 'NETWORK_ERROR',
      ),
    );
    expect(failure.userMessage, isNot(contains(secret)));
    expect(failure.toString(), isNot(contains(secret)));
    expect(failure.cause.toString(), isNot(contains(secret)));
  });

  test('maps native protocol errors to a stable support code', () {
    final failure = FailureMapper.from(
      const NativeProtocolException('raw native payload', field: 'balance'),
      StackTrace.current,
    );

    expect(failure.code, 'native_protocol_error');
    expect(failure.kind, AppFailureKind.protocol);
    expect(failure.userMessage, isNot(contains('raw native payload')));
  });

  test('classifies invalid build configuration separately from data', () {
    final failure = FailureMapper.from(
      const AppConfigurationException(),
      StackTrace.current,
    );

    expect(failure.code, 'app_configuration_invalid');
    expect(failure.kind, AppFailureKind.configuration);
    expect(failure.retryable, isFalse);
  });

  test('classifies malformed persisted records as storage corruption', () {
    final failure = FailureMapper.from(
      const StoredDataCorruptionException(),
      StackTrace.current,
    );

    expect(failure.code, 'stored_data_invalid');
    expect(failure.kind, AppFailureKind.storage);
    expect(failure.retryable, isFalse);
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isFalse);
  });

  test('marks an unconfirmed durable replacement as outcome unknown', () {
    final failure = FailureMapper.from(
      DurableStorageCommitException([StateError('injected failure')]),
      StackTrace.current,
    );

    expect(failure.code, 'durable_storage_commit_unknown');
    expect(failure.kind, AppFailureKind.storage);
    expect(failure.retryable, isFalse);
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isTrue);
    expect(failure.userMessage, isNot(contains('injected failure')));
  });

  test('requires reconciliation after a wallet filesystem failure', () {
    final failure = FailureMapper.from(
      const FileSystemException('private filesystem detail', '/secret/path'),
      StackTrace.current,
    );

    expect(failure.code, 'wallet_filesystem_failed');
    expect(failure.kind, AppFailureKind.storage);
    expect(failure.retryable, isFalse);
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isFalse);
    expect(failure.userMessage, isNot(contains('/secret/path')));
    expect(failure.cause.toString(), isNot(contains('/secret/path')));
  });

  test('classifies generic malformed external data as protocol failure', () {
    final failure = FailureMapper.from(
      const FormatException('untrusted payload'),
      StackTrace.current,
    );

    expect(failure.code, 'data_format_invalid');
    expect(failure.kind, AppFailureKind.protocol);
    expect(failure.retryable, isTrue);
    expect(failure.userMessage, isNot(contains('untrusted payload')));
  });

  test('does not misclassify internal argument errors as user input', () {
    final failure = FailureMapper.from(
      ArgumentError('internal invariant'),
      StackTrace.current,
    );

    expect(failure.code, 'internal_contract_violation');
    expect(failure.kind, AppFailureKind.unknown);
    expect(failure.retryable, isFalse);
    expect(failure.userMessage, isNot(contains('internal invariant')));
  });

  test('does not misclassify generic state faults as retryable conflicts', () {
    final failure = FailureMapper.from(
      StateError('internal state with private details'),
      StackTrace.current,
    );

    expect(failure.code, 'internal_state_violation');
    expect(failure.kind, AppFailureKind.unknown);
    expect(failure.retryable, isFalse);
    expect(failure.userMessage, isNot(contains('private details')));
  });

  test('rejects retryable failures whenever reconciliation is required', () {
    expect(
      () => AppFailure(
        code: 'unsafe_known_retry',
        kind: AppFailureKind.storage,
        userMessage: 'Reconcile before continuing.',
        retryable: true,
        requiresReconciliation: true,
      ),
      throwsAssertionError,
    );
    expect(
      () => AppFailure(
        code: 'unsafe_retry',
        kind: AppFailureKind.timeout,
        userMessage: 'Reconcile before continuing.',
        retryable: true,
        outcomeUnknown: true,
      ),
      throwsAssertionError,
    );

    const retained = AppFailure(
      code: 'known_retained_resources',
      kind: AppFailureKind.storage,
      userMessage: 'Reconcile before continuing.',
      retryable: false,
      requiresReconciliation: true,
    );
    const failure = AppFailure(
      code: 'safe_unknown_outcome',
      kind: AppFailureKind.timeout,
      userMessage: 'Reconcile before continuing.',
      retryable: false,
      outcomeUnknown: true,
    );
    expect(retained.requiresReconciliation, isTrue);
    expect(retained.outcomeUnknown, isFalse);
    expect(failure.retryable, isFalse);
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isTrue);
    expect(retained, isNot(failure));
  });

  test('preserves distinct LSP timeout and rate-limit semantics', () {
    final timeout = FailureMapper.from(
      const LspLiquidityTimeoutException(
        minMsat: 1000,
        elapsedMs: 5000,
        lastOutboundMsat: 0,
      ),
      StackTrace.current,
    );
    final rateLimit = FailureMapper.from(
      const LspError(
        endpoint: '/secret/account',
        status: 429,
        body: 'bearer token must not leak',
      ),
      StackTrace.current,
    );

    expect(timeout.code, 'lsp_liquidity_timeout');
    expect(timeout.kind, AppFailureKind.timeout);
    expect(timeout.retryable, isFalse);
    expect(timeout.requiresReconciliation, isTrue);
    expect(timeout.outcomeUnknown, isTrue);
    expect(rateLimit.code, 'lsp_rate_limited');
    expect(rateLimit.kind, AppFailureKind.rateLimited);
    expect(rateLimit.retryable, isTrue);
    expect(rateLimit.userMessage, isNot(contains('bearer token')));
    expect(rateLimit.toString(), isNot(contains('/secret/account')));
    expect(rateLimit.cause.toString(), isNot(contains('bearer token')));
    expect(rateLimit.cause.toString(), isNot(contains('/secret/account')));
  });

  test('does not retry business rejections or unverified LSP quotes', () {
    const secret = 'untrusted invoice password bearer secret';
    for (final error in <RgbSdkException>[
      const LnurlCallbackException(reason: secret),
      const LspQuoteMismatchException(reason: secret),
      const LspAddressQuoteVerificationException(reason: secret),
      const LspBridgeQuoteVerificationException(reason: secret),
      const LspNoPayableAssetException(address: secret),
      LspInsufficientAssetLiquidityException(requiredAmount: 1, candidates: []),
    ]) {
      final failure = FailureMapper.from(error, StackTrace.current);
      expect(failure.retryable, isFalse, reason: error.runtimeType.toString());
      expect(failure.kind, isNot(AppFailureKind.connectivity));
      expect(failure.userMessage, isNot(contains(secret)));
      expect(failure.toString(), isNot(contains(secret)));
      expect(failure.cause.toString(), isNot(contains(secret)));
    }
  });

  test('never recommends retry after an uncancellable native timeout', () {
    final failure = FailureMapper.from(
      const RlnOperationTimeoutException(
        operation: 'rlnSendPayment',
        timeout: Duration(minutes: 2),
      ),
      StackTrace.current,
    );

    expect(failure.code, 'wallet_operation_outcome_unknown');
    expect(failure.kind, AppFailureKind.timeout);
    expect(failure.retryable, isFalse);
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isTrue);
    expect(failure.userMessage, isNot(contains('rlnSendPayment')));
  });

  test('maps a redacted post-send marker to reconciliation-only failure', () {
    const diagnostic = FailureDiagnostic(
      sourceType: 'NativeProtocolException',
      sourceCode: 'NATIVE_PROTOCOL_ERROR',
      context: 'sendBtc.txid',
    );
    const marker = WalletMutationOutcomeUnknownException(diagnostic);

    final failure = FailureMapper.from(marker, StackTrace.current);

    expect(failure.code, 'payment_outcome_unknown');
    expect(failure.kind, AppFailureKind.protocol);
    expect(failure.retryable, isFalse);
    expect(failure.requiresReconciliation, isTrue);
    expect(failure.outcomeUnknown, isTrue);
    expect(failure.cause, diagnostic);
    expect(failure.userMessage, isNot(contains('sendBtc')));
    expect(marker.toString(), isNot(contains('sendBtc')));
  });

  test('does not collapse terminal or experimental SDK failures', () {
    final settlement = FailureMapper.from(
      const LspSettlementException(
        step: 'invoice',
        status: ReceiveStatuses.failed,
      ),
      StackTrace.current,
    );
    final experimental = FailureMapper.from(
      const ExperimentalCryptoException(
        'not production enabled',
        primitive: 'schnorr',
      ),
      StackTrace.current,
    );
    final node = FailureMapper.from(
      const RgbNodeError('native details must not leak'),
      StackTrace.current,
    );

    expect(settlement.code, 'lsp_settlement_failed');
    expect(settlement.retryable, isFalse);
    expect(experimental.kind, AppFailureKind.unsupported);
    expect(experimental.retryable, isFalse);
    expect(node.code, 'rgb_node_failed');
    expect(node.userMessage, isNot(contains('native details')));
  });
}
