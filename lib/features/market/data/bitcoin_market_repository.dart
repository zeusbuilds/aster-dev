import 'package:flutter/foundation.dart';

import '../../../core/config/config.dart';
import '../../../core/errors/errors.dart';
import '../../../core/network/network.dart';
import '../domain/models/models.dart';

/// Fetches truthful Bitcoin and Tether fiat data through shared HTTP policy.
final class BitcoinMarketRepository {
  BitcoinMarketRepository(
    this._http,
    this._configuration, {
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  static const _cacheLifetime = Duration(minutes: 1);
  static const _maximumChartPoints = 24;
  static const _maximumCachedCurrencies = 4;
  final ResilientHttpClient _http;
  final MarketDataConfiguration _configuration;
  final DateTime Function() _clock;
  final Map<MarketQuoteCurrency, _CachedMarketSnapshot> _cache = {};

  /// Loads one selected-currency snapshot, preserving typed transport and
  /// protocol failures and never substituting synthetic monetary values.
  Future<AppResult<BitcoinMarketSnapshot>> fetch({
    required MarketQuoteCurrency currency,
    NetworkCancellationToken? cancellation,
    bool forceRefresh = false,
  }) async {
    final result = await fetchLoad(
      currency: currency,
      cancellation: cancellation,
      forceRefresh: forceRefresh,
    );
    return switch (result) {
      AppSuccess<BitcoinMarketLoad>(:final value) => AppResult.success(
        value.snapshot,
      ),
      AppFailureResult<BitcoinMarketLoad>(:final failure) => AppResult.failure(
        failure,
      ),
    };
  }

  /// Loads the snapshot together with a typed partial-data failure.
  ///
  /// A valid spot quote remains useful when history is unavailable, and a
  /// complete history can temporarily supply a current quote. The additional
  /// failure lets presentation retry that degraded read and distinguish an
  /// offline chart without discarding independently validated data.
  Future<AppResult<BitcoinMarketLoad>> fetchLoad({
    required MarketQuoteCurrency currency,
    NetworkCancellationToken? cancellation,
    bool forceRefresh = false,
  }) async {
    if (_configuration.baseUri == null) {
      return const AppResult.failure(
        AppFailure(
          code: 'market_service_unconfigured',
          kind: AppFailureKind.configuration,
          userMessage: 'Market data is not configured for this build.',
          retryable: false,
        ),
      );
    }
    final now = _clock().toUtc();
    final cached = _cache[currency];
    if (!forceRefresh &&
        cached != null &&
        now.isBefore(cached.cachedAt.add(_cacheLifetime)) &&
        cached.load.snapshot.isCurrentAt(now)) {
      return AppResult.success(cached.load);
    }
    final from = now.subtract(BitcoinMarketSnapshot.historyWindow);
    final historyUri = _configuration
        .endpoint('coins/bitcoin/market_chart/range')
        .replace(
          queryParameters: {
            'vs_currency': currency.providerCode,
            'from': '${from.millisecondsSinceEpoch ~/ 1000}',
            'to': '${now.millisecondsSinceEpoch ~/ 1000}',
            'precision': 'full',
          },
        );
    final currentUri = _configuration
        .endpoint('simple/price')
        .replace(
          queryParameters: {
            'ids': 'bitcoin,tether',
            'vs_currencies': currency.providerCode,
            'include_last_updated_at': 'true',
            'precision': 'full',
          },
        );

    final (historyResult, currentResult) = await (
      _http.get(historyUri, cancellation: cancellation),
      _http.get(currentUri, cancellation: cancellation),
    ).wait;

    List<BitcoinPricePoint> historyCandidates = const [];
    AppFailure? historyFailure;
    switch (historyResult) {
      case AppSuccess<HttpPayload>(:final value):
        try {
          historyCandidates = _decodeHistory(
            value,
            currency: currency,
            earliest: from.subtract(const Duration(hours: 1)),
            latest: now.add(BitcoinMarketSnapshot.maximumFutureSkew),
          );
        } catch (error, stackTrace) {
          historyFailure = _invalidPayload(error, stackTrace);
        }
      case AppFailureResult<HttpPayload>(:final failure):
        historyFailure = failure;
    }

    FiatMarketPrice? currentBitcoinPrice;
    FiatMarketPrice? currentUsdtPrice;
    var currentSource = BitcoinPriceSource.spot;
    AppFailure? currentFailure;
    switch (currentResult) {
      case AppSuccess<HttpPayload>(:final value):
        Map<String, Object?>? decoded;
        try {
          decoded = _decodeCurrentPayload(value);
        } catch (error, stackTrace) {
          currentFailure = _invalidPayload(error, stackTrace);
        }
        try {
          if (decoded == null) break;
          final bitcoin = _decodeAssetPrice(
            decoded,
            assetId: 'bitcoin',
            currency: currency,
          );
          if (!_isCurrent(bitcoin.observedAt, now)) {
            throw const FormatException('Current price timestamp is stale.');
          }
          currentBitcoinPrice = bitcoin;
        } catch (error, stackTrace) {
          currentFailure = _invalidPayload(error, stackTrace);
        }
        try {
          if (decoded == null) break;
          final tether = _decodeAssetPrice(
            decoded,
            assetId: 'tether',
            currency: currency,
          );
          if (_isCurrent(tether.observedAt, now)) {
            currentUsdtPrice = tether;
          }
        } on FormatException {
          // Each provider asset is optional at this boundary. A malformed or
          // stale Tether observation must not erase independently valid BTC.
        } on ArgumentError {
          // Provider-controlled timestamps and values can also violate the
          // validated domain constructors without invalidating Bitcoin data.
        }
      case AppFailureResult<HttpPayload>(:final failure):
        currentFailure = failure;
    }

    final historyFallback = historyCandidates.lastOrNull;
    if (currentBitcoinPrice == null &&
        historyFallback != null &&
        _isCurrent(historyFallback.timestamp, now)) {
      currentBitcoinPrice = FiatMarketPrice(
        minorUnits: historyFallback.fiatMinorUnits,
        observedAt: historyFallback.timestamp,
      );
      currentSource = BitcoinPriceSource.historyFallback;
    }
    if (currentBitcoinPrice == null) {
      return AppResult.failure(
        _preferredFailure(currentFailure, historyFailure),
      );
    }
    final history = _buildChartHistory(
      historyCandidates,
      currentPrice: currentBitcoinPrice,
      requestedStart: from,
      now: now,
    );
    final snapshot = BitcoinMarketSnapshot(
      quoteCurrency: currency,
      currentBitcoinPrice: currentBitcoinPrice,
      currentUsdtPrice: currentUsdtPrice,
      currentSource: currentSource,
      history: history,
    );
    final degradedFailure = _degradedFailure(
      history: history,
      historyFailure: historyFailure,
      currentFailure: currentSource == BitcoinPriceSource.historyFallback
          ? currentFailure
          : null,
    );
    final load = BitcoinMarketLoad(
      snapshot: snapshot,
      degradedFailure: degradedFailure,
    );
    _cacheLoad(load, now);
    return AppResult.success(load);
  }

  static List<BitcoinPricePoint> _decodeHistory(
    HttpPayload payload, {
    required MarketQuoteCurrency currency,
    required DateTime earliest,
    required DateTime latest,
  }) {
    final decoded = payload.decodeJson();
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a market history object.');
    }
    final rawPrices = decoded['prices'];
    if (rawPrices is! List<Object?>) {
      throw const FormatException('Market history is missing prices.');
    }
    final byTimestamp = <int, BitcoinPricePoint>{};
    for (final rawPoint in rawPrices) {
      if (rawPoint is! List<Object?> || rawPoint.length < 2) {
        throw const FormatException(
          'Market history contains an invalid point.',
        );
      }
      final rawTimestamp = rawPoint[0];
      final rawPrice = rawPoint[1];
      if (rawTimestamp is! num ||
          !rawTimestamp.isFinite ||
          rawTimestamp.isNegative ||
          rawTimestamp != rawTimestamp.toInt() ||
          rawPrice is! num) {
        throw const FormatException(
          'Market history contains an invalid point.',
        );
      }
      final milliseconds = rawTimestamp.toInt();
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      );
      if (timestamp.isBefore(earliest) || timestamp.isAfter(latest)) {
        throw const FormatException(
          'Market history contains an out-of-window point.',
        );
      }
      byTimestamp[milliseconds] = BitcoinPricePoint(
        timestamp: timestamp,
        fiatMinorUnits: _toMinorUnits(
          rawPrice,
          precision: currency.minorUnitDigits,
        ),
      );
    }
    final points = byTimestamp.values.toList()
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return List<BitcoinPricePoint>.unmodifiable(points);
  }

