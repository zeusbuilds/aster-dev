import 'package:flutter/foundation.dart';

@immutable
final class BitcoinPricePoint {
  BitcoinPricePoint({required this.timestamp, required this.usdCents}) {
    if (!timestamp.isUtc || usdCents < 0 || usdCents > _maximumSignedInteger) {
      throw ArgumentError('Market points require UTC time and a valid price.');
    }
  }

  final DateTime timestamp;
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
enum BitcoinPriceSource { spot, historyFallback }

/// Real market data suitable for rendering without synthetic fallback points.
@immutable
final class BitcoinMarketSnapshot {
  BitcoinMarketSnapshot({
    required this.currentUsdCents,
    required this.currentObservedAt,
    required this.currentSource,
    required List<BitcoinPricePoint> history,
  }) : history = List<BitcoinPricePoint>.unmodifiable(history) {
    if (currentUsdCents < 0 ||
        currentUsdCents > _maximumSignedInteger ||
        !currentObservedAt.isUtc) {
      throw ArgumentError.value(
        currentUsdCents,
        'currentUsdCents',
        'Must not be negative.',
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

  final int currentUsdCents;
  final DateTime currentObservedAt;
  final BitcoinPriceSource currentSource;
  final List<BitcoinPricePoint> history;

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
