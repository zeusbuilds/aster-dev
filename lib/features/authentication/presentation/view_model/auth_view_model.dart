import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/models/models.dart';
import '../providers/providers.dart';
import 'auth_state.dart';

part 'auth_view_model.g.dart';

/// ViewModel for managing authentication state and operations
///
/// Handles login, email verification, logout, and manages authentication state
///
/// including loading states, error messages, and user information
@riverpod
class AuthViewModel extends _$AuthViewModel {
  @override
  AuthState build() => const AuthState();

  /// Logs in with email and password
  ///
  /// [email] - User email address
  ///
  /// [password] - User password
  ///
  /// Updates state with loading, success, or error messages
  Future<void> login(String email, String password) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      successMessage: null,
    );

    final repository = ref.read(authRepositoryProvider);
    final request = LoginRequest(email: email, password: password);
    final result = await repository.login(request);

    result.fold(
      (failure) => state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
      ),
      (authResponse) => state = state.copyWith(
        isLoading: false,
        isLoginStep: false,
        successMessage:
            authResponse.message ??
            'Login successful! Check your email for verification code.',
      ),
    );
  }

  /// Verifies email with verification code
  ///
  /// [email] - User email address
  ///
  /// [code] - Verification code from email
  ///
  /// Updates state with authentication status and user info
  Future<void> verify(String email, String code) async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      successMessage: null,
    );

    final repository = ref.read(authRepositoryProvider);
    final request = VerifyRequest(email: email, code: code);
    final result = await repository.verify(request);

    result.fold(
      (failure) => state = state.copyWith(
        isLoading: false,
        errorMessage: failure.message,
      ),
      (authResponse) {
        final user = UserModel(
          id: authResponse.userId,
          email: authResponse.email,
        );

        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          user: user,
          successMessage: 'Verification successful!',
        );
      },
    );
  }

  /// Logs out the current user
  ///
  /// Clears authentication state and removes access token
  Future<void> logout() async {
    final repository = ref.read(authRepositoryProvider);
    await repository.logout();

    state = const AuthState();
  }

  /// Clears the current error message from state
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  /// Clears the current success message from state
  void clearSuccess() {
    state = state.copyWith(successMessage: null);
  }
}
