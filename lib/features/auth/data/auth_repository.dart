import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/logger_provider.dart';
import '../model/auth_user.dart';
import 'token_store.dart';

/// Talks to the account backend. An interface so widget/unit tests inject a
/// fake without hitting the network.
///
/// Every method returns an [AppResult]: a `DioException` never leaves this
/// file (E01-R04 §4.4), and the UI localises the [AppFailure.code].
abstract interface class AuthRepository {
  /// Register, returning a usable access token (the backend auto-logs-in).
  Future<AppResult<String>> register(String email, String password);

  /// Log in, returning an access token.
  Future<AppResult<String>> login(String email, String password);

  /// The currently authenticated user (token attached by the Dio interceptor).
  Future<AppResult<AuthUser>> me();
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._dio);

  final Dio _dio;

  @override
  Future<AppResult<String>> register(String email, String password) =>
      _postForToken('/auth/register', email, password);

  @override
  Future<AppResult<String>> login(String email, String password) =>
      _postForToken('/auth/login', email, password);

  Future<AppResult<String>> _postForToken(
    String path,
    String email,
    String password,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: {'email': email, 'password': password},
      );
      final token = res.data?['access_token'];
      if (token is! String || token.isEmpty) {
        return const Failure(
          NetworkFailure(code: FailureCode.networkBadResponse),
        );
      }
      return Success(token);
    } on DioException catch (e, stackTrace) {
      return Failure(authFailureFromDio(e, stackTrace));
    } catch (e, stackTrace) {
      // Unknown is never success (§4.5).
      return Failure(UnknownFailure(cause: e, stackTrace: stackTrace));
    }
  }

  @override
  Future<AppResult<AuthUser>> me() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/auth/me');
      final data = res.data;
      if (data == null) {
        return const Failure(
          NetworkFailure(code: FailureCode.networkBadResponse),
        );
      }
      return Success(AuthUser.fromJson(data));
    } on DioException catch (e, stackTrace) {
      return Failure(authFailureFromDio(e, stackTrace));
    } catch (e, stackTrace) {
      // A malformed body reaching `fromJson` lands here — a bad response, not
      // a crash for the caller.
      return Failure(
        NetworkFailure(
          code: FailureCode.networkBadResponse,
          retryable: false,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

/// Maps a Dio transport error onto the unified failure taxonomy.
///
/// Lives here for now; it moves to `core/network/` when the shared API client
/// lands (SDD Ch2 §6). Deliberately keeps the response body out of the failure
/// — only the status code shapes the decision.
AppFailure authFailureFromDio(DioException e, [StackTrace? stackTrace]) {
  final status = e.response?.statusCode;
  if (status == 401) {
    return AuthenticationFailure(
      code: FailureCode.authInvalidCredentials,
      cause: e,
      stackTrace: stackTrace,
    );
  }
  if (status == 403) {
    return AuthenticationFailure(
      code: FailureCode.authForbidden,
      cause: e,
      stackTrace: stackTrace,
    );
  }
  if (status == 409) {
    // A conflict is an input problem (that e-mail is taken), not a failed
    // authentication — hence ValidationFailure.
    return ValidationFailure(
      code: FailureCode.validationEmailTaken,
      cause: e,
      stackTrace: stackTrace,
    );
  }
  if (status != null && status >= 500) {
    return NetworkFailure(
      code: FailureCode.networkServer,
      cause: e,
      stackTrace: stackTrace,
    );
  }
  return switch (e.type) {
    DioExceptionType.connectionError => NetworkFailure(
      cause: e,
      stackTrace: stackTrace,
    ),
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.transformTimeout => NetworkFailure(
      code: FailureCode.networkTimeout,
      cause: e,
      stackTrace: stackTrace,
    ),
    DioExceptionType.badCertificate => NetworkFailure(
      code: FailureCode.networkTls,
      retryable: false,
      cause: e,
      stackTrace: stackTrace,
    ),
    DioExceptionType.cancel => CancelledFailure(
      cause: e,
      stackTrace: stackTrace,
    ),
    DioExceptionType.badResponse => NetworkFailure(
      code: FailureCode.networkBadResponse,
      retryable: false,
      cause: e,
      stackTrace: stackTrace,
    ),
    DioExceptionType.unknown => UnknownFailure(
      cause: e,
      stackTrace: stackTrace,
    ),
  };
}

/// A Dio bound to the account API that attaches the stored bearer token to
/// every request.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      contentType: 'application/json',
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        // A read failure must not be silent: the request then goes out
        // unauthenticated and the server answers 401, which would look like
        // "wrong password" without this breadcrumb.
        final token = switch (await ref.read(tokenStoreProvider).read()) {
          Success(:final value) => value,
          Failure(:final error) => () {
            ref
                .read(appLoggerProvider)
                .warning(
                  'auth.token_read_failed',
                  fields: {'code': error.code},
                );
            return null;
          }(),
        };
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );
  return dio;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => HttpAuthRepository(ref.watch(dioProvider)),
);
