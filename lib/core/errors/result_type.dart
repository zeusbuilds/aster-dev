import 'package:dartz/dartz.dart';
import 'failures.dart';

/// Result type alias for Either<Failure, T>
/// This provides a consistent way to handle success and failure cases
typedef Result<T> = Either<Failure, T>;
