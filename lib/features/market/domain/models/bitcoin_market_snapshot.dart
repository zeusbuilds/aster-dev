import 'package:flutter/foundation.dart';

import '../../../../shared/formatting/fiat_currency_policy.dart';

const _maximumSignedInteger = 0x7fffffffffffffff;

/// Validated fiat identity accepted by the market-data boundary.
@immutable
final class MarketQuoteCurrency {
  MarketQuoteCurrency({
    required this.code,
    required this.symbol,
    required this.minorUnitDigits,
  }) {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
      throw ArgumentError.value(code, 'code', 'Must be an ISO 4217 code.');
    }
    if (!supportsCode(code)) {
      throw ArgumentError.value(
        code,
        'code',
        'Must be a supported market quote currency.',
      );
    }
    if (symbol.trim() != symbol || symbol.isEmpty || symbol.length > 8) {
      throw ArgumentError.value(symbol, 'symbol', 'Must be a bounded symbol.');
    }
    final expectedMinorUnitDigits = FiatCurrencyPolicy.minorUnitDigits(code);
    if (minorUnitDigits != expectedMinorUnitDigits) {
      throw ArgumentError.value(
        minorUnitDigits,
        'minorUnitDigits',
        'Must match the ISO 4217 precision of $expectedMinorUnitDigits.',
      );
    }
  }

  /// ISO 4217 alphabetic code used as app identity.
  final String code;

  /// Curated display symbol from the app's bundled currency catalog.
  final String symbol;

  /// Number of decimal digits in one ISO minor unit.
  final int minorUnitDigits;

  /// Lowercase quote identifier required by CoinGecko.
  String get providerCode => code.toLowerCase();

  /// Whether the reviewed provider contract supports [code].
  ///
  /// This allowlist is the fiat intersection of the bundled catalog and
  /// CoinGecko's official `/simple/supported_vs_currencies` response, verified
  /// on 2026-08-13. Runtime payload validation still fails closed if support
  /// changes before the next app release.
  static bool supportsCode(String code) =>
      FiatCurrencyPolicy.supportsMarketQuote(code);

  @override
  bool operator ==(Object other) =>
      other is MarketQuoteCurrency &&
      other.code == code &&
      other.symbol == symbol &&
      other.minorUnitDigits == minorUnitDigits;

  @override
  int get hashCode => Object.hash(code, symbol, minorUnitDigits);
}

/// One exact provider price for a whole asset in fiat minor units.
@immutable
final class FiatMarketPrice {
  FiatMarketPrice({required this.minorUnits, required this.observedAt}) {
    if (minorUnits <= 0 || minorUnits > _maximumSignedInteger) {
      throw ArgumentError.value(
        minorUnits,
        'minorUnits',
        'Must be a positive signed 64-bit integer.',
      );
    }
    if (!observedAt.isUtc) {
      throw ArgumentError.value(observedAt, 'observedAt', 'Must be UTC.');
    }
  }

  /// Fiat minor units for one whole Bitcoin or Tether unit.
  final int minorUnits;

  /// UTC instant at which the provider observed [minorUnits].
  final DateTime observedAt;

  /// First instant at which this price must no longer be rendered as live.
  DateTime get expiresAt =>
      observedAt.add(BitcoinMarketSnapshot.maximumCurrentAge);

  /// Whether this observation satisfies the shared temporal policy at [now].
  bool isCurrentAt(DateTime now) =>
      BitcoinMarketSnapshot.isObservationCurrentAt(
        observedAt: observedAt,
        now: now,
      );

  @override
  bool operator ==(Object other) =>
      other is FiatMarketPrice &&
      other.minorUnits == minorUnits &&
      other.observedAt == observedAt;

  @override
  int get hashCode => Object.hash(minorUnits, observedAt);
}

/// One validated Bitcoin observation in the snapshot's quote currency.
@immutable
final class BitcoinPricePoint {
  BitcoinPricePoint({required this.timestamp, required this.fiatMinorUnits}) {
    if (!timestamp.isUtc) {
      throw ArgumentError.value(timestamp, 'timestamp', 'Must be UTC.');
    }
    if (fiatMinorUnits <= 0 || fiatMinorUnits > _maximumSignedInteger) {
      throw ArgumentError.value(
        fiatMinorUnits,
        'fiatMinorUnits',
        'Must be a positive signed 64-bit integer.',
      );
    }
  }

