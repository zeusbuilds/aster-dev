import '../errors/errors.dart';

/// A fail-closed boundary for secret material, retained for existing callers.
///
/// Recovery phrases must be recorded offline. A process-owned expiry timer
/// cannot guarantee removal from clipboard history or after app termination.
abstract interface class SensitiveClipboardService {
  Future<AppResult<void>> copySensitive(
    String text, {
    Duration clearAfter = PlatformSensitiveClipboardService.defaultLifetime,
  });
  Future<AppResult<void>> clearSensitive();
  Future<void> dispose();
}

/// Secret copying is unavailable on every supported release platform.
///
/// No clipboard platform channel is invoked and no supplied text is retained.
/// Enabling this later requires a separately reviewed native security policy.
final class PlatformSensitiveClipboardService
    implements SensitiveClipboardService {
  const PlatformSensitiveClipboardService();

  static const defaultLifetime = Duration(minutes: 1);

  @override
  Future<AppResult<void>> copySensitive(
    String text, {
    Duration clearAfter = defaultLifetime,
  }) async => const AppResult<void>.failure(
    AppFailure(
      code: 'sensitive_clipboard_disabled',
      kind: AppFailureKind.unsupported,
      userMessage: 'Write your recovery phrase down and keep it offline.',
      retryable: false,
    ),
  );

  @override
  Future<AppResult<void>> clearSensitive() async =>
      const AppResult<void>.success(null);

  @override
  Future<void> dispose() async {}
}
