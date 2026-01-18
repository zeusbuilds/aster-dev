import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_response.freezed.dart';
part 'auth_response.g.dart';

/// Authentication response model
@freezed
class AuthResponse with _$AuthResponse {
  const factory AuthResponse({
    required String token,
    required String userId,
    required String email,
    String? message,
  }) = _AuthResponse;

  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);
}