  static List<BitcoinPricePoint> _sampleHistory(
    List<BitcoinPricePoint> points,
  ) {
    if (points.length <= _maximumChartPoints) return points;
    final lastIndex = points.length - 1;
    return List<BitcoinPricePoint>.generate(_maximumChartPoints, (index) {
      final sourceIndex = (index * lastIndex / (_maximumChartPoints - 1))
          .round();
      return points[sourceIndex];
    }, growable: false);
  }

  static List<BitcoinPricePoint> _buildChartHistory(
    List<BitcoinPricePoint> points, {
    required FiatMarketPrice currentPrice,
    required DateTime requestedStart,
    required DateTime now,
  }) {
    if (!_coversHistoricalWindow(
      points,
      requestedStart: requestedStart,
      now: now,
    )) {
      return const <BitcoinPricePoint>[];
    }

    final currentPoint = BitcoinPricePoint(
      timestamp: currentPrice.observedAt,
      fiatMinorUnits: currentPrice.minorUnits,
    );
    final completed = <BitcoinPricePoint>[
      for (final point in points)
        if (point.timestamp.isBefore(currentPoint.timestamp)) point,
      currentPoint,
    ];
    if (completed.length < 2) return const <BitcoinPricePoint>[];
    return List<BitcoinPricePoint>.unmodifiable(_sampleHistory(completed));
  }

