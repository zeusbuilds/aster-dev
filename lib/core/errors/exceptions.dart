/// Base exception class
abstract class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Server-related exceptions
class ServerException extends AppException {
  const ServerException(super.message);
}

/// Network-related exceptions
class NetworkException extends AppException {
  const NetworkException(super.message);
}

/// Cache-related exceptions
class CacheException extends AppException {
  const CacheException(super.message);
}

/// Authentication-related exceptions
class AuthException extends AppException {
  const AuthException(super.message);
}

/// Validation-related exceptions
class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// Unknown exceptions
class UnknownException extends AppException {
  const UnknownException(super.message);
}
