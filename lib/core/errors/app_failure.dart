import 'package:flutter/foundation.dart';

/// Stable failure categories used by repositories and ViewModels.
enum AppFailureKind {
  validation,
  authentication,
  configuration,
  connectivity,
  timeout,
  rateLimited,
  unavailable,
  conflict,
  notFound,
  storage,
  protocol,
  unsupported,
  cancelled,
  unknown,
}

/// A redacted application failure that is safe to hand to presentation code.
///
/// [cause] and [stackTrace] are retained for an injected diagnostics sink, but
/// must never be rendered or logged directly. User-facing code uses
/// [userMessage] and may offer retry only when [retryable] is true.
@immutable
final class AppFailure {
  const AppFailure({
    required this.code,
    required this.kind,
    required this.userMessage,
    required bool retryable,
    this.outcomeUnknown = false,
    this.retryAfter,
    this.cause,
    this.stackTrace,
  }) : retryable = retryable && !outcomeUnknown,
       assert(
         !outcomeUnknown || !retryable,
         'An outcome-unknown mutation cannot be safely retryable.',
       );

  /// Stable, non-secret support code.
  final String code;

  final AppFailureKind kind;
  final String userMessage;

  /// Whether presentation may safely offer the same operation again.
  ///
  /// Unknown mutation outcomes always force this to false, including in
  /// optimized builds where assertions are disabled.
  final bool retryable;

  /// Whether an interrupted mutation may still have completed underneath.
  ///
  /// Presentation must direct the user to reconcile wallet state before
  /// offering another attempt when this is true.
  final bool outcomeUnknown;
  final Duration? retryAfter;

  /// Internal diagnostic context. Infrastructure mappers store only redacted
  /// metadata or nested [AppFailure] values here, never raw payloads.
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'AppFailure($code, ${kind.name})';

  @override
  bool operator ==(Object other) =>
      other is AppFailure &&
      other.code == code &&
      other.kind == kind &&
      other.userMessage == userMessage &&
      other.retryable == retryable &&
      other.outcomeUnknown == outcomeUnknown &&
      other.retryAfter == retryAfter;

  @override
  int get hashCode => Object.hash(
    code,
    kind,
    userMessage,
    retryable,
    outcomeUnknown,
    retryAfter,
  );
}

/// Non-secret metadata retained from an infrastructure or SDK exception.
///
/// Messages, response bodies, endpoints, wallet paths, and operation inputs are
/// deliberately excluded. Diagnostics may use these bounded fields together
/// with [AppFailure.code] and a separately governed stack trace.
@immutable
final class FailureDiagnostic {
  const FailureDiagnostic({
    required this.sourceType,
    this.sourceCode,
    this.statusCode,
    this.context,
  });

  final String sourceType;
  final String? sourceCode;
  final int? statusCode;
  final String? context;

  @override
  String toString() => 'FailureDiagnostic($sourceType)';

  @override
  bool operator ==(Object other) =>
      other is FailureDiagnostic &&
      other.sourceType == sourceType &&
      other.sourceCode == sourceCode &&
      other.statusCode == statusCode &&
      other.context == context;

  @override
  int get hashCode => Object.hash(sourceType, sourceCode, statusCode, context);
}

/// Redacted marker for a payment whose native mutation outcome is ambiguous.
///
/// The original exception is reduced to [diagnostic] before this marker crosses
/// the wallet adapter boundary. Presentation must reconcile wallet activity and
/// must not offer the same route-scoped payment again.
final class WalletMutationOutcomeUnknownException implements Exception {
  const WalletMutationOutcomeUnknownException(this.diagnostic);

  final FailureDiagnostic diagnostic;

  @override
  String toString() => 'WalletMutationOutcomeUnknownException';
}

/// Non-secret marker for invalid compile-time or runtime service settings.
final class AppConfigurationException implements Exception {
  const AppConfigurationException();

  @override
  String toString() => 'AppConfigurationException';
}

/// Non-secret marker for malformed persisted application data.
final class StoredDataCorruptionException implements Exception {
  const StoredDataCorruptionException();

  @override
  String toString() => 'StoredDataCorruptionException';
}

/// A durable replacement may have committed despite an I/O failure.
///
/// Callers must preserve all involved resources and reconcile on the next
/// bootstrap rather than guessing whether the old or new document is durable.
final class DurableStorageCommitException implements Exception {
  DurableStorageCommitException(List<Object> causes)
    : causes = List<Object>.unmodifiable(causes);

  final List<Object> causes;

  @override
  String toString() => 'DurableStorageCommitException';
}

/// Marker for metadata from the pre-native wallet architecture.
///
/// Those records contain no credential ownership proof, so callers must ask
/// the user to restore from their recovery phrase rather than inventing a
/// migration or silently discarding the record.
final class LegacyWalletDataException implements Exception {
  const LegacyWalletDataException();

  @override
  String toString() => 'LegacyWalletDataException';
}
