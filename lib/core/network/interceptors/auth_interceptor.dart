import 'package:chopper/chopper.dart';

/// Chopper interceptor for adding authentication headers
class AuthInterceptor implements RequestInterceptor {
  AuthInterceptor({required this.getAccessToken});

  final String? Function() getAccessToken;

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
