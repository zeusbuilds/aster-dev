import 'package:chopper/chopper.dart';

/// Chopper interceptor for handling errors
class ErrorInterceptor implements ResponseInterceptor {
  ErrorInterceptor({this.onUnauthorized});

  final void Function()? onUnauthorized;

  /// Intercepts incoming responses and handles 401 unauthorized errors
  ///
  /// [response] - The incoming HTTP response
  ///
  /// Calls [onUnauthorized] callback if response status is 401
  ///
  /// Returns the response unchanged
  @override
  Future<Response> onResponse(Response response) async {
    if (response.statusCode == 401) {
      // Handle unauthorized - trigger logout or token refresh
      onUnauthorized?.call();
    }

    return response;
  }
}
