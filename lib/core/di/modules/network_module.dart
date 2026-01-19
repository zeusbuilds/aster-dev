import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/constants.dart';

/// Network module for dependency injection
class NetworkModule {
  /// Sets up network-related providers
  ///
  /// [container] - The provider container to set up providers in
  ///
  /// Note: Network providers are already set up in providers.dart.
  ///
  /// This method can be extended for additional network-related setup.
  static void setup(ProviderContainer container) {
    // Network providers are already set up in providers.dart
    // This module can be extended for additional network-related setup
  }

  /// Gets Chopper client with authentication
  ///
  /// Chopper-compatible interceptors are implemented below for auth and error handling
  static ChopperClient getChopperClient(
    Ref ref, {
    String? Function()? getAccessToken,
    void Function()? onUnauthorized,
    bool enableLogging = false,
  }) {
    final requestInterceptors = <RequestInterceptor>[];
    final responseInterceptors = <ResponseInterceptor>[];

    if (enableLogging) {
      requestInterceptors.add(HttpLoggingInterceptor());
    }

    // Add auth interceptor if token getter is provided
    if (getAccessToken != null) {
      requestInterceptors.add(
        _AuthRequestInterceptor(getAccessToken: getAccessToken),
      );
    }

    // Add error interceptor if callback is provided
    if (onUnauthorized != null) {
      responseInterceptors.add(
        _ErrorResponseInterceptor(onUnauthorized: onUnauthorized),
      );
    }

    return ChopperClient(
      baseUrl: Uri.parse(ApiEndpoints.baseUrl),
      interceptors: [...requestInterceptors, ...responseInterceptors],
      converter: const JsonConverter(),
      errorConverter: const JsonConverter(),
    );
  }
}

/// Chopper-compatible auth request interceptor
class _AuthRequestInterceptor implements RequestInterceptor {
  _AuthRequestInterceptor({required this.getAccessToken});

  final String? Function() getAccessToken;

  @override
  Future<Request> onRequest(Request request) async {
    final token = getAccessToken();
    if (token != null) {
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

/// Chopper-compatible error response interceptor
class _ErrorResponseInterceptor implements ResponseInterceptor {
  _ErrorResponseInterceptor({this.onUnauthorized});

  final void Function()? onUnauthorized;

  @override
  Future<Response> onResponse(Response response) async {
    if (response.statusCode == 401) {
      onUnauthorized?.call();
    }
    return response;
  }
}