  /// UTC instant at which the provider observed this Bitcoin price.
  final DateTime timestamp;

  /// Bitcoin price in the snapshot currency's integer minor units.
  final int fiatMinorUnits;

  @override
  bool operator ==(Object other) =>
      other is BitcoinPricePoint &&
      other.timestamp == timestamp &&
      other.fiatMinorUnits == fiatMinorUnits;

  @override
  int get hashCode => Object.hash(timestamp, fiatMinorUnits);
}

/// Provenance of the value rendered as the current Bitcoin market price.
enum BitcoinPriceSource {
  /// A dedicated provider spot-price response.
  spot,

  /// The newest validated history point when a current response was absent.
  historyFallback,
}

/// Validated multi-asset fiat data suitable for rendering without fallbacks.
@immutable
final class BitcoinMarketSnapshot {
  BitcoinMarketSnapshot({
    required this.quoteCurrency,
    required this.currentBitcoinPrice,
    required this.currentSource,
    required List<BitcoinPricePoint> history,
    this.currentUsdtPrice,
  }) : history = List<BitcoinPricePoint>.unmodifiable(history) {
    for (var index = 1; index < this.history.length; index += 1) {
      if (!this.history[index].timestamp.isAfter(
        this.history[index - 1].timestamp,
      )) {
        throw ArgumentError('Market history must be strictly chronological.');
      }
    }
  }

  /// Fiat identity shared by every value in this snapshot.
  final MarketQuoteCurrency quoteCurrency;

  /// Current Bitcoin price and provider timestamp.
  final FiatMarketPrice currentBitcoinPrice;

  /// Current Tether price when the provider returned one valid observation.
  final FiatMarketPrice? currentUsdtPrice;

  /// Provider path from which the current Bitcoin value was selected.
  final BitcoinPriceSource currentSource;

  /// Strictly chronological, immutable Bitcoin observations.
  final List<BitcoinPricePoint> history;

  /// Maximum age for presenting a provider price as a live conversion.
  static const maximumCurrentAge = Duration(minutes: 30);

  /// Bounded provider/client clock skew accepted as a current observation.
  static const maximumFutureSkew = Duration(minutes: 5);

  /// Requested provider window represented by a complete Home chart.
  static const historyWindow = Duration(hours: 24);

  /// Latest acceptable first observation relative to the requested start.
  static const maximumHistoryStartLag = Duration(hours: 1);

  /// Maximum lag allowed between the last hourly bucket and the live quote.
  ///
  /// CoinGecko publishes completed hourly buckets after the represented hour,
  /// so the newest bucket may be more than one hour behind a valid spot quote.
  /// The repository appends that independently validated quote to the chart;
  /// this bound only prevents a substantially truncated history from being
  /// presented as a complete 24-hour series.
  static const maximumHistoryTailLag = Duration(hours: 2);

  /// First instant at which the Bitcoin price must no longer be presented.
  DateTime get expiresAt => currentBitcoinPrice.expiresAt;

  /// Whether the current Bitcoin observation is valid at [now].
  bool isCurrentAt(DateTime now) => currentBitcoinPrice.isCurrentAt(now);

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

  /// Bitcoin price change in basis points (100 basis points is one percent).
  int? get changeBasisPoints {
    if (history.length < 2 || history.first.fiatMinorUnits == 0) return null;
    final change =
        (BigInt.from(
              currentBitcoinPrice.minorUnits - history.first.fiatMinorUnits,
            ) *
            BigInt.from(10000)) ~/
        BigInt.from(history.first.fiatMinorUnits);
    if (change < BigInt.from(-_maximumSignedInteger) ||
        change > BigInt.from(_maximumSignedInteger)) {
      return null;
    }
    return change.toInt();
  }

  @override
  bool operator ==(Object other) =>
      other is BitcoinMarketSnapshot &&
      other.quoteCurrency == quoteCurrency &&
      other.currentBitcoinPrice == currentBitcoinPrice &&
      other.currentUsdtPrice == currentUsdtPrice &&
      other.currentSource == currentSource &&
      listEquals(other.history, history);

  @override
  int get hashCode => Object.hash(
    quoteCurrency,
    currentBitcoinPrice,
    currentUsdtPrice,
    currentSource,
    Object.hashAll(history),
  );
}
