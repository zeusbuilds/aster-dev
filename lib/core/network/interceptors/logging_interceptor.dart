import 'dart:developer' as developer;

import 'package:chopper/chopper.dart';

/// Chopper interceptor for logging requests and responses
class LoggingInterceptor implements RequestInterceptor, ResponseInterceptor {
  /// Logs outgoing HTTP requests with method, URL, body, and parameters
  ///
  /// [request] - The outgoing HTTP request to log
  ///
  /// Returns the request unchanged
  @override
  Future<Request> onRequest(Request request) async {
    final method = request.method;
    final url = request.url;

    developer.log('🌐 Request: $method $url', name: 'HTTP');

    if (request.body != null) {
      developer.log('Body: ${request.body}', name: 'HTTP');
    }

    if (request.parameters.isNotEmpty) {
      developer.log('Parameters: ${request.parameters}', name: 'HTTP');
    }

    return request;
  }

  /// Logs incoming HTTP responses with status code, URL, and body
  ///
  /// [response] - The incoming HTTP response to log
  ///
  /// Returns the response unchanged
  @override
  Future<Response> onResponse(Response response) async {
    final statusCode = response.statusCode;
    final url = response.base.request?.url;

    if (statusCode >= 200 && statusCode < 300) {
      developer.log('✅ Response: $statusCode $url', name: 'HTTP');
    } else {
      developer.log(
        '❌ Response: $statusCode $url',
        name: 'HTTP',
        error: response.error,
      );
    }

    if (response.body != null) {
      developer.log('Body: ${response.body}', name: 'HTTP');
    }

    return response;
  }
}
