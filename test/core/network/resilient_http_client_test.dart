import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('retries transient GET with Retry-After and then succeeds', () async {
    var calls = 0;
    final waits = <Duration>[];
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        calls += 1;
        if (calls == 1) {
          return http.Response(
            'temporarily unavailable',
            429,
            headers: {'retry-after': '2'},
          );
        }
        return http.Response('{"ok":true}', 200);
      }),
      retryPolicy: RetryPolicy(
        maxAttempts: 3,
        sleep: (delay) async => waits.add(delay),
      ),
    );
    addTearDown(transport.close);

    final result = await transport.get(Uri.https('example.com', '/data'));

    expect(result, isA<AppSuccess<HttpPayload>>());
    expect(calls, 2);
    expect(waits, [const Duration(seconds: 2)]);
  });

  test('does not retry a rejected non-transient request', () async {
    var calls = 0;
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        calls += 1;
        return http.Response('bad request body must not leak', 400);
      }),
      retryPolicy: RetryPolicy(maxAttempts: 3, sleep: (_) async {}),
    );
    addTearDown(transport.close);

    final result = await transport.get(Uri.https('example.com', '/data'));

    final failure = (result as AppFailureResult<HttpPayload>).failure;
    expect(calls, 1);
    expect(failure.code, 'http_request_rejected');
    expect(failure.toString(), isNot(contains('bad request body')));
  });

  test(
    'classifies HTTP timeout and conflict without retrying conflict',
    () async {
      var conflictCalls = 0;
      final timeoutTransport = ResilientHttpClient(
        client: MockClient((_) async => http.Response('', 408)),
        retryPolicy: RetryPolicy(maxAttempts: 1),
      );
      final conflictTransport = ResilientHttpClient(
        client: MockClient((_) async {
          conflictCalls += 1;
          return http.Response('', 409);
        }),
        retryPolicy: RetryPolicy(maxAttempts: 3, sleep: (_) async {}),
      );
      addTearDown(timeoutTransport.close);
      addTearDown(conflictTransport.close);

      final timeout = await timeoutTransport.get(
        Uri.https('example.com', '/timeout'),
      );
      final conflict = await conflictTransport.get(
        Uri.https('example.com', '/conflict'),
      );

      expect(
        (timeout as AppFailureResult<HttpPayload>).failure.kind,
        AppFailureKind.timeout,
      );
      expect(
        (conflict as AppFailureResult<HttpPayload>).failure.kind,
        AppFailureKind.conflict,
      );
      expect(conflictCalls, 1);
    },
  );

  test('enforces the whole-operation deadline', () async {
    final pending = Completer<http.Response>();
    final transport = ResilientHttpClient(
      client: MockClient((request) => pending.future),
      timeouts: const NetworkTimeoutPolicy(
        connect: Duration(seconds: 1),
        receive: Duration(seconds: 1),
        operation: Duration(milliseconds: 20),
      ),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);

    final result = await transport.get(Uri.https('example.com', '/slow'));

    expect(
      (result as AppFailureResult<HttpPayload>).failure.code,
      'http_operation_timeout',
    );
  });

  test(
    'operation timeout aborts the request and prevents later retries',
    () async {
      var calls = 0;
      final pending = Completer<http.Response>();
      final transport = ResilientHttpClient(
        client: MockClient((request) {
          calls += 1;
          return pending.future;
        }),
        timeouts: const NetworkTimeoutPolicy(
          connect: Duration(seconds: 1),
          receive: Duration(seconds: 1),
          operation: Duration(milliseconds: 20),
        ),
        retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: Duration.zero),
      );
      addTearDown(transport.close);

      final result = await transport.get(Uri.https('example.com', '/slow'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        (result as AppFailureResult<HttpPayload>).failure.code,
        'http_operation_timeout',
      );
      expect(calls, 1);
    },
  );

  test('does not wait past the operation budget for Retry-After', () async {
    var calls = 0;
    var waits = 0;
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        calls += 1;
        return http.Response('', 429, headers: {'retry-after': '60'});
      }),
      timeouts: const NetworkTimeoutPolicy(
        connect: Duration(seconds: 1),
        receive: Duration(seconds: 1),
        operation: Duration(milliseconds: 50),
      ),
      retryPolicy: RetryPolicy(maxAttempts: 3, sleep: (_) async => waits += 1),
    );
    addTearDown(transport.close);

    final result = await transport.get(Uri.https('example.com', '/limited'));

    expect(
      (result as AppFailureResult<HttpPayload>).failure.code,
      'http_operation_timeout',
    );
    expect(calls, 1);
    expect(waits, 0);
  });

  test('rejects an oversized response without exposing its body', () async {
    final transport = ResilientHttpClient(
      client: MockClient((request) async => http.Response('12345', 200)),
      maximumResponseBytes: 4,
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);

    final result = await transport.get(Uri.https('example.com', '/large'));

    final failure = (result as AppFailureResult<HttpPayload>).failure;
    expect(failure.kind, AppFailureKind.protocol);
    expect(failure.toString(), isNot(contains('12345')));
  });

  test(
    'caller cancellation aborts an active request without retrying',
    () async {
      final client = _AbortAwareClient();
      final cancellation = NetworkCancellationToken();
      final transport = ResilientHttpClient(
        client: client,
        retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: Duration.zero),
      );
      addTearDown(transport.close);

      final request = transport.get(
        Uri.https('example.com', '/cancel'),
        cancellation: cancellation,
      );
      await client.started.future;
      cancellation.cancel();
      final result = await request;

      expect(
        (result as AppFailureResult<HttpPayload>).failure.code,
        'http_request_cancelled',
      );
      expect(client.calls, 1);
    },
  );

  test('caller cancellation interrupts retry backoff', () async {
    var calls = 0;
    final waiting = Completer<void>();
    final cancellation = NetworkCancellationToken();
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        calls += 1;
        return http.Response('', 503);
      }),
      retryPolicy: RetryPolicy(
        maxAttempts: 3,
        sleep: (_) {
          if (!waiting.isCompleted) waiting.complete();
          return Completer<void>().future;
        },
      ),
    );
    addTearDown(transport.close);

    final request = transport.get(
      Uri.https('example.com', '/cancel-backoff'),
      cancellation: cancellation,
    );
    await waiting.future;
    cancellation.cancel();
    final result = await request;

    expect(
      (result as AppFailureResult<HttpPayload>).failure.code,
      'http_request_cancelled',
    );
    expect(calls, 1);
  });

  test('a closed client fails through AppResult', () async {
    final transport = ResilientHttpClient(
      client: MockClient((request) async => http.Response('', 200)),
    );
    transport.close();

    final result = await transport.get(Uri.https('example.com', '/closed'));

    expect(
      (result as AppFailureResult<HttpPayload>).failure.code,
      'http_client_closed',
    );
  });

  test(
    'rejects insecure or credential-bearing request URLs before I/O',
    () async {
      var calls = 0;
      final transport = ResilientHttpClient(
        client: MockClient((request) async {
          calls += 1;
          return http.Response('', 200);
        }),
      );
      addTearDown(transport.close);

      final insecure = await transport.get(
        Uri.parse('http://example.com/data'),
      );
      final credentialed = await transport.get(
        Uri.parse('https://user:password@example.com/data'),
      );

      expect(calls, 0);
      expect(
        (insecure as AppFailureResult<HttpPayload>).failure.code,
        'http_request_policy_rejected',
      );
      expect(credentialed, isA<AppFailureResult<HttpPayload>>());
    },
  );

  test('disables automatic redirects on app-owned requests', () async {
    late bool followsRedirects;
    final transport = ResilientHttpClient(
      client: MockClient((request) async {
        followsRedirects = request.followRedirects;
        return http.Response(
          '',
          302,
          headers: {'location': 'http://example.com'},
        );
      }),
      retryPolicy: RetryPolicy(maxAttempts: 1),
    );
    addTearDown(transport.close);

    final result = await transport.get(Uri.https('example.com', '/redirect'));

    expect(followsRedirects, isFalse);
    expect(
      (result as AppFailureResult<HttpPayload>).failure.code,
      'http_request_rejected',
    );
  });

  test('rejects invalid retry and transport policies at construction', () {
    expect(() => RetryPolicy(maxAttempts: 0), throwsArgumentError);
    expect(() => RetryPolicy(maxAttempts: 11), throwsArgumentError);
    expect(
      () => RetryPolicy(
        baseDelay: const Duration(seconds: 2),
        maximumDelay: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => RetryPolicy(maximumDelay: const Duration(minutes: 6)),
      throwsArgumentError,
    );
    expect(() => RetryPolicy(jitterFactor: 1.1), throwsArgumentError);
    expect(() => RetryPolicy(jitterFactor: double.nan), throwsArgumentError);
    expect(
      () => RetryPolicy(jitterFactor: double.infinity),
      throwsArgumentError,
    );
    expect(
      () => ResilientHttpClient(maximumResponseBytes: 0),
      throwsArgumentError,
    );
    expect(
      () => ResilientHttpClient(
        timeouts: const NetworkTimeoutPolicy(operation: Duration.zero),
      ),
      throwsArgumentError,
    );
  });
}

final class _AbortAwareClient extends http.BaseClient {
  final started = Completer<void>();
  var calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls += 1;
    if (!started.isCompleted) started.complete();
    if (request case final http.Abortable abortable) {
      await abortable.abortTrigger;
      throw http.RequestAbortedException(request.url);
    }
    throw StateError('Expected an abortable request.');
  }
}
