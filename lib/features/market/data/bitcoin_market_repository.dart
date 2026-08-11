import '../../../core/errors/errors.dart';
import '../../../core/network/network.dart';
import 'models/bitcoin_market_snapshot.dart';

/// Fetches truthful Bitcoin/USD market data through the shared HTTP policy.
final class BitcoinMarketRepository {
  BitcoinMarketRepository(this._http, {DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  static const _baseUrl = 'https://api.coingecko.com/api/v3';
  static const _maximumFutureSkew = Duration(minutes: 5);
  final ResilientHttpClient _http;
  final DateTime Function() _clock;

  Future<AppResult<BitcoinMarketSnapshot>> fetch({
    NetworkCancellationToken? cancellation,
  }) async {
    final now = _clock().toUtc();
    final from = now.subtract(const Duration(hours: 24));
    final historyUri = Uri.parse('$_baseUrl/coins/bitcoin/market_chart/range')
        .replace(
          queryParameters: {
            'vs_currency': 'usd',
            'from': '${from.millisecondsSinceEpoch ~/ 1000}',
            'to': '${now.millisecondsSinceEpoch ~/ 1000}',
          },
        );
    final currentUri = Uri.parse('$_baseUrl/simple/price').replace(
      queryParameters: {
        'ids': 'bitcoin',
        'vs_currencies': 'usd',
        'include_last_updated_at': 'true',
      },
    );

    final (historyResult, currentResult) = await (
      _http.get(historyUri, cancellation: cancellation),
      _http.get(currentUri, cancellation: cancellation),
    ).wait;

    List<BitcoinPricePoint> history = const [];
    AppFailure? historyFailure;
    switch (historyResult) {
      case AppSuccess<HttpPayload>(:final value):
        try {
          history = _decodeHistory(
            value,
            earliest: from.subtract(const Duration(hours: 1)),
            latest: now.add(_maximumFutureSkew),
          );
        } catch (error, stackTrace) {
          historyFailure = _invalidPayload(error, stackTrace);
        }
      case AppFailureResult<HttpPayload>(:final failure):
        historyFailure = failure;
    }

    int? currentUsdCents;
    DateTime? currentObservedAt;
    var currentSource = BitcoinPriceSource.spot;
    AppFailure? currentFailure;
    switch (currentResult) {
      case AppSuccess<HttpPayload>(:final value):
        try {
          final current = _decodeCurrentPrice(value);
          if (!_isCurrent(current.observedAt, now)) {
            throw const FormatException('Current price timestamp is stale.');
          }
          currentUsdCents = current.usdCents;
          currentObservedAt = current.observedAt;
        } catch (error, stackTrace) {
          currentFailure = _invalidPayload(error, stackTrace);
        }
      case AppFailureResult<HttpPayload>(:final failure):
        currentFailure = failure;
    }

    final historyFallback = history.lastOrNull;
    if (currentUsdCents == null &&
        historyFallback != null &&
        _isCurrent(historyFallback.timestamp, now)) {
      currentUsdCents = historyFallback.usdCents;
      currentObservedAt = historyFallback.timestamp;
      currentSource = BitcoinPriceSource.historyFallback;
    }
    if (currentUsdCents == null || currentObservedAt == null) {
      return AppResult.failure(currentFailure ?? historyFailure!);
    }
    return AppResult.success(
      BitcoinMarketSnapshot(
        currentUsdCents: currentUsdCents,
        currentObservedAt: currentObservedAt,
        currentSource: currentSource,
        history: history,
      ),
    );
  }

  static List<BitcoinPricePoint> _decodeHistory(
    HttpPayload payload, {
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
        usdCents: _toMinorUnits(rawPrice, precision: 2),
      );
    }
    final points = byTimestamp.values.toList()
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return List<BitcoinPricePoint>.unmodifiable(points);
  }

  static ({int usdCents, DateTime observedAt}) _decodeCurrentPrice(
    HttpPayload payload,
  ) {
    final decoded = payload.decodeJson();
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a current-price object.');
    }
    final bitcoin = decoded['bitcoin'];
    if (bitcoin is! Map<String, Object?> ||
        bitcoin['usd'] is! num ||
        bitcoin['last_updated_at'] is! num) {
      throw const FormatException('Current Bitcoin/USD price is missing.');
    }
    final rawTimestamp = bitcoin['last_updated_at']! as num;
    if (!rawTimestamp.isFinite ||
        rawTimestamp.isNegative ||
        rawTimestamp != rawTimestamp.toInt()) {
      throw const FormatException('Current price timestamp is invalid.');
    }
    final observedAt = DateTime.fromMillisecondsSinceEpoch(
      rawTimestamp.toInt() * 1000,
      isUtc: true,
    );
    return (
      usdCents: _toMinorUnits(bitcoin['usd']! as num, precision: 2),
      observedAt: observedAt,
    );
  }

  static int _toMinorUnits(num value, {required int precision}) {
    if (!value.isFinite || value.isNegative) {
      throw const FormatException('Price must be finite and non-negative.');
    }
    final match = RegExp(
      r'^(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$',
    ).firstMatch(value.toString());
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
    if (result > BigInt.from(0x7fffffffffffffff)) {
      throw const FormatException('Price exceeds supported bounds.');
    }
    return result.toInt();
  }

  static bool _isCurrent(DateTime observedAt, DateTime now) =>
      !observedAt.isBefore(
        now.subtract(BitcoinMarketSnapshot.maximumCurrentAge),
      ) &&
      !observedAt.isAfter(now.add(_maximumFutureSkew));

  static DateTime _utcNow() => DateTime.now().toUtc();

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
