import 'package:aster/core/core.dart';
import 'package:aster/features/market/data/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final now = DateTime.utc(2026, 8, 8, 12);
  final recentFirst = now.subtract(const Duration(minutes: 10));
  final recentLast = now.subtract(const Duration(minutes: 1));

  test('returns integer cents and sorted, deduplicated real history', () async {
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            '{"prices":[[${recentLast.millisecondsSinceEpoch},65000.129],'
            '[${recentFirst.millisecondsSinceEpoch},64000.125],'
            '[${recentLast.millisecondsSinceEpoch},65001.999]]}',
            200,
          );
        }
        return http.Response(
          '{"bitcoin":{"usd":65123.456,"last_updated_at":'
          '${recentLast.millisecondsSinceEpoch ~/ 1000}}}',
          200,
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      clock: () => now,
    ).fetch();
    final snapshot = (result as AppSuccess<BitcoinMarketSnapshot>).value;

    expect(snapshot.currentUsdCents, 6512346);
    expect(snapshot.currentSource, BitcoinPriceSource.spot);
    expect(
      snapshot.currentObservedAt,
      DateTime.fromMillisecondsSinceEpoch(
        (recentLast.millisecondsSinceEpoch ~/ 1000) * 1000,
        isUtc: true,
      ),
    );
    expect(snapshot.history.map((point) => point.usdCents), [6400013, 6500200]);
    expect(snapshot.history.first.timestamp.isUtc, isTrue);
  });

  test('uses latest real history point when current endpoint fails', () async {
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            '{"prices":[[${recentFirst.millisecondsSinceEpoch},64000],'
            '[${recentLast.millisecondsSinceEpoch},65000]]}',
            200,
          );
        }
        return http.Response('unavailable', 503);
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      clock: () => now,
    ).fetch();
    final snapshot = (result as AppSuccess<BitcoinMarketSnapshot>).value;

    expect(snapshot.currentUsdCents, 6500000);
    expect(snapshot.currentSource, BitcoinPriceSource.historyFallback);
    expect(snapshot.currentObservedAt, snapshot.history.last.timestamp);
    expect(snapshot.history, hasLength(2));
  });

  test('does not manufacture data when both endpoints fail', () async {
    final transport = ResilientHttpClient(
      client: MockClient((request) async => http.Response('no', 503)),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      clock: () => now,
    ).fetch();

    expect(result, isA<AppFailureResult<BitcoinMarketSnapshot>>());
  });

  test('rejects market prices outside signed 64-bit storage bounds', () async {
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/range')) {
          return http.Response('{"prices":[]}', 200);
        }
        return http.Response(
          '{"bitcoin":{"usd":1e100,"last_updated_at":'
          '${recentLast.millisecondsSinceEpoch ~/ 1000}}}',
          200,
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      clock: () => now,
    ).fetch();

    expect(result, isA<AppFailureResult<BitcoinMarketSnapshot>>());
    expect(
      (result as AppFailureResult<BitcoinMarketSnapshot>).failure.code,
      'market_payload_invalid',
    );
  });

  test(
    'does not partially accept history when any point is malformed',
    () async {
      final transport = ResilientHttpClient(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/range')) {
            return http.Response(
              '{"prices":[[1000,64000],["bad",65000]]}',
              200,
            );
          }
          return http.Response(
            '{"bitcoin":{"usd":65000,"last_updated_at":'
            '${recentLast.millisecondsSinceEpoch ~/ 1000}}}',
            200,
          );
        }),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      addTearDown(transport.close);

      final result = await BitcoinMarketRepository(
        transport,
        clock: () => now,
      ).fetch();

      final snapshot = (result as AppSuccess<BitcoinMarketSnapshot>).value;
      expect(snapshot.currentUsdCents, 6500000);
      expect(snapshot.currentSource, BitcoinPriceSource.spot);
      expect(snapshot.history, isEmpty);
    },
  );

  test('never presents stale or future-dated prices as current', () async {
    final stale = now.subtract(const Duration(hours: 2));
    final future = now.add(const Duration(hours: 1));
    var currentTimestamp = stale.millisecondsSinceEpoch ~/ 1000;
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            '{"prices":[[${stale.millisecondsSinceEpoch},64000]]}',
            200,
          );
        }
        return http.Response(
          '{"bitcoin":{"usd":65000,"last_updated_at":$currentTimestamp}}',
          200,
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);
    final repository = BitcoinMarketRepository(transport, clock: () => now);

    expect(
      await repository.fetch(),
      isA<AppFailureResult<BitcoinMarketSnapshot>>(),
    );

    currentTimestamp = future.millisecondsSinceEpoch ~/ 1000;
    expect(
      await repository.fetch(),
      isA<AppFailureResult<BitcoinMarketSnapshot>>(),
    );
  });

  test('market values validate chronology and compare by value', () {
    final first = BitcoinPricePoint(
      timestamp: DateTime.utc(2026, 8, 8),
      usdCents: 6500000,
    );
    final same = BitcoinPricePoint(
      timestamp: DateTime.utc(2026, 8, 8),
      usdCents: 6500000,
    );

    expect(first, same);
    expect(
      BitcoinMarketSnapshot(
        currentUsdCents: 6500000,
        currentObservedAt: first.timestamp,
        currentSource: BitcoinPriceSource.spot,
        history: [first],
      ),
      BitcoinMarketSnapshot(
        currentUsdCents: 6500000,
        currentObservedAt: same.timestamp,
        currentSource: BitcoinPriceSource.spot,
        history: [same],
      ),
    );
    expect(
      () =>
          BitcoinPricePoint(timestamp: DateTime(2026, 8, 8), usdCents: 6500000),
      throwsArgumentError,
    );
    expect(
      () => BitcoinMarketSnapshot(
        currentUsdCents: 6500000,
        currentObservedAt: DateTime(2026, 8, 8),
        currentSource: BitcoinPriceSource.spot,
        history: [first],
      ),
      throwsArgumentError,
    );
    expect(
      () => BitcoinMarketSnapshot(
        currentUsdCents: 6500000,
        currentObservedAt: first.timestamp,
        currentSource: BitcoinPriceSource.spot,
        history: [same, first],
      ),
      throwsArgumentError,
    );
    expect(
      BitcoinMarketSnapshot(
        currentUsdCents: 6600000,
        currentObservedAt: first.timestamp,
        currentSource: BitcoinPriceSource.spot,
        history: [
          first,
          BitcoinPricePoint(
            timestamp: DateTime.utc(2026, 8, 8, 1),
            usdCents: 6400000,
          ),
        ],
      ).changeBasisPoints,
      153,
    );
  });

  test('market snapshot exposes an exact presentation freshness boundary', () {
    final observedAt = DateTime.utc(2026, 8, 11, 12);
    final snapshot = BitcoinMarketSnapshot(
      currentUsdCents: 6500000,
      currentObservedAt: observedAt,
      currentSource: BitcoinPriceSource.spot,
      history: const [],
    );

    expect(snapshot.isCurrentAt(observedAt), isTrue);
    expect(
      snapshot.isCurrentAt(
        observedAt.add(
          BitcoinMarketSnapshot.maximumCurrentAge -
              const Duration(milliseconds: 1),
        ),
      ),
      isTrue,
    );
    expect(snapshot.isCurrentAt(snapshot.expiresAt), isFalse);
    expect(
      snapshot.isCurrentAt(observedAt.subtract(const Duration(seconds: 1))),
      isFalse,
    );
  });
}
