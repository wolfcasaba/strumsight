import 'package:dio/dio.dart';

import '../foundation/app_failure.dart';
import 'transport_error_classifier.dart';

/// Converts Dio transport/status failures into the app-wide failure taxonomy.
///
/// Response bodies and request headers are deliberately ignored: neither is
/// needed to classify the failure, and both may contain credentials.
AppFailure mapNetworkFailure(
  DioException error, {
  String unauthorizedCode = FailureCode.authSessionExpired,
  String conflictCode = FailureCode.validationInvalidInput,
  StackTrace? stackTrace,
}) {
  final original = error.error;
  if (original is AppFailure) return original;

  final trace = stackTrace ?? error.stackTrace;
  final status = error.response?.statusCode;
  if (status == 401) {
    return AuthenticationFailure(
      code: unauthorizedCode,
      cause: error,
      stackTrace: trace,
    );
  }
  if (status == 403) {
    return AuthenticationFailure(
      code: FailureCode.authForbidden,
      cause: error,
      stackTrace: trace,
    );
  }
  if (status == 409) {
    return ValidationFailure(
      code: conflictCode,
      cause: error,
      stackTrace: trace,
    );
  }
  if (status == 422) {
    return ValidationFailure(cause: error, stackTrace: trace);
  }
  if (status == 408) {
    return NetworkFailure(
      code: FailureCode.networkTimeout,
      cause: error,
      stackTrace: trace,
    );
  }
  if (status == 429 || (status != null && status >= 500)) {
    return NetworkFailure(
      code: FailureCode.networkServer,
      cause: error,
      stackTrace: trace,
    );
  }
  if (status != null) {
    return NetworkFailure(
      code: FailureCode.networkBadResponse,
      retryable: false,
      cause: error,
      stackTrace: trace,
    );
  }

  if (isTlsTransportError(original)) {
    return NetworkFailure(
      code: FailureCode.networkTls,
      retryable: false,
      cause: error,
      stackTrace: trace,
    );
  }
  if (original is FormatException) {
    return NetworkFailure(
      code: FailureCode.networkBadResponse,
      retryable: false,
      cause: error,
      stackTrace: trace,
    );
  }
  if (isConnectionTransportError(original)) {
    return NetworkFailure(cause: error, stackTrace: trace);
  }

  return switch (error.type) {
    DioExceptionType.connectionError => NetworkFailure(
      cause: error,
      stackTrace: trace,
    ),
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.transformTimeout => NetworkFailure(
      code: FailureCode.networkTimeout,
      cause: error,
      stackTrace: trace,
    ),
    DioExceptionType.badCertificate => NetworkFailure(
      code: FailureCode.networkTls,
      retryable: false,
      cause: error,
      stackTrace: trace,
    ),
    DioExceptionType.cancel => CancelledFailure(
      cause: error,
      stackTrace: trace,
    ),
    DioExceptionType.badResponse => NetworkFailure(
      code: FailureCode.networkBadResponse,
      retryable: false,
      cause: error,
      stackTrace: trace,
    ),
    DioExceptionType.unknown => UnknownFailure(
      cause: original ?? error,
      stackTrace: trace,
    ),
  };
}
