import 'app_failure.dart';

/// The result of an operation that can fail in an *expected* way (SDD Ch2 §7.1).
///
/// Expected failures are values, not exceptions: a repository returns
/// `AppResult<T>`, so the caller cannot forget to handle the failure path and
/// the UI is never handed a transport type (`DioException`, `PlatformException`).
///
/// Deliberately small — this is not a functional-programming framework. If you
/// need more than [map] / [fold], pattern-match on the sealed type:
///
/// ```dart
/// switch (result) {
///   case Success(:final value): use(value);
///   case Failure(:final error): show(error.code);
/// }
/// ```
sealed class AppResult<T> {
  const AppResult();

  /// Wrap a successful [value].
  const factory AppResult.success(T value) = Success<T>;

  /// Wrap a failure [error].
  const factory AppResult.failure(AppFailure error) = Failure<T>;

  bool get isSuccess => this is Success<T>;

  bool get isFailure => this is Failure<T>;

  /// The value, or null when this is a [Failure]. Prefer pattern matching when
  /// `T` is itself nullable — null is then ambiguous.
  T? get valueOrNull => switch (this) {
    Success<T>(:final value) => value,
    Failure<T>() => null,
  };

  /// The failure, or null when this is a [Success].
  AppFailure? get failureOrNull => switch (this) {
    Success<T>() => null,
    Failure<T>(:final error) => error,
  };

  /// Transform a success value, passing a failure through untouched.
  AppResult<R> map<R>(R Function(T value) transform) => switch (this) {
    Success<T>(:final value) => Success<R>(transform(value)),
    Failure<T>(:final error) => Failure<R>(error),
  };

  /// Collapse both branches into one value — the standard way for UI code to
  /// consume a result.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure error) onFailure,
  }) => switch (this) {
    Success<T>(:final value) => onSuccess(value),
    Failure<T>(:final error) => onFailure(error),
  };
}

final class Success<T> extends AppResult<T> {
  const Success(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Success<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Success<T>, value);

  @override
  String toString() => 'Success<$T>($value)';
}

final class Failure<T> extends AppResult<T> {
  const Failure(this.error);

  final AppFailure error;

  @override
  bool operator ==(Object other) => other is Failure<T> && other.error == error;

  @override
  int get hashCode => Object.hash(Failure<T>, error);

  /// Only the code — [AppFailure.toString] deliberately omits the cause.
  @override
  String toString() => 'Failure<$T>(${error.code})';
}
