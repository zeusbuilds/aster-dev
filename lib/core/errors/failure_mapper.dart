import 'dart:async';
import 'dart:io';

import 'package:rgb_sdk_flutter/rgb_sdk_flutter.dart';

import '../platform/local_network_access.dart';
import 'app_failure.dart';

/// Converts infrastructure and SDK errors into stable, redacted app failures.
abstract final class FailureMapper {
  /// Reduces an exception to bounded metadata that cannot retain payload text.
  static FailureDiagnostic diagnosticCause(Object error) {
    if (error is WalletPaymentRejectedBeforeDispatchException) {
      return FailureDiagnostic(
        sourceType: 'WalletPaymentRejectedBeforeDispatchException',
        sourceCode: _safeToken(error.failure.code),
      );
    }
    if (error is WalletMutationOutcomeUnknownException) {
      return error.diagnostic;
    }
    if (error is AppFailureException) {
      return FailureDiagnostic(
        sourceType: 'AppFailureException',
        sourceCode: _safeToken(error.failure.code),
      );
    }
    if (error is RgbSdkException) {
      final context = switch (error) {
        RlnOperationTimeoutException(:final operation) => operation,
        NativeProtocolException(:final field) => field,
        WalletValidationException(:final field) => field,
        UnsupportedWalletFeatureException(:final feature) => feature,
        ExperimentalCryptoException(:final primitive) => primitive,
        _ => error.operation,
      };
      return FailureDiagnostic(
        sourceType:
            _safeToken(error.runtimeType.toString()) ?? 'RgbSdkException',
        sourceCode: _safeToken(error.code),
        statusCode: error.statusCode,
        context: _safeToken(context),
      );
    }
    if (error is StorageOperationException) {
      return FailureDiagnostic(
        sourceType: 'StorageOperationException',
        context: _safeToken(error.operation),
      );
    }
    return FailureDiagnostic(
      sourceType: _safeToken(error.runtimeType.toString()) ?? 'Exception',
    );
  }

