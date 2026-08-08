import 'dart:math';

/// Bounded exponential backoff with symmetric jitter for idempotent requests.
final class RetryPolicy {
  RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 400),
    this.maximumDelay = const Duration(seconds: 5),
    this.jitterFactor = 0.2,
    Random? random,
    Future<void> Function(Duration delay)? sleep,
  }) : _random = random ?? Random(),
       _sleep = sleep ?? Future<void>.delayed {
    if (maxAttempts < 1 || maxAttempts > _maximumAttempts) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'Must be between 1 and $_maximumAttempts.',
      );
    }
    if (baseDelay.isNegative ||
        maximumDelay.isNegative ||
        baseDelay > maximumDelay ||
        maximumDelay > _maximumSupportedDelay) {
      throw ArgumentError(
        'Retry delays must be ordered, non-negative, and bounded.',
      );
    }
    if (!jitterFactor.isFinite || jitterFactor < 0 || jitterFactor > 1) {
      throw ArgumentError.value(
        jitterFactor,
        'jitterFactor',
        'Must be between 0 and 1.',
      );
    }
  }

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maximumDelay;
  final double jitterFactor;
  final Random _random;
  final Future<void> Function(Duration delay) _sleep;

  Duration delayFor(int completedAttempts) {
    final exponent = completedAttempts.clamp(0, _maximumExponent);
    final unboundedMs = baseDelay.inMilliseconds * (1 << exponent);
    final boundedMs = min(unboundedMs, maximumDelay.inMilliseconds);
    final jitterRange = (boundedMs * jitterFactor).round();
    if (jitterRange == 0) return Duration(milliseconds: boundedMs);
    final jitter = ((_random.nextDouble() * 2 - 1) * jitterRange).round();
    return Duration(milliseconds: max(0, boundedMs + jitter));
  }

  Future<void> wait(Duration delay) => _sleep(delay);

  static const _maximumAttempts = 10;
  static const _maximumExponent = 30;
  static const _maximumSupportedDelay = Duration(minutes: 5);
}
