import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../errors/errors.dart';
import 'http_payload.dart';
import 'network_cancellation.dart';
import 'network_timeout_policy.dart';
import 'retry_policy.dart';

/// HTTP adapter with bounded bodies, explicit deadlines, and GET-only retry.
final class ResilientHttpClient {
  ResilientHttpClient({
    http.Client? client,
    this.timeouts = const NetworkTimeoutPolicy(),
    RetryPolicy? retryPolicy,
    this.maximumResponseBytes = 1024 * 1024,
  }) : _client = client ?? http.Client(),
       _retryPolicy = retryPolicy ?? RetryPolicy() {
    if (maximumResponseBytes < 1) {
      throw ArgumentError.value(
        maximumResponseBytes,
        'maximumResponseBytes',
        'Must be positive.',
      );
    }
    if (timeouts.connect <= Duration.zero ||
        timeouts.receive <= Duration.zero ||
        timeouts.operation <= Duration.zero) {
      throw ArgumentError('Network timeouts must be positive.');
    }
  }

  final http.Client _client;
  final NetworkTimeoutPolicy timeouts;
  final RetryPolicy _retryPolicy;
  final int maximumResponseBytes;
  bool _closed = false;

  /// Performs an idempotent GET. Only transient transport/HTTP failures retry.
  Future<AppResult<HttpPayload>> get(
    Uri uri, {
    Map<String, String> headers = const {},
    NetworkCancellationToken? cancellation,
  }) {
    if (_closed) return Future.value(_clientClosed());
    final policyFailure = _requestPolicyFailure(uri);
    if (policyFailure != null) {
      return Future.value(AppResult.failure(policyFailure));
    }
    if (cancellation?.isCancelled ?? false) {
      return Future.value(_cancelled());
    }
    return _getWithRetry(uri, headers, cancellation);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  Future<AppResult<HttpPayload>> _getWithRetry(
    Uri uri,
    Map<String, String> headers,
    NetworkCancellationToken? cancellation,
  ) async {
    final operationClock = Stopwatch()..start();
    AppFailure? latestFailure;
    for (var attempt = 0; attempt < _retryPolicy.maxAttempts; attempt += 1) {
      if (_closed) return _clientClosed();
      if (cancellation?.isCancelled ?? false) return _cancelled();
      final remaining = timeouts.operation - operationClock.elapsed;
      if (remaining <= Duration.zero) return _operationTimeout();
      final result = await _singleGet(uri, headers, remaining, cancellation);
      if (result case AppSuccess<HttpPayload>()) return result;
      latestFailure = (result as AppFailureResult<HttpPayload>).failure;
      final hasAnotherAttempt = attempt + 1 < _retryPolicy.maxAttempts;
      if (!latestFailure.retryable || !hasAnotherAttempt) return result;
      final delay = latestFailure.retryAfter ?? _retryPolicy.delayFor(attempt);
      final waitBudget = timeouts.operation - operationClock.elapsed;
      if (waitBudget <= delay) return _operationTimeout();
      try {
        final completed = await _waitBeforeRetry(
          delay,
          waitBudget,
          cancellation,
        );
        if (!completed) return _cancelled();
      } on TimeoutException {
        return _operationTimeout();
      } catch (error, stackTrace) {
        return AppResult.failure(
          FailureMapper.from(
            error,
            stackTrace,
            fallbackCode: 'http_retry_wait_failed',
          ),
        );
      }
    }
    return AppResult.failure(latestFailure!);
  }

  Future<AppResult<HttpPayload>> _singleGet(
    Uri uri,
    Map<String, String> headers,
    Duration operationBudget,
    NetworkCancellationToken? cancellation,
  ) async {
    final requestClock = Stopwatch()..start();
    final abort = Completer<void>();
    var responseRead = false;
    try {
      final abortTrigger = cancellation == null
          ? abort.future
          : Future.any<void>([abort.future, cancellation.whenCancelled]);
      final request =
          http.AbortableRequest('GET', uri, abortTrigger: abortTrigger)
            ..followRedirects = false
            ..headers.addAll(headers);
      final connectBudget = _shorter(timeouts.connect, operationBudget);
      final response = await _client
          .send(request)
          .timeout(
            connectBudget,
            onTimeout: () {
              abort.complete();
              throw TimeoutException('HTTP connect deadline exceeded.');
            },
          );
      final remaining = operationBudget - requestClock.elapsed;
      if (remaining <= Duration.zero) {
        abort.complete();
        return _operationTimeout();
      }
      final receiveBudget = _shorter(timeouts.receive, remaining);
      final body = await _readBounded(response.stream).timeout(
        receiveBudget,
        onTimeout: () {
          abort.complete();
          throw TimeoutException('HTTP receive deadline exceeded.');
        },
      );
      responseRead = true;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AppResult.success(
          HttpPayload(statusCode: response.statusCode, bodyBytes: body),
        );
      }
      return AppResult.failure(_httpFailure(response));
    } on TimeoutException catch (error, stackTrace) {
      if (!abort.isCompleted) abort.complete();
      if (requestClock.elapsed >= operationBudget) {
        return _operationTimeout(error: error, stackTrace: stackTrace);
      }
      return AppResult.failure(
        AppFailure(
          code: 'http_timeout',
          kind: AppFailureKind.timeout,
          userMessage: 'The server took too long to respond.',
          retryable: true,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    } on HandshakeException catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'http_tls_failed',
          kind: AppFailureKind.connectivity,
          userMessage: 'A secure connection could not be established.',
          retryable: false,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    } on SocketException catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'http_offline',
          kind: AppFailureKind.connectivity,
          userMessage: 'Check your connection and try again.',
          retryable: true,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    } on http.RequestAbortedException catch (error, stackTrace) {
      if (cancellation?.isCancelled ?? false) {
        return _cancelled(error: error, stackTrace: stackTrace);
      }
      return _operationTimeout(error: error, stackTrace: stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'http_transport_failed',
          kind: AppFailureKind.connectivity,
          userMessage: 'The server could not be reached.',
          retryable: true,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    } on FormatException catch (error, stackTrace) {
      return AppResult.failure(
        AppFailure(
          code: 'http_response_invalid',
          kind: AppFailureKind.protocol,
          userMessage: 'The server returned an invalid response.',
          retryable: false,
          cause: FailureMapper.diagnosticCause(error),
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      return AppResult.failure(
        FailureMapper.from(
          error,
          stackTrace,
          fallbackCode: 'http_request_failed',
        ),
      );
    } finally {
      if (!responseRead && !abort.isCompleted) abort.complete();
    }
  }

  Future<Uint8List> _readBounded(http.ByteStream stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length + chunk.length > maximumResponseBytes) {
        throw const FormatException('HTTP response exceeded the size limit.');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static AppFailure _httpFailure(http.StreamedResponse response) {
    final status = response.statusCode;
    final retryAfter = _retryAfter(response.headers['retry-after']);
    if (status == 429) {
      return AppFailure(
        code: 'http_rate_limited',
        kind: AppFailureKind.rateLimited,
        userMessage: 'Too many requests. Try again shortly.',
        retryable: true,
        retryAfter: retryAfter,
      );
    }
    if (status == 401 || status == 403) {
      return const AppFailure(
        code: 'http_unauthorized',
        kind: AppFailureKind.authentication,
        userMessage: 'This service request was not authorized.',
        retryable: false,
      );
    }
    if (status == 404) {
      return const AppFailure(
        code: 'http_not_found',
        kind: AppFailureKind.notFound,
        userMessage: 'The requested information is unavailable.',
        retryable: false,
      );
    }
    if (status == 408) {
      return AppFailure(
        code: 'http_timeout',
        kind: AppFailureKind.timeout,
        userMessage: 'The server took too long to respond.',
        retryable: true,
        retryAfter: retryAfter,
      );
    }
    if (status == 409) {
      return const AppFailure(
        code: 'http_conflict',
        kind: AppFailureKind.conflict,
        userMessage: 'The request conflicts with the current state.',
        retryable: false,
      );
    }
    final transient = status >= 500;
    return AppFailure(
      code: transient ? 'http_server_unavailable' : 'http_request_rejected',
      kind: transient ? AppFailureKind.unavailable : AppFailureKind.validation,
      userMessage: transient
          ? 'The service is temporarily unavailable.'
          : 'The service could not process this request.',
      retryable: transient,
      retryAfter: retryAfter,
    );
  }

  static Duration? _retryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    try {
      final date = HttpDate.parse(value);
      final difference = date.difference(DateTime.now().toUtc());
      return difference.isNegative ? Duration.zero : difference;
    } on FormatException {
      return null;
    }
  }

  static Duration _shorter(Duration first, Duration second) =>
      first <= second ? first : second;

  static AppFailure? _requestPolicyFailure(Uri uri) {
    if (!uri.isAbsolute ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return const AppFailure(
        code: 'http_request_policy_rejected',
        kind: AppFailureKind.configuration,
        userMessage: 'The network service is not configured safely.',
        retryable: false,
      );
    }
    return null;
  }

  Future<bool> _waitBeforeRetry(
    Duration delay,
    Duration budget,
    NetworkCancellationToken? cancellation,
  ) async {
    final wait = _retryPolicy.wait(delay);
    if (cancellation == null) {
      await wait.timeout(budget);
      return true;
    }
    return Future.any<bool>([
      wait.then((_) => true),
      cancellation.whenCancelled.then((_) => false),
    ]).timeout(budget);
  }

  static AppResult<HttpPayload> _operationTimeout({
    Object? error,
    StackTrace? stackTrace,
  }) {
    return AppResult.failure(
      AppFailure(
        code: 'http_operation_timeout',
        kind: AppFailureKind.timeout,
        userMessage: 'The request took too long. Try again.',
        retryable: true,
        cause: error == null ? null : FailureMapper.diagnosticCause(error),
        stackTrace: stackTrace,
      ),
    );
  }

  static AppResult<HttpPayload> _cancelled({
    Object? error,
    StackTrace? stackTrace,
  }) {
    return AppResult.failure(
      AppFailure(
        code: 'http_request_cancelled',
        kind: AppFailureKind.cancelled,
        userMessage: 'The request was cancelled.',
        retryable: false,
        cause: error == null ? null : FailureMapper.diagnosticCause(error),
        stackTrace: stackTrace,
      ),
    );
  }

  static AppResult<HttpPayload> _clientClosed() {
    return const AppResult.failure(
      AppFailure(
        code: 'http_client_closed',
        kind: AppFailureKind.cancelled,
        userMessage: 'The network service is closing.',
        retryable: false,
      ),
    );
  }
}
