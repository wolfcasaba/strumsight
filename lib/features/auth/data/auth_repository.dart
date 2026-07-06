import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_config.dart';
import '../model/auth_user.dart';
import 'token_store.dart';

/// Why an auth call failed — mapped to a user-facing (localised) message by the
/// UI, so the repository stays free of BuildContext / l10n.
enum AuthErrorKind { invalidCredentials, emailTaken, network, unknown }

class AuthException implements Exception {
  const AuthException(this.kind);
  final AuthErrorKind kind;
}

/// Talks to the account backend. An interface so widget/unit tests inject a
/// fake without hitting the network.
abstract interface class AuthRepository {
  /// Register, returning a usable access token (the backend auto-logs-in).
  Future<String> register(String email, String password);

  /// Log in, returning an access token.
  Future<String> login(String email, String password);

  /// The currently authenticated user (token attached by the Dio interceptor).
  Future<AuthUser> me();
}

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._dio);

  final Dio _dio;

  @override
  Future<String> register(String email, String password) =>
      _postForToken('/auth/register', email, password);

  @override
  Future<String> login(String email, String password) =>
      _postForToken('/auth/login', email, password);

  Future<String> _postForToken(String path, String email, String password) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: {'email': email, 'password': password},
      );
      return res.data!['access_token'] as String;
    } on DioException catch (e) {
      throw AuthException(_kindFor(e));
    }
  }

  @override
  Future<AuthUser> me() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/auth/me');
      return AuthUser.fromJson(res.data!);
    } on DioException catch (e) {
      throw AuthException(_kindFor(e));
    }
  }

  AuthErrorKind _kindFor(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) return AuthErrorKind.invalidCredentials;
    if (status == 409) return AuthErrorKind.emailTaken;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return AuthErrorKind.network;
    }
    return AuthErrorKind.unknown;
  }
}

/// A Dio bound to the account API that attaches the stored bearer token to
/// every request.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      contentType: 'application/json',
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await ref.read(tokenStoreProvider).read();
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
