import 'package:dio/dio.dart';

import '../foundation/app_failure.dart';
import '../foundation/app_result.dart';
import '../logging/app_logger.dart';

typedef AccessTokenReader = Future<AppResult<String?>> Function();
typedef SessionGenerationReader = int Function();
typedef UnauthorizedCallback = void Function(int rejectedGeneration);

/// Request metadata used to exempt public account operations from bearer auth.
abstract final class NetworkRequestMetadata {
  static const String requiresAuthentication =
      'strumsight.requires_authentication';
  static const String unauthorizedHandled = 'strumsight.unauthorized_handled';
  static const String sessionGeneration = 'strumsight.session_generation';
}

/// Attaches the stored bearer token and reports authenticated 401 responses.
///
/// The callbacks keep core independent from the auth feature. Login/register
/// set [NetworkRequestMetadata.requiresAuthentication] to false, so a bad
/// password never expires an otherwise valid session.
final class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.readToken,
    required this.readSessionGeneration,
    required this.onUnauthorized,
    required this.logger,
  });

  final AccessTokenReader readToken;
  final SessionGenerationReader readSessionGeneration;
  final UnauthorizedCallback onUnauthorized;
  final AppLogger logger;

  static bool requiresAuthentication(RequestOptions options) =>
      options.extra[NetworkRequestMetadata.requiresAuthentication] != false;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!requiresAuthentication(options)) {
      handler.next(options);
      return;
    }

    final requestGeneration = readSessionGeneration();
    final AppResult<String?> tokenResult;
    try {
      tokenResult = await readToken();
    } catch (error, stackTrace) {
      const failure = StorageFailure(code: FailureCode.storageRead);
      logger.warning(
        'auth.token_read_failed',
        error: error,
        stackTrace: stackTrace,
        fields: const {'code': FailureCode.storageRead},
      );
      handler.reject(
        DioException(
          requestOptions: options,
          error: failure,
          stackTrace: stackTrace,
        ),
        true,
      );
      return;
    }

    if (requestGeneration != readSessionGeneration()) {
      const failure = CancelledFailure();
      handler.reject(
        DioException(requestOptions: options, error: failure),
        true,
      );
      return;
    }

    switch (tokenResult) {
      case Success(:final value):
        options.headers.removeWhere(
          (name, _) => name.toLowerCase() == 'authorization',
        );
        if (value == null || value.isEmpty) {
          const failure = AuthenticationFailure(
            code: FailureCode.authSessionExpired,
          );
          handler.reject(
            DioException(requestOptions: options, error: failure),
            true,
          );
          return;
        }
        options.headers['Authorization'] = 'Bearer $value';
        options.extra[NetworkRequestMetadata.sessionGeneration] =
            requestGeneration;
        handler.next(options);
      case Failure(:final error):
        logger.warning('auth.token_read_failed', fields: {'code': error.code});
        handler.reject(
          DioException(
            requestOptions: options,
            error: error,
            stackTrace: error.stackTrace,
          ),
          true,
        );
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    final isAuthenticated401 =
        err.response?.statusCode == 401 && requiresAuthentication(options);
    final alreadyHandled =
        options.extra[NetworkRequestMetadata.unauthorizedHandled] == true;
    final requestGeneration =
        options.extra[NetworkRequestMetadata.sessionGeneration];

    if (isAuthenticated401 && !alreadyHandled && requestGeneration is int) {
      options.extra[NetworkRequestMetadata.unauthorizedHandled] = true;
      try {
        onUnauthorized(requestGeneration);
      } catch (callbackError, stackTrace) {
        logger.warning(
          'auth.session_invalidation_failed',
          error: callbackError,
          stackTrace: stackTrace,
          fields: const {'code': FailureCode.unknown},
        );
      }
    }
    handler.next(err);
  }
}
