import 'dart:convert';

/// Bounded successful HTTP response body.
final class HttpPayload {
  HttpPayload({required this.statusCode, required List<int> bodyBytes})
    : bodyBytes = List<int>.unmodifiable(bodyBytes);

  final int statusCode;
  final List<int> bodyBytes;

  Object? decodeJson() => jsonDecode(utf8.decode(bodyBytes));
}
