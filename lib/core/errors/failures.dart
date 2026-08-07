/// Typed, user-safe failure returned by application repositories.
sealed class Failure {
  const Failure(this.message);

  const factory Failure.server({String message, int? statusCode}) =
      ServerFailure;

  const factory Failure.network({String message}) = NetworkFailure;

  const factory Failure.cache({String message}) = CacheFailure;

  const factory Failure.auth({String message}) = AuthFailure;

  const factory Failure.validation({String message}) = ValidationFailure;

  const factory Failure.unknown({String message}) = UnknownFailure;

  final String message;
}

final class ServerFailure extends Failure {
  const ServerFailure({String message = 'Server error', this.statusCode})
    : super(message);

  final int? statusCode;
}

final class NetworkFailure extends Failure {
  const NetworkFailure({String message = 'Network error'}) : super(message);
}

final class CacheFailure extends Failure {
  const CacheFailure({String message = 'Cache error'}) : super(message);
}

final class AuthFailure extends Failure {
  const AuthFailure({String message = 'Authentication error'}) : super(message);
}

final class ValidationFailure extends Failure {
  const ValidationFailure({String message = 'Validation error'})
    : super(message);
}

final class UnknownFailure extends Failure {
  const UnknownFailure({String message = 'Unknown error'}) : super(message);
}
