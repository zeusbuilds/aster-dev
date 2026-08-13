import 'package:flutter/foundation.dart';

/// One validated Bitcoin/USD observation from the market-data provider.
@immutable
final class BitcoinPricePoint {
  BitcoinPricePoint({required this.timestamp, required this.usdCents}) {
    if (!timestamp.isUtc) {
      throw ArgumentError.value(timestamp, 'timestamp', 'Must be UTC.');
    }
    if (usdCents < 0 || usdCents > _maximumSignedInteger) {
      throw ArgumentError.value(
        usdCents,
        'usdCents',
        'Must be a non-negative signed 64-bit integer.',
      );
    }
  }

  /// UTC instant at which the provider observed this price.
  final DateTime timestamp;

  /// Price in integer US-dollar cents.
  final int usdCents;

  @override
  bool operator ==(Object other) =>
      other is BitcoinPricePoint &&
      other.timestamp == timestamp &&
      other.usdCents == usdCents;

  @override
  int get hashCode => Object.hash(timestamp, usdCents);
}

/// Provenance of the value rendered as the current Bitcoin market price.
enum BitcoinPriceSource {
  /// A dedicated provider spot-price response.
  spot,

  /// The newest validated history point when a current response was absent.
  historyFallback,
}

/// Validated market data suitable for rendering without synthetic fallbacks.
@immutable
final class BitcoinMarketSnapshot {
  BitcoinMarketSnapshot({
    required this.currentUsdCents,
    required this.currentObservedAt,
    required this.currentSource,
    required List<BitcoinPricePoint> history,
  }) : history = List<BitcoinPricePoint>.unmodifiable(history) {
    if (currentUsdCents < 0 || currentUsdCents > _maximumSignedInteger) {
      throw ArgumentError.value(
        currentUsdCents,
        'currentUsdCents',
        'Must be a non-negative signed 64-bit integer.',
      );
    }
    if (!currentObservedAt.isUtc) {
      throw ArgumentError.value(
        currentObservedAt,
        'currentObservedAt',
        'Must be UTC.',
      );
    }
    for (var index = 1; index < this.history.length; index += 1) {
      if (!this.history[index].timestamp.isAfter(
        this.history[index - 1].timestamp,
      )) {
        throw ArgumentError('Market history must be strictly chronological.');
      }
    }
  }

  /// Current Bitcoin price in integer US-dollar cents.
  final int currentUsdCents;

  /// UTC instant at which [currentUsdCents] was observed.
  final DateTime currentObservedAt;

  /// Provider path from which the current value was selected.
  final BitcoinPriceSource currentSource;

  /// Strictly chronological, immutable provider observations.
  final List<BitcoinPricePoint> history;

  /// Maximum age for presenting the current price as a live conversion.
  static const maximumCurrentAge = Duration(minutes: 30);

  /// Bounded provider/client clock skew accepted as a current observation.
  static const maximumFutureSkew = Duration(minutes: 5);

  /// First instant at which this snapshot must no longer be presented as live.
  DateTime get expiresAt => currentObservedAt.add(maximumCurrentAge);

  /// Whether the current observation is valid at the supplied instant.
  bool isCurrentAt(DateTime now) =>
      isObservationCurrentAt(observedAt: currentObservedAt, now: now);

  /// Applies the exact freshness and clock-skew policy used at every layer.
  static bool isObservationCurrentAt({
    required DateTime observedAt,
    required DateTime now,
  }) {
    final utcObservedAt = observedAt.toUtc();
    final utcNow = now.toUtc();
    return !utcObservedAt.isAfter(utcNow.add(maximumFutureSkew)) &&
        utcNow.isBefore(utcObservedAt.add(maximumCurrentAge));
  }

  /// Price change in basis points, where 100 basis points equals one percent.
  int? get changeBasisPoints {
    if (history.length < 2 || history.first.usdCents == 0) return null;
    final change =
        (BigInt.from(currentUsdCents - history.first.usdCents) *
            BigInt.from(10000)) ~/
        BigInt.from(history.first.usdCents);
    if (change < BigInt.from(-_maximumSignedInteger) ||
        change > BigInt.from(_maximumSignedInteger)) {
      return null;
    }
    return change.toInt();
  }

  @override
  bool operator ==(Object other) =>
      other is BitcoinMarketSnapshot &&
      other.currentUsdCents == currentUsdCents &&
      other.currentObservedAt == currentObservedAt &&
      other.currentSource == currentSource &&
      listEquals(other.history, history);

  @override
  int get hashCode => Object.hash(
    currentUsdCents,
    currentObservedAt,
    currentSource,
    Object.hashAll(history),
  );
}

const _maximumSignedInteger = 0x7fffffffffffffff;
