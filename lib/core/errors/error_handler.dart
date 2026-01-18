import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'failures.dart';

/// Handles errors and converts them to Failures
class ErrorHandler {
  ErrorHandler._();

  /// Converts exceptions to failures
  static Failure handleException(dynamic exception) {
    if (exception is ServerException) {
      return Failure.server(message: exception.message);
    }
    if (exception is NetworkException) {
      return Failure.network(message: exception.message);
    }
    if (exception is CacheException) {
      return Failure.cache(message: exception.message);
    }
    if (exception is AuthException) {
      return Failure.auth(message: exception.message);
    }
    if (exception is ValidationException) {
      return Failure.validation(message: exception.message);
    }
    if (exception is http.ClientException) {
      return Failure.network(message: exception.message);
    }
    if (exception is TimeoutException) {
      return Failure.network(message: 'Request timeout');
    }
    if (exception is SocketException) {
      return Failure.network(message: 'No internet connection');
    }

    return Failure.unknown(message: exception.toString());
  }

  /// Handles HTTP response errors
  static Failure handleHttpResponse(http.Response response) {
    final statusCode = response.statusCode;

    if (statusCode == 401) {
      return Failure.auth(message: 'Unauthorized');
    }
    if (statusCode == 403) {
      return Failure.auth(message: 'Forbidden');
    }
    if (statusCode == 404) {
      return Failure.server(message: 'Not found', statusCode: statusCode);
    }
    if (statusCode >= 500) {
      return Failure.server(message: 'Server error', statusCode: statusCode);
    }

    return Failure.server(
      message: response.body.isNotEmpty ? response.body : 'Server error',
      statusCode: statusCode,
    );
  }
}
