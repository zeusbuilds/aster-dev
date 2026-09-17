import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/market/domain/models/models.dart';
import 'package:aster/features/market/presentation/models/models.dart';
import 'package:aster/features/market/presentation/view_model/view_models.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/features/settings/presentation/models/models.dart';
import 'package:aster/features/settings/presentation/view_model/view_models.dart';
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
      retry: (retryCount, error) => null,
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
    'market failure is retained silently and can recover explicitly',
    () async {
      var requestCount = 0;
      final transport = ResilientHttpClient(
        client: MockClient((request) async {
          requestCount += 1;
          if (requestCount <= 2) {
            return http.Response('temporarily unavailable', 503);
          }
          final now = DateTime.now().toUtc();
          if (request.url.path.endsWith('/range')) {
            return http.Response(
              '{"prices":[[${now.millisecondsSinceEpoch},64000]]}',
              200,
            );
          }
          return http.Response(
            '{"bitcoin":{"usd":65000,"last_updated_at":'
            '${now.millisecondsSinceEpoch ~/ 1000}},'
            '"tether":{"usd":1,"last_updated_at":'
            '${now.millisecondsSinceEpoch ~/ 1000}}}',
            200,
          );
        }),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          resilientHttpClientProvider.overrideWithValue(transport),
          selectedMarketQuoteCurrencyProvider.overrideWith(
            (ref) async => _currency('USD', r'$'),
          ),
        ],
      );
      final subscription = container.listen(
        bitcoinMarketViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
        transport.close();
      });

      final failed = await container.read(
        bitcoinMarketViewModelProvider.future,
      );
      expect(failed.snapshot, isNull);
      expect(failed.refreshFailure?.code, 'http_server_unavailable');

      await container.read(bitcoinMarketViewModelProvider.notifier).retry();

      final recovered = container
          .read(bitcoinMarketViewModelProvider)
          .requireValue;
      expect(recovered.snapshot, isNotNull);
      expect(requestCount, 4);
    },
  );

  test('market failure retries automatically after bounded backoff', () async {
    final retryStarted = Completer<void>();
    final releaseRetry = Completer<void>();
    var requestCount = 0;
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        requestCount += 1;
        if (requestCount <= 2) {
          return http.Response('temporarily unavailable', 503);
        }
        if (requestCount == 4 && !retryStarted.isCompleted) {
          retryStarted.complete();
        }
        await releaseRetry.future;
        final now = DateTime.now().toUtc();
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            '{"prices":[[${now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch},64000],'
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
      retry: (retryCount, error) => null,
      overrides: [
        resilientHttpClientProvider.overrideWithValue(transport),
        bitcoinMarketBackgroundRetryPolicyProvider.overrideWithValue(
          RetryPolicy(
            maxAttempts: 1,
            baseDelay: Duration.zero,
            maximumDelay: Duration.zero,
            jitterFactor: 0,
          ),
        ),
        selectedMarketQuoteCurrencyProvider.overrideWith(
          (ref) async => _currency('USD', r'$'),
        ),
      ],
    );
    final subscription = container.listen(
      bitcoinMarketViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      if (!releaseRetry.isCompleted) releaseRetry.complete();
      subscription.close();
      container.dispose();
      transport.close();
    });

    final failed = await container.read(bitcoinMarketViewModelProvider.future);
    expect(failed.snapshot, isNull);
    expect(failed.refreshFailure?.kind, AppFailureKind.unavailable);

    await retryStarted.future;
    final retrying = container
        .read(bitcoinMarketViewModelProvider)
        .requireValue;
    expect(retrying.refreshing, isTrue);
    expect(retrying.refreshFailure?.kind, AppFailureKind.unavailable);

    releaseRetry.complete();
    for (var attempt = 0; attempt < 20; attempt += 1) {
      await container.pump();
      if (container.read(bitcoinMarketViewModelProvider).value?.snapshot !=
          null) {
        break;
      }
    }

    final recovered = container
        .read(bitcoinMarketViewModelProvider)
        .requireValue;
    expect(recovered.snapshot, isNotNull);
    expect(recovered.refreshFailure, isNull);
    expect(requestCount, 4);
  });

  test(
    'resuming observation defers retry outside Riverpod callbacks',
    () async {
      var requestCount = 0;
      final transport = ResilientHttpClient(
        client: MockClient((request) async {
          requestCount += 1;
          return http.Response('temporarily unavailable', 503);
        }),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          resilientHttpClientProvider.overrideWithValue(transport),
          bitcoinMarketBackgroundRetryPolicyProvider.overrideWithValue(
            RetryPolicy(
              maxAttempts: 1,
              baseDelay: const Duration(minutes: 5),
              maximumDelay: const Duration(minutes: 5),
              jitterFactor: 0,
            ),
          ),
          selectedMarketQuoteCurrencyProvider.overrideWith(
            (ref) async => _currency('USD', r'$'),
          ),
        ],
      );
      final initialSubscription = container.listen(
        bitcoinMarketViewModelProvider,
        (_, _) {},
        fireImmediately: true,
      );
      ProviderSubscription<AsyncValue<BitcoinMarketState>>? resumedSubscription;
      addTearDown(() {
        resumedSubscription?.close();
        initialSubscription.close();
        container.dispose();
        transport.close();
      });

      final failed = await container.read(
        bitcoinMarketViewModelProvider.future,
      );
      expect(failed.refreshFailure?.kind, AppFailureKind.unavailable);
      expect(requestCount, 2);

      initialSubscription.close();
      expect(
        () => resumedSubscription = container.listen(
          bitcoinMarketViewModelProvider,
          (_, _) {},
          fireImmediately: true,
        ),
        returnsNormally,
      );
      await container.pump();

      expect(requestCount, 2);
      expect(
        container
            .read(bitcoinMarketViewModelProvider)
            .requireValue
            .refreshFailure
            ?.kind,
        AppFailureKind.unavailable,
      );
    },
  );

  test('loaded refresh retains confirmed content and typed failure', () async {
    final now = DateTime.utc(2026, 8, 18, 12);
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    var requestCount = 0;
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        requestCount += 1;
        if (requestCount > 2) {
          if (requestCount == 4 && !refreshStarted.isCompleted) {
            refreshStarted.complete();
          }
          await releaseRefresh.future;
          return http.Response('temporarily unavailable', 503);
        }
        if (request.url.path.endsWith('/range')) {
          return http.Response(
            '{"prices":[[${now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch},64000],'
            '[${now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch},65000]]}',
            200,
          );
        }
        return http.Response(
          '{"bitcoin":{"usd":65000,"last_updated_at":'
          '${now.millisecondsSinceEpoch ~/ 1000}},'
          '"tether":{"usd":1,"last_updated_at":'
          '${now.millisecondsSinceEpoch ~/ 1000}}}',
          200,
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
      clock: () => now,
    );
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        utcClockProvider.overrideWithValue(() => now),
        resilientHttpClientProvider.overrideWithValue(transport),
        selectedMarketQuoteCurrencyProvider.overrideWith(
          (ref) async => _currency('USD', r'$'),
        ),
      ],
    );
    final subscription = container.listen(
      bitcoinMarketViewModelProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() {
      if (!releaseRefresh.isCompleted) releaseRefresh.complete();
      subscription.close();
      container.dispose();
      transport.close();
    });

    final initial = await container.read(bitcoinMarketViewModelProvider.future);
    final refresh = container
        .read(bitcoinMarketViewModelProvider.notifier)
        .retry();
    await refreshStarted.future;

    final refreshing = container
        .read(bitcoinMarketViewModelProvider)
        .requireValue;
    expect(refreshing.snapshot, initial.snapshot);
    expect(refreshing.refreshing, isTrue);
    expect(refreshing.refreshFailure, isNull);

    releaseRefresh.complete();
    await refresh;

    final failed = container.read(bitcoinMarketViewModelProvider).requireValue;
    expect(failed.snapshot, initial.snapshot);
    expect(failed.refreshing, isFalse);
    expect(failed.refreshFailure?.retryable, isTrue);
  });

  test(
    'configuration failure stays silent and explicit retry is safe',
    () async {
      var requestCount = 0;
      final transport = ResilientHttpClient(
        client: MockClient((request) async {
          requestCount += 1;
          return http.Response('unexpected request', 500);
        }),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          resilientHttpClientProvider.overrideWithValue(transport),
          marketDataConfigurationProvider.overrideWithValue(
            MarketDataConfiguration.resolve(
              configuredBase: '',
              releaseMode: true,
            ),
          ),
          selectedMarketQuoteCurrencyProvider.overrideWith(
            (ref) async => _currency('USD', r'$'),
          ),
        ],
      );
      final transitions = <AsyncValue<BitcoinMarketState>>[];
      final subscription = container.listen(
        bitcoinMarketViewModelProvider,
        (_, next) => transitions.add(next),
        fireImmediately: true,
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
        transport.close();
      });

      final failed = await container.read(
        bitcoinMarketViewModelProvider.future,
      );
      expect(failed.snapshot, isNull);
      expect(failed.refreshFailure?.kind, AppFailureKind.configuration);
      transitions.clear();

      await container.read(bitcoinMarketViewModelProvider.notifier).retry();

      expect(transitions, hasLength(2));
      final retried = container
          .read(bitcoinMarketViewModelProvider)
          .requireValue;
      expect(retried.snapshot, isNull);
      expect(retried.refreshing, isFalse);
      expect(retried.refreshFailure?.kind, AppFailureKind.configuration);
      expect(requestCount, 0);
    },
  );

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
      expect(usd.snapshot!.quoteCurrency.code, 'USD');

      selected = _currency('EUR', '€');
      container.invalidate(selectedMarketQuoteCurrencyProvider);
      final eur = await container.read(bitcoinMarketViewModelProvider.future);

      expect(eur.snapshot!.quoteCurrency.code, 'EUR');
      expect(requests, ['usd', 'usd', 'eur', 'eur']);
    },
  );

  test(
    'projects Settings updates onto selected currency identity only',
    () async {
      final now = DateTime.utc(2026, 8, 16, 12);
      final initialSettings = _settingsState();
      final settings = _MutableSettingsViewModel(initialSettings);
      final requests = <String>[];
      final transport = ResilientHttpClient(
        client: MockClient((request) async {
          final parameter = request.url.path.endsWith('/range')
              ? 'vs_currency'
              : 'vs_currencies';
          final currency = request.url.queryParameters[parameter]!;
          requests.add(currency);
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
        retry: (retryCount, error) => null,
        overrides: [
          utcClockProvider.overrideWithValue(() => now),
          resilientHttpClientProvider.overrideWithValue(transport),
          settingsViewModelProvider.overrideWith(() => settings),
        ],
      );
      final selectedTransitions = <AsyncValue<MarketQuoteCurrency>>[];
      final marketTransitions = <AsyncValue<BitcoinMarketState>>[];
      final selectedSubscription = container.listen(
        selectedMarketQuoteCurrencyProvider,
        (_, next) => selectedTransitions.add(next),
        fireImmediately: true,
      );
      final marketSubscription = container.listen(
        bitcoinMarketViewModelProvider,
        (_, next) => marketTransitions.add(next),
        fireImmediately: true,
      );
      addTearDown(() {
        selectedSubscription.close();
        marketSubscription.close();
        container.dispose();
        transport.close();
      });

      expect(
        (await container.read(bitcoinMarketViewModelProvider.future))
            .snapshot!
            .quoteCurrency
            .code,
        'USD',
      );
      selectedTransitions.clear();
      marketTransitions.clear();

      settings.publish(
        initialSettings.copyWith(operation: SettingsOperation.region),
      );
      await container.pump();

      expect(selectedTransitions, isEmpty);
      expect(marketTransitions, isEmpty);
      expect(requests, ['usd', 'usd']);

      settings.publish(
        SettingsState(
          snapshot: initialSettings.snapshot.copyWith(
            preferences: initialSettings.snapshot.preferences.copyWith(
              currencyCode: 'EUR',
            ),
          ),
        ),
      );
      await container.pump();
      final eur = await container.read(bitcoinMarketViewModelProvider.future);

      expect(eur.snapshot!.quoteCurrency.code, 'EUR');
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
          .snapshot!
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

    expect(eur.snapshot!.quoteCurrency.code, 'EUR');
    expect(
      container
          .read(bitcoinMarketViewModelProvider)
          .requireValue
          .snapshot!
          .quoteCurrency,
      selected,
    );
  });
}

MarketQuoteCurrency _currency(String code, String symbol) =>
    MarketQuoteCurrency(code: code, symbol: symbol, minorUnitDigits: 2);

SettingsState _settingsState() {
  return SettingsState(
    snapshot: SettingsSnapshot(
      preferences: AppPreferences.defaults,
      currencies: [
        FiatCurrency(
          name: 'United States Dollar',
          symbol: r'$',
          code: 'USD',
          countryCode: 'US',
        ),
        FiatCurrency(name: 'Euro', symbol: '€', code: 'EUR', countryCode: 'EU'),
      ],
      regions: [Region(name: 'United States', code: 'US')],
    ),
  );
}

final class _MutableSettingsViewModel extends SettingsViewModel {
  _MutableSettingsViewModel(this.initial);

  final SettingsState initial;

  @override
  Future<SettingsState> build() async => initial;

  void publish(SettingsState next) => state = AsyncData(next);
}
