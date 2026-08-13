import '../../../../core/errors/errors.dart';

/// Narrow repository contract used by the app-lifecycle coordinator.
///
/// Implementations must serialize these operations with every other native
/// wallet command and must not return before an uncancellable native call has
/// settled.
abstract interface class WalletLifecycleRepository {
  /// Suspends the active native wallet, or succeeds when none is active.
  Future<AppResult<void>> suspend();

  /// Restores the durable active wallet after the application returns.
  Future<AppResult<void>> resume();

  /// Permanently releases the process-owned native wallet resources.
  Future<AppResult<void>> dispose();
}
