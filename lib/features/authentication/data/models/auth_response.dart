import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_response.freezed.dart';
part 'auth_response.g.dart';

/// Authentication response model
@freezed
class AuthResponse with _$AuthResponse {
  const factory AuthResponse({
    /// JWT access token for authenticated requests
    required String token,

    /// Unique identifier for the user
    required String userId,

    /// User's email address
    required String email,

    /// Optional message from the server (e.g., "Check your email for verification code")
    String? message,
  }) = _AuthResponse;

  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);
}
