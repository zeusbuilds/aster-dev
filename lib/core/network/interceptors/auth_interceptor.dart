import 'package:chopper/chopper.dart';

/// Chopper interceptor for adding authentication headers
class AuthInterceptor implements RequestInterceptor {
  AuthInterceptor({required this.getAccessToken});

  final String? Function() getAccessToken;

  /// Intercepts outgoing requests and adds Authorization header if token is available
  ///
  /// [request] - The outgoing HTTP request
  ///
  /// Returns the request with Authorization header added if token exists
  @override
  Future<Request> onRequest(Request request) async {
    final token = getAccessToken();

    if (token != null && token.isNotEmpty) {
      final headers = Map<String, String>.from(request.headers);
      headers['Authorization'] = 'Bearer $token';

      return Request(
        request.method,
        request.url,
        request.baseUri,
        headers: headers,
        body: request.body,
        parameters: request.parameters,
      );
    }

    return request;
  }
}
