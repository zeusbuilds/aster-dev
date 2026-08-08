import 'dart:async';

/// Cooperative cancellation signal for one app-owned network operation.
///
/// Cancellation is idempotent. Network adapters must translate it to a typed
/// cancelled result and must not schedule subsequent retries.
final class NetworkCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