  static AppFailure from(
    Object error,
    StackTrace stackTrace, {
    String fallbackCode = 'unexpected_error',
  }) {
    if (error is WalletPaymentRejectedBeforeDispatchException) {
      return error.failure;
    }
    if (error is AppFailureException) return error.failure;
    if (error is LocalNetworkAccessException) {
      final denied = error.reason == LocalNetworkAccessFailure.denied;
      return _failure(
        code: denied
            ? 'local_network_access_denied'
            : 'local_network_access_unavailable',
        kind: denied
            ? AppFailureKind.authentication
            : AppFailureKind.unavailable,
        message: denied
            ? 'Allow local network access in Android settings to connect to '
                  'your configured wallet services.'
            : 'Local network access could not be checked. Try again.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is AppConfigurationException) {
      return _failure(
        code: 'app_configuration_invalid',
        kind: AppFailureKind.configuration,
        message: 'Wallet services are not configured for this network.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is StoredDataCorruptionException) {
      return _failure(
        code: 'stored_data_invalid',
        kind: AppFailureKind.storage,
        message: 'Stored wallet information could not be read safely.',
        requiresReconciliation: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is DurableStorageCommitException) {
      return _failure(
        code: 'durable_storage_commit_unknown',
        kind: AppFailureKind.storage,
        message:
            'A wallet change could not be confirmed safely. Restart the app '
            'before continuing.',
        outcomeUnknown: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is WalletMutationOutcomeUnknownException) {
      return _failure(
        code: 'payment_outcome_unknown',
        kind: AppFailureKind.protocol,
        message:
            'The payment could not be confirmed. Check Activity before '
            'sending again.',
        outcomeUnknown: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is StorageOperationException) {
      return _failure(
        code: 'storage_operation_failed',
        kind: AppFailureKind.storage,
        message: 'Wallet settings could not be saved safely.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is FileSystemException) {
      return _failure(
        code: 'wallet_filesystem_failed',
        kind: AppFailureKind.storage,
        message: 'Local wallet data could not be accessed safely.',
        requiresReconciliation: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is LspAmountOutOfRangeException) {
      return _failure(
        code: 'lsp_amount_out_of_range',
        kind: AppFailureKind.validation,
        message: 'Enter an amount supported by the Lightning service.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is WalletValidationException || error is ValidationError) {
      return _failure(
        code: 'wallet_validation',
        kind: AppFailureKind.validation,
        message: 'Check the entered information and try again.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is BadRequestError) {
      return _failure(
        code: 'invalid_request',
        kind: AppFailureKind.validation,
        message: 'Check the entered information and try again.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is LspTransportPolicyException) {
      return _failure(
        code: 'lsp_transport_invalid',
        kind: AppFailureKind.configuration,
        message: 'The Lightning service transport is not configured safely.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is ConfigurationError) {
      return _failure(
        code: 'wallet_configuration',
        kind: AppFailureKind.configuration,
        message: 'Wallet services are not configured for this network.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is LspChannelTimeoutException) {
      return _failure(
        code: 'lsp_channel_timeout',
        kind: AppFailureKind.timeout,
        message:
            'The Lightning channel was not confirmed in time. Check its '
            'status before trying again.',
        outcomeUnknown: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is LspLiquidityTimeoutException) {
      return _failure(
        code: 'lsp_liquidity_timeout',
        kind: AppFailureKind.timeout,
        message:
            'Lightning liquidity was not confirmed in time. Check its status '
            'before trying again.',
        outcomeUnknown: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is RlnOperationTimeoutException) {
      return _failure(
        code: 'wallet_operation_outcome_unknown',
        kind: AppFailureKind.timeout,
        message:
            'The wallet did not confirm the operation in time. Check its '
            'status before trying again.',
        outcomeUnknown: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is TimeoutException) {
      return _failure(
        code: 'operation_timeout',
        kind: AppFailureKind.timeout,
        message: 'The operation took too long. Try again.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is LspError) {
      return _fromLsp(error, stackTrace);
    }
    if (error is LspQuoteMismatchException ||
        error is LspAddressQuoteVerificationException ||
        error is LspBridgeQuoteVerificationException) {
      return _failure(
        code: 'lsp_quote_verification_failed',
        kind: AppFailureKind.protocol,
        message: 'The payment quote could not be verified safely.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is LspInsufficientAssetLiquidityException ||
        error is LspNoPayableAssetException) {
      return _failure(
        code: 'lsp_payment_unavailable',
        kind: AppFailureKind.validation,
        message: 'This payment cannot be made with the available assets and liquidity.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is LnurlCallbackException) {
      return _failure(
        code: 'lnurl_invoice_rejected',
        kind: AppFailureKind.validation,
        message: 'The payment provider could not issue an invoice.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is NetworkError ||
        error is SocketException ||
        error is HttpException) {
      return _failure(
        code: 'network_unavailable',
        kind: AppFailureKind.connectivity,
        message: 'Check your connection and try again.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is NotFoundError) {
      return _failure(
        code: 'wallet_data_not_found',
        kind: AppFailureKind.notFound,
        message: 'The requested wallet data is no longer available.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is ConflictError) {
      return _failure(
        code: 'wallet_conflict',
        kind: AppFailureKind.conflict,
        message: 'The wallet changed while this action was running. Try again.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is StateError) {
      return _failure(
        code: 'internal_state_violation',
        kind: AppFailureKind.unknown,
        message: 'Something went wrong. Restart the app and try again.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is ArgumentError) {
      return _failure(
        code: 'internal_contract_violation',
        kind: AppFailureKind.unknown,
        message: 'Something went wrong. Restart the app and try again.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is UnsupportedWalletFeatureException) {
      return _failure(
        code: 'wallet_feature_unsupported',
        kind: AppFailureKind.unsupported,
        message: 'This wallet feature is not available yet.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is ExperimentalCryptoException) {
      return _failure(
        code: 'wallet_crypto_experimental',
        kind: AppFailureKind.unsupported,
        message: 'This cryptographic operation is not production enabled.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is CryptoError) {
      return _failure(
        code: 'wallet_crypto_failed',
        kind: AppFailureKind.unavailable,
        message: 'The cryptographic operation could not be completed.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is OperationCancelledError) {
      return _failure(
        code: 'operation_cancelled',
        kind: AppFailureKind.cancelled,
        message: 'The operation was cancelled.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is NativeProtocolException) {
      return _failure(
        code: 'native_protocol_error',
        kind: AppFailureKind.protocol,
        message: 'The wallet returned an unexpected response. Try again.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is LspSettlementException) {
      return _failure(
        code: 'lsp_settlement_failed',
        kind: AppFailureKind.conflict,
        message: 'The Lightning operation did not settle successfully.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is RgbNodeError) {
      return _failure(
        code: 'rgb_node_failed',
        kind: AppFailureKind.unavailable,
        message: 'The wallet node could not complete the operation.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is FormatException) {
      return _failure(
        code: 'data_format_invalid',
        kind: AppFailureKind.protocol,
        message: 'Unexpected data was received. Try again.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (error is RgbSdkException || error is WalletException) {
      return _failure(
        code: 'wallet_operation_failed',
        kind: AppFailureKind.unavailable,
        message: 'The wallet operation could not be completed.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return _failure(
      code: fallbackCode,
      kind: AppFailureKind.unknown,
      message: 'Something went wrong. Try again.',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static AppFailure _fromLsp(LspError error, StackTrace stackTrace) {
    final status = error.status;
    if (status == 401 || status == 403) {
      return _failure(
        code: 'lsp_unauthorized',
        kind: AppFailureKind.authentication,
        message: 'The Lightning service request was not authorized.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (status == 404) {
      return _failure(
        code: 'lsp_not_found',
        kind: AppFailureKind.notFound,
        message: 'The requested Lightning service is unavailable.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (status == 408) {
      return _failure(
        code: 'lsp_timeout',
        kind: AppFailureKind.timeout,
        message: 'The Lightning service took too long to respond.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (status == 409) {
      return _failure(
        code: 'lsp_conflict',
        kind: AppFailureKind.conflict,
        message: 'The Lightning request conflicts with the current state.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (status == 429) {
      return _failure(
        code: 'lsp_rate_limited',
        kind: AppFailureKind.rateLimited,
        message: 'Too many Lightning requests. Try again shortly.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (status >= 500) {
      return _failure(
        code: 'lsp_unavailable',
        kind: AppFailureKind.unavailable,
        message: 'The Lightning service is temporarily unavailable.',
        retryable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (status >= 400) {
      return _failure(
        code: 'lsp_request_rejected',
        kind: AppFailureKind.validation,
        message: 'The Lightning service could not process this request.',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return _failure(
      code: 'lsp_unreachable',
      kind: AppFailureKind.connectivity,
      message: 'The Lightning service could not be reached.',
      retryable: true,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static AppFailure _failure({
    required String code,
    required AppFailureKind kind,
    required String message,
    required Object error,
    required StackTrace stackTrace,
    bool retryable = false,
    bool requiresReconciliation = false,
    bool outcomeUnknown = false,
  }) {
    return AppFailure(
      code: code,
      kind: kind,
      userMessage: message,
      retryable: retryable,
      requiresReconciliation: requiresReconciliation,
      outcomeUnknown: outcomeUnknown,
      cause: diagnosticCause(error),
      stackTrace: stackTrace,
    );
  }

  static String? _safeToken(String? value) {
    if (value == null || !RegExp(r'^[A-Za-z0-9_.:-]{1,80}$').hasMatch(value)) {
      return null;
    }
    return value;
  }
}

/// Internal exception wrapper for infrastructure that already classified a
/// failure and must preserve it across an asynchronous boundary.
final class AppFailureException implements Exception {
  const AppFailureException(this.failure);

  final AppFailure failure;

  @override
  String toString() => 'AppFailureException(${failure.code})';
}

/// Non-secret storage adapter failure. Keys and values are deliberately absent.
final class StorageOperationException implements Exception {
  const StorageOperationException(
    this.operation, {
    this.cause,
    this.stackTrace,
  });

  final String operation;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'StorageOperationException($operation)';
}
