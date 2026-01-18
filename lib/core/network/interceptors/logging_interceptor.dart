import 'dart:developer' as developer;
import 'package:chopper/chopper.dart';

/// Chopper interceptor for logging requests and responses
class LoggingInterceptor implements RequestInterceptor, ResponseInterceptor {
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
