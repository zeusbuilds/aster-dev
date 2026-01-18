import 'package:freezed_annotation/freezed_annotation.dart';

part 'failures.freezed.dart';

/// Base failure class for error handling
@freezed
class Failure with _$Failure {
  const factory Failure.server({
    @Default('Server error') String message,
    int? statusCode,
  }) = ServerFailure;

  const factory Failure.network({@Default('Network error') String message}) =
      NetworkFailure;

  const factory Failure.cache({@Default('Cache error') String message}) =
      CacheFailure;

  const factory Failure.auth({
    @Default('Authentication error') String message,
  }) = AuthFailure;

  const factory Failure.validation({
    @Default('Validation error') String message,
  }) = ValidationFailure;

  const factory Failure.unknown({@Default('Unknown error') String message}) =
      UnknownFailure;
}