  static bool _coversHistoricalWindow(
    List<BitcoinPricePoint> points, {
    required DateTime requestedStart,
    required DateTime now,
  }) {
    if (points.length < 2) return false;
    final latestStart = requestedStart.add(
      BitcoinMarketSnapshot.maximumHistoryStartLag,
    );
    final earliestEnd = now.subtract(
      BitcoinMarketSnapshot.maximumHistoryTailLag,
    );
    return !points.first.timestamp.isAfter(latestStart) &&
        points.last.timestamp.isAfter(earliestEnd);
  }

  static Map<String, Object?> _decodeCurrentPayload(HttpPayload payload) {
    final decoded = payload.decodeJson();
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a current-price object.');
    }
    return decoded;
  }

  static FiatMarketPrice _decodeAssetPrice(
    Map<String, Object?> decoded, {
    required String assetId,
    required MarketQuoteCurrency currency,
  }) {
    final asset = decoded[assetId];
    final rawPrice = asset is Map<String, Object?>
        ? asset[currency.providerCode]
        : null;
    final rawUpdatedAt = asset is Map<String, Object?>
        ? asset['last_updated_at']
        : null;
    if (rawPrice is! num || rawUpdatedAt is! num) {
      throw FormatException(
        'Current $assetId/${currency.code} price is missing.',
      );
    }
    if (!rawUpdatedAt.isFinite ||
        rawUpdatedAt.isNegative ||
        rawUpdatedAt != rawUpdatedAt.toInt()) {
      throw const FormatException('Current price timestamp is invalid.');
    }
    final observedAt = DateTime.fromMillisecondsSinceEpoch(
      rawUpdatedAt.toInt() * 1000,
      isUtc: true,
    );
    return FiatMarketPrice(
      minorUnits: _toMinorUnits(rawPrice, precision: currency.minorUnitDigits),
      observedAt: observedAt,
    );
  }

  void _cacheLoad(BitcoinMarketLoad load, DateTime cachedAt) {
    _cache.remove(load.snapshot.quoteCurrency);
    _cache[load.snapshot.quoteCurrency] = _CachedMarketSnapshot(
      load: load,
      cachedAt: cachedAt,
    );
    while (_cache.length > _maximumCachedCurrencies) {
      _cache.remove(_cache.keys.first);
    }
  }

  static int _toMinorUnits(num value, {required int precision}) {
    if (!value.isFinite || value <= 0) {
      throw const FormatException('Price must be finite and positive.');
    }
    final match = RegExp(r'^(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$')
        .firstMatch(value.toString());
    if (match == null) throw const FormatException('Invalid decimal price.');
    final whole = match.group(1)!;
    final fraction = match.group(2) ?? '';
    final exponent = int.tryParse(match.group(3) ?? '0') ?? 0;
    final digits = BigInt.parse('$whole$fraction');
    final shift = exponent - fraction.length + precision;
    final result = shift >= 0
        ? digits * BigInt.from(10).pow(shift)
        : () {
            final divisor = BigInt.from(10).pow(-shift);
            return (digits + (divisor ~/ BigInt.two)) ~/ divisor;
          }();
    if (result <= BigInt.zero || result > BigInt.from(0x7fffffffffffffff)) {
      throw const FormatException('Price exceeds supported bounds.');
    }
    return result.toInt();
  }

  static bool _isCurrent(DateTime observedAt, DateTime now) =>
      BitcoinMarketSnapshot.isObservationCurrentAt(
        observedAt: observedAt,
        now: now,
      );

  static DateTime _utcNow() => DateTime.now().toUtc();

  static AppFailure? _degradedFailure({
    required List<BitcoinPricePoint> history,
    required AppFailure? historyFailure,
    required AppFailure? currentFailure,
  }) {
    final effectiveHistoryFailure = history.isEmpty
        ? historyFailure ?? _incompleteHistory()
        : null;
    if (effectiveHistoryFailure == null && currentFailure == null) return null;
    return _preferredFailure(currentFailure, effectiveHistoryFailure);
  }

  static AppFailure _preferredFailure(
    AppFailure? primary,
    AppFailure? secondary,
  ) {
    if (primary?.kind == AppFailureKind.connectivity) return primary!;
    if (secondary?.kind == AppFailureKind.connectivity) return secondary!;
    return primary ?? secondary ?? _incompleteHistory();
  }

  static AppFailure _incompleteHistory() {
    return const AppFailure(
      code: 'market_history_incomplete',
      kind: AppFailureKind.unavailable,
      userMessage: 'Market history is temporarily unavailable.',
      retryable: true,
    );
  }

  static AppFailure _invalidPayload(Object error, StackTrace stackTrace) {
    return AppFailure(
      code: 'market_payload_invalid',
      kind: AppFailureKind.protocol,
      userMessage: 'Market data is temporarily unavailable.',
      retryable: true,
      cause: FailureMapper.diagnosticCause(error),
      stackTrace: stackTrace,
    );
  }
}

/// A validated market snapshot and any recoverable missing-data condition.
@immutable
final class BitcoinMarketLoad {
  const BitcoinMarketLoad({
    required this.snapshot,
    required this.degradedFailure,
  });

  final BitcoinMarketSnapshot snapshot;

  /// Failure for an endpoint whose data was replaced by a validated fallback
  /// or omitted from this otherwise useful snapshot.
  final AppFailure? degradedFailure;
}

final class _CachedMarketSnapshot {
  const _CachedMarketSnapshot({required this.load, required this.cachedAt});

  final BitcoinMarketLoad load;
  final DateTime cachedAt;
}
