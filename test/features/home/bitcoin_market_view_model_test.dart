import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/home/presentation/view_model/view_models.dart';
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
      overrides: [resilientHttpClientProvider.overrideWithValue(transport)],
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
}
