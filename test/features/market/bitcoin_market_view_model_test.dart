import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/market/domain/models/models.dart';
import 'package:aster/features/market/presentation/view_model/view_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('ignores retry while the initial market request is active', () async {
    final releaseResponses = Completer<void>();
    final requestsStarted = Completer<void>();
    var requestCount = 0;
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        requestCount += 1;
        if (requestCount == 2 && !requestsStarted.isCompleted) {
          requestsStarted.complete();
        }
        await releaseResponses.future;
        final now = DateTime.now().toUtc();
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            '{"prices":[[${now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch},64000],'
            '[${now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch},65000]]}',
            200,
          );
        }
        return http.Response(
          '{"bitcoin":{"usd":65000,"last_updated_at":'
          '${now.millisecondsSinceEpoch ~/ 1000}}}',
          200,
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    final container = ProviderContainer(
      overrides: [
        resilientHttpClientProvider.overrideWithValue(transport),
        selectedMarketQuoteCurrencyProvider.overrideWith(
          (ref) async => MarketQuoteCurrency(
            code: 'USD',
            symbol: r'$',
            minorUnitDigits: 2,
          ),
        ),
      ],
    );
    final subscription = container.listen(
      bitcoinMarketViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      if (!releaseResponses.isCompleted) releaseResponses.complete();
      subscription.close();
      container.dispose();
      transport.close();
    });

    await requestsStarted.future;
    final retry = container
        .read(bitcoinMarketViewModelProvider.notifier)
        .retry();
    await retry;
    expect(requestCount, 2);

    releaseResponses.complete();
    await container.read(bitcoinMarketViewModelProvider.future);

    expect(requestCount, 2);
  });

  test(
    'rebuilds with the newly selected currency without reusing USD',
    () async {
      var selected = _currency('USD', r'$');
      final requests = <String>[];
      final transport = ResilientHttpClient(
        client: MockClient((request) async {
          final parameter = request.url.path.endsWith('/range')
              ? 'vs_currency'
              : 'vs_currencies';
          final currency = request.url.queryParameters[parameter]!;
          requests.add(currency);
          final now = DateTime.now().toUtc();
          if (request.url.path.endsWith('/range')) {
            return http.Response(
              '{"prices":[[${now.millisecondsSinceEpoch},64000]]}',
              200,
            );
          }
          return http.Response(
            '{"bitcoin":{"$currency":65000,"last_updated_at":'
            '${now.millisecondsSinceEpoch ~/ 1000}},'
            '"tether":{"$currency":1,"last_updated_at":'
            '${now.millisecondsSinceEpoch ~/ 1000}}}',
            200,
          );
        }),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      final container = ProviderContainer(
        overrides: [
          resilientHttpClientProvider.overrideWithValue(transport),
          selectedMarketQuoteCurrencyProvider.overrideWith(
            (ref) async => selected,
          ),
        ],
      );
      addTearDown(() {
        container.dispose();
        transport.close();
      });

      final usd = await container.read(bitcoinMarketViewModelProvider.future);
      expect(usd.quoteCurrency.code, 'USD');

      selected = _currency('EUR', '€');
      container.invalidate(selectedMarketQuoteCurrencyProvider);
      final eur = await container.read(bitcoinMarketViewModelProvider.future);

      expect(eur.quoteCurrency.code, 'EUR');
      expect(requests, ['usd', 'usd', 'eur', 'eur']);
    },
  );

  test('a stale retry cannot overwrite a newer currency build', () async {
    var selected = _currency('USD', r'$');
    var usdRequests = 0;
    final staleRetryStarted = Completer<void>();
    final releaseStaleRetry = Completer<void>();
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        final parameter = request.url.path.endsWith('/range')
            ? 'vs_currency'
            : 'vs_currencies';
        final currency = request.url.queryParameters[parameter]!;
        if (currency == 'usd') {
          usdRequests += 1;
          if (usdRequests > 2) {
            if (usdRequests == 4 && !staleRetryStarted.isCompleted) {
              staleRetryStarted.complete();
            }
            await releaseStaleRetry.future;
          }
        }
        final now = DateTime.now().toUtc();
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            '{"prices":[[${now.millisecondsSinceEpoch},64000]]}',
            200,
          );
        }
        return http.Response(
          '{"bitcoin":{"$currency":65000,"last_updated_at":'
          '${now.millisecondsSinceEpoch ~/ 1000}},'
          '"tether":{"$currency":1,"last_updated_at":'
          '${now.millisecondsSinceEpoch ~/ 1000}}}',
          200,
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    final container = ProviderContainer(
      overrides: [
        resilientHttpClientProvider.overrideWithValue(transport),
        selectedMarketQuoteCurrencyProvider.overrideWith(
          (ref) async => selected,
        ),
      ],
    );
    final subscription = container.listen(
      bitcoinMarketViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      if (!releaseStaleRetry.isCompleted) releaseStaleRetry.complete();
      subscription.close();
      container.dispose();
      transport.close();
    });

    expect(
      (await container.read(bitcoinMarketViewModelProvider.future))
          .quoteCurrency
          .code,
      'USD',
    );
    final retry = container
        .read(bitcoinMarketViewModelProvider.notifier)
        .retry();
    await staleRetryStarted.future;

    selected = _currency('EUR', '€');
    container.invalidate(selectedMarketQuoteCurrencyProvider);
    await container.read(selectedMarketQuoteCurrencyProvider.future);
    final eur = await container.read(bitcoinMarketViewModelProvider.future);
    releaseStaleRetry.complete();
    await retry;

    expect(eur.quoteCurrency.code, 'EUR');
    expect(
      container.read(bitcoinMarketViewModelProvider).requireValue.quoteCurrency,
      selected,
    );
  });
}

MarketQuoteCurrency _currency(String code, String symbol) =>
    MarketQuoteCurrency(code: code, symbol: symbol, minorUnitDigits: 2);
