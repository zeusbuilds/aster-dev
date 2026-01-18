import 'package:freezed_annotation/freezed_annotation.dart';
import '../../data/models/models.dart';

part 'auth_state.freezed.dart';

/// Authentication state model
/// Tracks authentication status, user info, loading state, and messages
@freezed
class AuthState with _$AuthState {
  const factory AuthState({
    /// Whether an authentication operation is in progress
    @Default(false) bool isLoading,

    /// Whether the user is currently authenticated
    @Default(false) bool isAuthenticated,

    /// Whether currently on login step (vs verification step)
    @Default(false) bool isLoginStep,

    /// Current authenticated user information
    UserModel? user,

    /// Error message if authentication failed
    String? errorMessage,

    /// Success message for successful operations
    String? successMessage,
  }) = _AuthState;
}
