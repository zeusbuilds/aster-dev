import 'app_failure.dart';

/// Result returned across repository and ViewModel boundaries.
sealed class AppResult<T> {
  const AppResult();

  const factory AppResult.success(T value) = AppSuccess<T>;
  const factory AppResult.failure(AppFailure failure) = AppFailureResult<T>;

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) {
    return switch (this) {
      AppSuccess<T>(:final value) => onSuccess(value),
      AppFailureResult<T>(:final failure) => onFailure(failure),
    };
  }
}

final class AppSuccess<T> extends AppResult<T> {
  const AppSuccess(this.value);

  final T value;
}

final class AppFailureResult<T> extends AppResult<T> {
  const AppFailureResult(this.failure);

  final AppFailure failure;
}
