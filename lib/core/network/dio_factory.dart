import 'package:dio/dio.dart';

import '../logging/app_logger.dart';
import 'api_client.dart';
import 'auth_interceptor.dart';
import 'correlation_id_interceptor.dart';
import 'redacted_log_interceptor.dart';

/// The only production constructor for Dio-backed clients.
final class DioFactory {
  DioFactory({
    required this.baseUrl,
    required this.appVersion,
    required this.logger,
    this.adapter,
    CorrelationIdGenerator? correlationIdGenerator,
  }) : _externalCorrelationIdGenerator = correlationIdGenerator;

  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration sendTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 8);

  /// Inter-chunk budget for the tutor's SSE stream (see
  /// [createTutorStreamClient]). Long enough for a slow first model token,
  /// short enough that a dead stream still fails instead of hanging.
  static const Duration tutorStreamReceiveTimeout = Duration(seconds: 60);

  final String baseUrl;
  final String appVersion;
  final AppLogger logger;
  final HttpClientAdapter? adapter;
  final CorrelationIdGenerator? _externalCorrelationIdGenerator;
  int _correlationSequence = 0;

  ApiClient createAccountClient({
    required bool accountEnabled,
    required AccessTokenReader readToken,
    required SessionGenerationReader readSessionGeneration,
    required UnauthorizedCallback onUnauthorized,
  }) {
    if (!accountEnabled) {
      throw StateError('The account API is disabled for this build.');
    }
    return ApiClient(
      _createDio(
        authInterceptor: AuthInterceptor(
          readToken: readToken,
          readSessionGeneration: readSessionGeneration,
          onUnauthorized: onUnauthorized,
          logger: logger,
        ),
      ),
    );
  }

  ApiClient createDiagnosticsClient({required bool diagnosticsEnabled}) {
    if (!diagnosticsEnabled) {
      throw StateError('The diagnostics API is disabled for this build.');
    }
    return ApiClient(_createDio());
  }

  /// The server-sent-events client the AI tutor's stream transport rides.
  ///
  /// It returns a raw [Dio] rather than an [ApiClient] on purpose: the tutor
  /// turn is a long-lived `ResponseType.stream` response, and [ApiClient]'s
  /// primitives all decode a single JSON object. Everything else is the
  /// account client's own pipeline — the same [_createDio] path, so the
  /// bearer token (via [AuthInterceptor]) and the correlation id travel on
  /// every request, and the redacting log interceptor is attached.
  ///
  /// The one deliberate difference is [tutorStreamReceiveTimeout]: Dio's
  /// receive timeout is the budget BETWEEN two received chunks, and the
  /// shared 8s account budget would abort a turn whose first model token is
  /// merely slow. The timeout is longer, never absent — a hung stream must
  /// still fail, not hang forever.
  Dio createTutorStreamClient({
    required bool accountEnabled,
    required AccessTokenReader readToken,
    required SessionGenerationReader readSessionGeneration,
    required UnauthorizedCallback onUnauthorized,
  }) {
    if (!accountEnabled) {
      throw StateError('The tutor stream API is disabled for this build.');
    }
    final dio = _createDio(
      authInterceptor: AuthInterceptor(
        readToken: readToken,
        readSessionGeneration: readSessionGeneration,
        onUnauthorized: onUnauthorized,
        logger: logger,
      ),
    );
    dio.options.receiveTimeout = tutorStreamReceiveTimeout;
    dio.options.headers['Accept'] = 'text/event-stream';
    return dio;
  }

  Dio _createDio({AuthInterceptor? authInterceptor}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        sendTimeout: sendTimeout,
        receiveTimeout: receiveTimeout,
        // Error bodies are never consumed. Skipping their transformation keeps
        // the HTTP status authoritative even if a proxy returns malformed JSON
        // (notably, a 401 must still expire the authenticated session).
        receiveDataWhenStatusError: false,
        contentType: Headers.jsonContentType,
        headers: {
          'Accept': Headers.jsonContentType,
          'User-Agent': 'StrumSight/$appVersion',
          'X-App-Version': appVersion,
        },
      ),
    );
    if (adapter case final clientAdapter?) {
      dio.httpClientAdapter = clientAdapter;
    }
    dio.interceptors.add(
      CorrelationIdInterceptor(
        _externalCorrelationIdGenerator ?? _nextCorrelationId,
      ),
    );
    if (authInterceptor != null) {
      dio.interceptors.add(authInterceptor);
    }
    dio.interceptors.add(RedactedLogInterceptor(logger));
    return dio;
  }

  String _nextCorrelationId() {
    _correlationSequence++;
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final sequence = _correlationSequence.toRadixString(36);
    return 'ss-$timestamp-$sequence';
  }
}
