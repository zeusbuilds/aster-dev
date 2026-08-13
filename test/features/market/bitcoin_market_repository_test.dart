import 'dart:convert';

import 'package:aster/core/core.dart';
import 'package:aster/features/market/data/data.dart';
import 'package:aster/features/market/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final now = DateTime.utc(2026, 8, 8, 12);
  final recentFirst = now.subtract(const Duration(minutes: 10));
  final recentLast = now.subtract(const Duration(minutes: 1));

  test('requests the selected fiat and decodes Bitcoin and Tether', () async {
    final requestedCurrencies = <String>[];
    final transport = _transport((request) async {
      final currency = _requestedCurrency(request);
      requestedCurrencies.add(currency);
      if (request.url.path.endsWith('/range')) {
        expect(request.url.queryParameters['precision'], 'full');
        return _historyResponse([
          [recentLast.millisecondsSinceEpoch, 65000.129],
          [recentFirst.millisecondsSinceEpoch, 64000.125],
          [recentLast.millisecondsSinceEpoch, 65001.999],
        ]);
      }
      expect(request.url.queryParameters['ids'], 'bitcoin,tether');
      expect(request.url.queryParameters['precision'], 'full');
      return _currentResponse(
        currency: currency,
        bitcoin: 65123.456,
        tether: 0.9234,
        observedAt: recentLast,
      );
    });
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    ).fetch(currency: _eur);
    final snapshot = (result as AppSuccess<BitcoinMarketSnapshot>).value;

    expect(requestedCurrencies, ['eur', 'eur']);
    expect(snapshot.quoteCurrency, _eur);
    expect(snapshot.currentBitcoinPrice.minorUnits, 6512346);
    expect(snapshot.currentUsdtPrice?.minorUnits, 92);
    expect(snapshot.currentSource, BitcoinPriceSource.spot);
    expect(
      snapshot.currentBitcoinPrice.observedAt,
      DateTime.fromMillisecondsSinceEpoch(
        (recentLast.millisecondsSinceEpoch ~/ 1000) * 1000,
        isUtc: true,
      ),
    );
    expect(snapshot.history.map((point) => point.fiatMinorUnits), [
      6400013,
      6500200,
    ]);
    expect(snapshot.history.first.timestamp.isUtc, isTrue);
  });

  test('rounds zero-, two-, and three-decimal fiat minor units', () async {
    final vectors = <(MarketQuoteCurrency, num, int)>[
      (_jpy, 65000.5, 65001),
      (_usd, 65000.125, 6500013),
      (_kwd, 19999.9995, 20000000),
    ];
    for (final (currency, rawPrice, expected) in vectors) {
      final transport = _transport((request) async {
        final providerCode = _requestedCurrency(request);
        if (request.url.path.endsWith('/range')) {
          return _historyResponse(const []);
        }
        return _currentResponse(
          currency: providerCode,
          bitcoin: rawPrice,
          tether: 1,
          observedAt: recentLast,
        );
      });
      addTearDown(transport.close);

      final result = await BitcoinMarketRepository(
        transport,
        MarketDataConfiguration.developmentKeyless(),
        clock: () => now,
      ).fetch(currency: currency);

      expect(
        (result as AppSuccess<BitcoinMarketSnapshot>)
            .value
            .currentBitcoinPrice
            .minorUnits,
        expected,
        reason: currency.code,
      );
    }
  });

  test('uses the latest real history point when current fails', () async {
    final transport = _transport((request) async {
      if (request.url.path.endsWith('/range')) {
        return _historyResponse([
          [recentFirst.millisecondsSinceEpoch, 64000],
          [recentLast.millisecondsSinceEpoch, 65000],
        ]);
      }
      return http.Response('unavailable', 503);
    });
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    ).fetch(currency: _usd);
    final snapshot = (result as AppSuccess<BitcoinMarketSnapshot>).value;

    expect(snapshot.currentBitcoinPrice.minorUnits, 6500000);
    expect(snapshot.currentSource, BitcoinPriceSource.historyFallback);
    expect(
      snapshot.currentBitcoinPrice.observedAt,
      snapshot.history.last.timestamp,
    );
    expect(snapshot.currentUsdtPrice, isNull);
  });

  test('keeps a valid Bitcoin quote when Tether is absent', () async {
    final transport = _transport((request) async {
      if (request.url.path.endsWith('/range')) {
        return _historyResponse(const []);
      }
      return http.Response(
        jsonEncode({
          'bitcoin': {
            'usd': 65000,
            'last_updated_at': recentLast.millisecondsSinceEpoch ~/ 1000,
          },
        }),
        200,
      );
    });
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    ).fetch(currency: _usd);
    final snapshot = (result as AppSuccess<BitcoinMarketSnapshot>).value;

    expect(snapshot.currentBitcoinPrice.minorUnits, 6500000);
    expect(snapshot.currentUsdtPrice, isNull);
  });

  test('keeps Bitcoin when optional Tether violates domain bounds', () async {
    final transport = _transport((request) async {
      if (request.url.path.endsWith('/range')) {
        return _historyResponse(const []);
      }
      return http.Response(
        jsonEncode({
          'bitcoin': {
            'usd': 65000,
            'last_updated_at': recentLast.millisecondsSinceEpoch ~/ 1000,
          },
          'tether': {'usd': 1, 'last_updated_at': 9000000000000},
        }),
        200,
      );
    });
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    ).fetch(currency: _usd);
    final snapshot = (result as AppSuccess<BitcoinMarketSnapshot>).value;

    expect(snapshot.currentBitcoinPrice.minorUnits, 6500000);
    expect(snapshot.currentUsdtPrice, isNull);
  });

  test('retains valid Tether when Bitcoin uses history fallback', () async {
    final transport = _transport((request) async {
      if (request.url.path.endsWith('/range')) {
        return _historyResponse([
          [recentLast.millisecondsSinceEpoch, 65000],
        ]);
      }
      return http.Response(
        jsonEncode({
          'bitcoin': {
            'usd': 'invalid',
            'last_updated_at': recentLast.millisecondsSinceEpoch ~/ 1000,
          },
          'tether': {
            'usd': 0.9998,
            'last_updated_at': recentLast.millisecondsSinceEpoch ~/ 1000,
          },
        }),
        200,
      );
    });
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    ).fetch(currency: _usd);
    final snapshot = (result as AppSuccess<BitcoinMarketSnapshot>).value;

    expect(snapshot.currentSource, BitcoinPriceSource.historyFallback);
    expect(snapshot.currentBitcoinPrice.minorUnits, 6500000);
    expect(snapshot.currentUsdtPrice?.minorUnits, 100);
  });

  test('does not manufacture data when both endpoints fail', () async {
    final transport = _transport(
      (request) async => http.Response('unavailable', 503),
    );
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    ).fetch(currency: _usd);

    expect(result, isA<AppFailureResult<BitcoinMarketSnapshot>>());
  });

  test(
    'fails before transport when a release market service is absent',
    () async {
      var requestCount = 0;
      final transport = _transport((request) async {
        requestCount += 1;
        return http.Response('{}', 200);
      });
      addTearDown(transport.close);
      final repository = BitcoinMarketRepository(
        transport,
        MarketDataConfiguration.resolve(configuredBase: '', releaseMode: true),
        clock: () => now,
      );

      final result = await repository.fetch(currency: _usd);

      expect(result, isA<AppFailureResult<BitcoinMarketSnapshot>>());
      final failure =
          (result as AppFailureResult<BitcoinMarketSnapshot>).failure;
      expect(failure.code, 'market_service_unconfigured');
      expect(failure.kind, AppFailureKind.configuration);
      expect(failure.retryable, isFalse);
      expect(requestCount, 0);
    },
  );

  test('rejects market values outside signed 64-bit bounds', () async {
    final transport = _transport((request) async {
      if (request.url.path.endsWith('/range')) {
        return _historyResponse(const []);
      }
      return _currentResponse(
        currency: 'usd',
        bitcoin: 1e100,
        tether: 1,
        observedAt: recentLast,
      );
    });
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    ).fetch(currency: _usd);

    expect(result, isA<AppFailureResult<BitcoinMarketSnapshot>>());
    expect(
      (result as AppFailureResult<BitcoinMarketSnapshot>).failure.code,
      'market_payload_invalid',
    );
  });

  test('rejects zero and positive prices that round to zero', () async {
    for (final invalidPrice in <num>[0, 0.004]) {
      final transport = _transport((request) async {
        if (request.url.path.endsWith('/range')) {
          return _historyResponse(const []);
        }
        return _currentResponse(
          currency: 'usd',
          bitcoin: invalidPrice,
          tether: 1,
          observedAt: recentLast,
        );
      });

      final result = await BitcoinMarketRepository(
        transport,
        MarketDataConfiguration.developmentKeyless(),
        clock: () => now,
      ).fetch(currency: _usd);
      transport.close();

      expect(
        result,
        isA<AppFailureResult<BitcoinMarketSnapshot>>(),
        reason: '$invalidPrice must not become a valid zero quote.',
      );
    }
  });

  test('discards all malformed history but retains a valid spot', () async {
    final transport = _transport((request) async {
      if (request.url.path.endsWith('/range')) {
        return http.Response('{"prices":[[1000,64000],["bad",65000]]}', 200);
      }
      return _currentResponse(
        currency: 'usd',
        bitcoin: 65000,
        tether: 1,
        observedAt: recentLast,
      );
    });
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    ).fetch(currency: _usd);
    final snapshot = (result as AppSuccess<BitcoinMarketSnapshot>).value;

    expect(snapshot.currentBitcoinPrice.minorUnits, 6500000);
    expect(snapshot.currentSource, BitcoinPriceSource.spot);
    expect(snapshot.history, isEmpty);
  });

  test(
    'bounds chart history while preserving the full source window',
    () async {
      final first = now.subtract(const Duration(hours: 24));
      final prices = List<List<num>>.generate(49, (index) {
        return [
          first.add(Duration(minutes: 30 * index)).millisecondsSinceEpoch,
          64000 + index,
        ];
      });
      final transport = _transport((request) async {
        if (request.url.path.endsWith('/range')) {
          return _historyResponse(prices);
        }
        return _currentResponse(
          currency: 'usd',
          bitcoin: 65000,
          tether: 1,
          observedAt: recentLast,
        );
      });
      addTearDown(transport.close);

      final result = await BitcoinMarketRepository(
        transport,
        MarketDataConfiguration.developmentKeyless(),
        clock: () => now,
      ).fetch(currency: _usd);
      final history =
          (result as AppSuccess<BitcoinMarketSnapshot>).value.history;

      expect(history, hasLength(24));
      expect(history.first.timestamp, first);
      expect(history.last.timestamp, now);
      for (var index = 1; index < history.length; index += 1) {
        expect(
          history[index].timestamp.isAfter(history[index - 1].timestamp),
          isTrue,
        );
      }
    },
  );

  test('rejects stale and out-of-skew prices as current', () async {
    final stale = now.subtract(const Duration(hours: 2));
    final future = now.add(
      BitcoinMarketSnapshot.maximumFutureSkew + const Duration(seconds: 1),
    );
    var currentTimestamp = stale;
    final transport = _transport((request) async {
      if (request.url.path.endsWith('/range')) {
        return _historyResponse([
          [stale.millisecondsSinceEpoch, 64000],
        ]);
      }
      return _currentResponse(
        currency: 'usd',
        bitcoin: 65000,
        tether: 1,
        observedAt: currentTimestamp,
      );
    });
    addTearDown(transport.close);
    final repository = BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    );

    expect(
      await repository.fetch(currency: _usd),
      isA<AppFailureResult<BitcoinMarketSnapshot>>(),
    );

    currentTimestamp = future;
    expect(
      await repository.fetch(currency: _usd, forceRefresh: true),
      isA<AppFailureResult<BitcoinMarketSnapshot>>(),
    );
  });

  test(
    'caches briefly, force-refreshes, and evicts beyond its bound',
    () async {
      var requestCount = 0;
      final transport = _transport((request) async {
        requestCount += 1;
        final currency = _requestedCurrency(request);
        if (request.url.path.endsWith('/range')) {
          return _historyResponse(const []);
        }
        return _currentResponse(
          currency: currency,
          bitcoin: 65000,
          tether: 1,
          observedAt: recentLast,
        );
      });
      addTearDown(transport.close);
      final repository = BitcoinMarketRepository(
        transport,
        MarketDataConfiguration.developmentKeyless(),
        clock: () => now,
      );

      await repository.fetch(currency: _usd);
      await repository.fetch(currency: _usd);
      expect(requestCount, 2);

      await repository.fetch(currency: _usd, forceRefresh: true);
      expect(requestCount, 4);

      for (final currency in [_eur, _jpy, _kwd, _gbp]) {
        await repository.fetch(currency: currency);
      }
      expect(requestCount, 12);

      await repository.fetch(currency: _usd);
      expect(requestCount, 14, reason: 'USD must be the evicted oldest entry.');
    },
  );

  test('cache expires at the exact one-minute boundary', () async {
    var clockNow = now;
    var requestCount = 0;
    final transport = _transport((request) async {
      requestCount += 1;
      if (request.url.path.endsWith('/range')) {
        return _historyResponse(const []);
      }
      return _currentResponse(
        currency: 'usd',
        bitcoin: 65000,
        tether: 1,
        observedAt: clockNow,
      );
    });
    addTearDown(transport.close);
    final repository = BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => clockNow,
    );

    await repository.fetch(currency: _usd);
    clockNow = clockNow.add(
      const Duration(minutes: 1) - const Duration(milliseconds: 1),
    );
    await repository.fetch(currency: _usd);
    expect(requestCount, 2);

    clockNow = clockNow.add(const Duration(milliseconds: 1));
    await repository.fetch(currency: _usd);
    expect(requestCount, 4);
  });

  test('cache identity includes the curated display contract', () async {
    var requestCount = 0;
    final transport = _transport((request) async {
      requestCount += 1;
      if (request.url.path.endsWith('/range')) {
        return _historyResponse(const []);
      }
      return _currentResponse(
        currency: 'usd',
        bitcoin: 65000,
        tether: 1,
        observedAt: recentLast,
      );
    });
    addTearDown(transport.close);
    final repository = BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    );
    final alternateUsd = MarketQuoteCurrency(
      code: 'USD',
      symbol: r'US$',
      minorUnitDigits: 2,
    );

    await repository.fetch(currency: _usd);
    final alternate = await repository.fetch(currency: alternateUsd);

    expect(requestCount, 4);
    expect(
      (alternate as AppSuccess<BitcoinMarketSnapshot>).value.quoteCurrency,
      alternateUsd,
    );
  });

  test('rejects unsupported or incorrectly scaled currency identities', () {
    expect(
      () => MarketQuoteCurrency(code: 'ALL', symbol: 'L', minorUnitDigits: 2),
      throwsArgumentError,
    );
    expect(
      () => MarketQuoteCurrency(code: 'JPY', symbol: '¥', minorUnitDigits: 2),
      throwsArgumentError,
    );
  });

  test('market values validate identity, chronology, and value equality', () {
    final first = BitcoinPricePoint(
      timestamp: DateTime.utc(2026, 8, 8),
      fiatMinorUnits: 6500000,
    );
    final same = BitcoinPricePoint(
      timestamp: DateTime.utc(2026, 8, 8),
      fiatMinorUnits: 6500000,
    );
    final current = FiatMarketPrice(
      minorUnits: 6600000,
      observedAt: first.timestamp,
    );

    expect(first, same);
    expect(
      BitcoinMarketSnapshot(
        quoteCurrency: _usd,
        currentBitcoinPrice: current,
        currentSource: BitcoinPriceSource.spot,
        history: [first],
      ),
      BitcoinMarketSnapshot(
        quoteCurrency: _usd,
        currentBitcoinPrice: current,
        currentSource: BitcoinPriceSource.spot,
        history: [same],
      ),
    );
    expect(
      () => BitcoinPricePoint(
        timestamp: DateTime(2026, 8, 8),
        fiatMinorUnits: 6500000,
      ),
      throwsArgumentError,
    );
    expect(
      () => BitcoinMarketSnapshot(
        quoteCurrency: _usd,
        currentBitcoinPrice: current,
        currentSource: BitcoinPriceSource.spot,
        history: [same, first],
      ),
      throwsArgumentError,
    );
    expect(
      BitcoinMarketSnapshot(
        quoteCurrency: _usd,
        currentBitcoinPrice: current,
        currentSource: BitcoinPriceSource.spot,
        history: [
          first,
          BitcoinPricePoint(
            timestamp: DateTime.utc(2026, 8, 8, 1),
            fiatMinorUnits: 6400000,
          ),
        ],
      ).changeBasisPoints,
      153,
    );
    expect(
      () => MarketQuoteCurrency(code: 'usd', symbol: r'$', minorUnitDigits: 2),
      throwsArgumentError,
    );
    expect(
      () => FiatMarketPrice(minorUnits: 0, observedAt: first.timestamp),
      throwsArgumentError,
    );
    expect(
      () => BitcoinPricePoint(timestamp: first.timestamp, fiatMinorUnits: 0),
      throwsArgumentError,
    );
  });

  test('snapshot exposes exact freshness and skew boundaries', () {
    final observedAt = DateTime.utc(2026, 8, 11, 12);
    final snapshot = BitcoinMarketSnapshot(
      quoteCurrency: _usd,
      currentBitcoinPrice: FiatMarketPrice(
        minorUnits: 6500000,
        observedAt: observedAt,
      ),
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
      snapshot.isCurrentAt(
        observedAt.subtract(BitcoinMarketSnapshot.maximumFutureSkew),
      ),
      isTrue,
    );
    expect(
      snapshot.isCurrentAt(
        observedAt.subtract(
          BitcoinMarketSnapshot.maximumFutureSkew +
              const Duration(milliseconds: 1),
        ),
      ),
      isFalse,
    );
  });

  test('repository rejects the exact maximum-age boundary', () async {
    final observedAt = now.subtract(BitcoinMarketSnapshot.maximumCurrentAge);
    final transport = _transport((request) async {
      if (request.url.path.endsWith('/range')) {
        return _historyResponse(const []);
      }
      return _currentResponse(
        currency: 'usd',
        bitcoin: 65000,
        tether: 1,
        observedAt: observedAt,
      );
    });
    addTearDown(transport.close);

    final result = await BitcoinMarketRepository(
      transport,
      MarketDataConfiguration.developmentKeyless(),
      clock: () => now,
    ).fetch(currency: _usd);

    expect(result, isA<AppFailureResult<BitcoinMarketSnapshot>>());
  });
}

