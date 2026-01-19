import 'package:dartz/dartz.dart';

import '../../../../core/core.dart';
import '../datasource/datasource.dart';
import '../models/models.dart';

/// Abstract authentication repository interface
abstract class AuthRepository {
  /// Logs in with email and password
  ///
  /// [request] - Login request containing email and password
  ///
  /// Returns AuthResponse with token and user info on success
  ///
  /// Returns Failure on error (network, server, or unknown)
  Future<Result<AuthResponse>> login(LoginRequest request);

  /// Verifies email with verification code
  ///
  /// [request] - Verify request containing email and code
  ///
  /// Returns AuthResponse with token and user info on success
  ///
  /// Returns Failure on error (network, server, or unknown)
  Future<Result<AuthResponse>> verify(VerifyRequest request);

  /// Logs out the current user
  ///
  /// Clears the access token from secure storage
  ///
  /// Returns success or failure result
  Future<Result<void>> logout();

  /// Retrieves the current access token from secure storage
  ///
  /// Returns the token if found, null otherwise
  Future<String?> getAccessToken();

  /// Saves access token to secure storage
  ///
  /// [token] - The access token to save
  ///
  /// Returns success or failure result
  Future<Result<void>> saveAccessToken(String token);

  /// Clears the access token from secure storage
  ///
  /// Returns success or failure result
  Future<Result<void>> clearAccessToken();
}

/// Implementation of AuthRepository
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required AuthApiService apiService,
    required SecureStorageService secureStorage,
    required NetworkInfo networkInfo,
  }) : _apiService = apiService,
       _secureStorage = secureStorage,
       _networkInfo = networkInfo;

  final AuthApiService _apiService;
  final SecureStorageService _secureStorage;
  final NetworkInfo _networkInfo;

  static const String _tokenKey = 'auth_token';

  /// Logs in with email and password
  ///
  /// [request] - Login request containing email and password
  ///
  /// Returns AuthResponse with token and user info on success
  ///
  /// Returns Failure on error (network, server, or unknown)
  @override
  Future<Result<AuthResponse>> login(LoginRequest request) async {
    try {
      // Check network connectivity
      if (!await _networkInfo.isConnected) {
        return const Left(Failure.network(message: 'No internet connection'));
      }

      // Make API call
      final response = await _apiService.login(request);

      if (response.isSuccessful && response.body != null) {
        final authResponse = response.body!;

        // Save token to secure storage
        await saveAccessToken(authResponse.token);

        return Right(authResponse);
      } else {
        return Left(
          Failure.server(
            message: response.error?.toString() ?? 'Login failed',
            statusCode: response.statusCode,
          ),
        );
      }
    } on NetworkException catch (e) {
      return Left(Failure.network(message: e.message));
    } on ServerException catch (e) {
      return Left(Failure.server(message: e.message));
    } catch (e) {
      return Left(Failure.unknown(message: e.toString()));
    }
  }

  /// Verifies email with verification code
  ///
  /// [request] - Verify request containing email and code
  ///
  /// Returns AuthResponse with token and user info on success
  ///
  /// Returns Failure on error (network, server, or unknown)
  @override
  Future<Result<AuthResponse>> verify(VerifyRequest request) async {
    try {
      // Check network connectivity
      if (!await _networkInfo.isConnected) {
        return const Left(Failure.network(message: 'No internet connection'));
      }

      // Make API call
      final response = await _apiService.verify(request);

      if (response.isSuccessful && response.body != null) {
        final authResponse = response.body!;

        // Save token to secure storage
        await saveAccessToken(authResponse.token);

        return Right(authResponse);
      } else {
        return Left(
          Failure.server(
            message: response.error?.toString() ?? 'Verification failed',
            statusCode: response.statusCode,
          ),
        );
      }
    } on NetworkException catch (e) {
      return Left(Failure.network(message: e.message));
    } on ServerException catch (e) {
      return Left(Failure.server(message: e.message));
    } catch (e) {
      return Left(Failure.unknown(message: e.toString()));
    }
  }

  /// Logs out the current user
  ///
  /// Clears the access token from secure storage
  ///
  /// Returns success or failure result
  @override
  Future<Result<void>> logout() async {
    try {
      await clearAccessToken();
      return const Right(null);
    } catch (e) {
      return Left(Failure.unknown(message: e.toString()));
    }
  }

  /// Retrieves the current access token from secure storage
  ///
  /// Returns the token if found, null otherwise
  @override
  Future<String?> getAccessToken() async {
    try {
      return await _secureStorage.read(key: _tokenKey);
    } catch (e) {
      return null;
    }
  }

  /// Saves access token to secure storage
  ///
  /// [token] - The access token to save
  ///
  /// Returns success or failure result
  @override
  Future<Result<void>> saveAccessToken(String token) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
      return const Right(null);
    } catch (e) {
      return Left(Failure.cache(message: 'Failed to save token: $e'));
    }
  }

  /// Clears the access token from secure storage
  ///
  /// Returns success or failure result
  @override
  Future<Result<void>> clearAccessToken() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
      return const Right(null);
    } catch (e) {
      return Left(Failure.cache(message: 'Failed to clear token: $e'));
    }
  }
}