final _usd = MarketQuoteCurrency(code: 'USD', symbol: r'$', minorUnitDigits: 2);
final _eur = MarketQuoteCurrency(code: 'EUR', symbol: '€', minorUnitDigits: 2);
final _jpy = MarketQuoteCurrency(code: 'JPY', symbol: '¥', minorUnitDigits: 0);
final _kwd = MarketQuoteCurrency(
  code: 'KWD',
  symbol: 'د.ك',
  minorUnitDigits: 3,
);
final _gbp = MarketQuoteCurrency(code: 'GBP', symbol: '£', minorUnitDigits: 2);

ResilientHttpClient _transport(
  Future<http.Response> Function(http.Request) handler,
) {
  return ResilientHttpClient(
    client: MockClient(handler),
    retryPolicy: RetryPolicy(maxAttempts: 1),
  );
}

String _requestedCurrency(http.Request request) {
  return request.url.queryParameters[request.url.path.endsWith('/range')
          ? 'vs_currency'
          : 'vs_currencies'] ??
      '';
}

http.Response _historyResponse(List<List<num>> prices) {
  return http.Response(jsonEncode({'prices': prices}), 200);
}

http.Response _currentResponse({
  required String currency,
  required num bitcoin,
  required num tether,
  required DateTime observedAt,
}) {
  final timestamp = observedAt.millisecondsSinceEpoch ~/ 1000;
  return http.Response(
    jsonEncode({
      'bitcoin': {currency: bitcoin, 'last_updated_at': timestamp},
      'tether': {currency: tether, 'last_updated_at': timestamp},
    }),
    200,
  );
}
