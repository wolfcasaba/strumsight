import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/debug_app_logger.dart';
import 'package:strumsight/core/network/dio_factory.dart';

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({
    this.status = 200,
    this.body = '{"ok":true}',
    this.errorType,
  });

  final int status;
  final String body;
  final DioExceptionType? errorType;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (errorType != null) {
      throw DioException(requestOptions: options, type: errorType!);
    }
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioFactory _factory(
  _RecordingAdapter adapter, {
  List<String>? logs,
  String correlationId = 'corr-fixed',
}) {
  return DioFactory(
    baseUrl: 'https://api.strumsight.test',
    appVersion: '1.2.3+4',
    logger: DebugAppLogger(
      enabled: true,
      sink: logs == null ? (_) {} : logs.add,
    ),
    adapter: adapter,
    correlationIdGenerator: () => correlationId,
  );
}

void main() {
  test(
    'configures headers, all timeouts, bearer, and correlation ID',
    () async {
      final adapter = _RecordingAdapter();
      final client = _factory(adapter).createAccountClient(
        accountEnabled: true,
        readToken: () async => const Success('jwt-secret'),
        readSessionGeneration: () => 7,
        onUnauthorized: (_) {},
      );

      final result = await client.getJson<bool>(
        '/ping',
        decode: (json) => json['ok'] as bool,
      );

      expect(result.valueOrNull, isTrue);
      final request = adapter.requests.single;
      expect(request.baseUrl, 'https://api.strumsight.test');
      expect(request.connectTimeout, const Duration(seconds: 8));
      expect(request.sendTimeout, const Duration(seconds: 8));
      expect(request.receiveTimeout, const Duration(seconds: 8));
      expect(request.contentType, Headers.jsonContentType);
      expect(request.headers['User-Agent'], 'StrumSight/1.2.3+4');
      expect(request.headers['X-App-Version'], '1.2.3+4');
      expect(request.headers['X-Correlation-ID'], 'corr-fixed');
      expect(request.headers['Authorization'], 'Bearer jwt-secret');
    },
  );

  test('account-disabled factory refuses to instantiate an account client', () {
    final adapter = _RecordingAdapter();

    expect(
      () => _factory(adapter).createAccountClient(
        accountEnabled: false,
        readToken: () async => const Success(null),
        readSessionGeneration: () => 7,
        onUnauthorized: (_) {},
      ),
      throwsStateError,
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    'public auth request skips token read and does not expire a session',
    () async {
      final adapter = _RecordingAdapter(status: 401, body: '{"detail":"bad"}');
      var tokenReads = 0;
      var invalidations = 0;
      final client = _factory(adapter).createAccountClient(
        accountEnabled: true,
        readToken: () async {
          tokenReads++;
          return const Success('old-session-token');
        },
        readSessionGeneration: () => 7,
        onUnauthorized: (generation) {
          expect(generation, 7);
          invalidations++;
        },
      );

      final result = await client.postJson<String>(
        '/auth/login',
        data: const {
          'email': 'player@strumsight.app',
          'password': 'sixstrings',
        },
        requiresAuthentication: false,
        decode: (_) => 'unreachable',
        unauthorizedCode: FailureCode.authInvalidCredentials,
      );

      expect(result.failureOrNull?.code, FailureCode.authInvalidCredentials);
      expect(tokenReads, 0);
      expect(invalidations, 0);
      expect(adapter.requests.single.headers, isNot(contains('Authorization')));
    },
  );

  test('token read failure fails closed before the network adapter', () async {
    const storage = StorageFailure(code: FailureCode.storageRead);
    final adapter = _RecordingAdapter();
    final client = _factory(adapter).createAccountClient(
      accountEnabled: true,
      readToken: () async => const Failure(storage),
      readSessionGeneration: () => 7,
      onUnauthorized: (_) {},
    );

    final result = await client.getJson<bool>(
      '/auth/me',
      decode: (json) => json['ok'] as bool,
    );

    expect(identical(result.failureOrNull, storage), isTrue);
    expect(adapter.requests, isEmpty);
  });

  test('missing token fails a protected request before transport', () async {
    final adapter = _RecordingAdapter();
    final client = _factory(adapter).createAccountClient(
      accountEnabled: true,
      readToken: () async => const Success(null),
      readSessionGeneration: () => 7,
      onUnauthorized: (_) {},
    );

    final result = await client.getJson<bool>(
      '/auth/me',
      decode: (json) => json['ok'] as bool,
    );
    final postResult = await client.post('/settings');

    expect(result.failureOrNull?.code, FailureCode.authSessionExpired);
    expect(postResult.failureOrNull?.code, FailureCode.authSessionExpired);
    expect(adapter.requests, isEmpty);
  });

  test('a session change during token read cancels before transport', () async {
    final adapter = _RecordingAdapter();
    final tokenReadStarted = Completer<void>();
    final releaseToken = Completer<void>();
    var generation = 1;
    final client = _factory(adapter).createAccountClient(
      accountEnabled: true,
      readToken: () async {
        tokenReadStarted.complete();
        await releaseToken.future;
        return const Success('old-token');
      },
      readSessionGeneration: () => generation,
      onUnauthorized: (_) {},
    );

    final request = client.getJson<bool>(
      '/settings',
      decode: (json) => json['ok'] as bool,
    );
    await tokenReadStarted.future;
    generation++;
    releaseToken.complete();

    expect((await request).failureOrNull, isA<CancelledFailure>());
    expect(adapter.requests, isEmpty);
  });

  test('authenticated 401 invalidates once and is never retried', () async {
    final adapter = _RecordingAdapter(status: 401);
    var invalidations = 0;
    final client = _factory(adapter).createAccountClient(
      accountEnabled: true,
      readToken: () async => const Success('expired-token'),
      readSessionGeneration: () => 7,
      onUnauthorized: (generation) {
        expect(generation, 7);
        invalidations++;
      },
    );

    final result = await client.getJson<bool>(
      '/settings',
      decode: (json) => json['ok'] as bool,
    );

    expect(result.failureOrNull?.code, FailureCode.authSessionExpired);
    expect(invalidations, 1);
    expect(adapter.requests, hasLength(1));
  });

  test('malformed 401 body still expires the authenticated session', () async {
    final adapter = _RecordingAdapter(status: 401, body: '{"broken":');
    var invalidations = 0;
    final client = _factory(adapter).createAccountClient(
      accountEnabled: true,
      readToken: () async => const Success('expired-token'),
      readSessionGeneration: () => 7,
      onUnauthorized: (generation) {
        expect(generation, 7);
        invalidations++;
      },
    );

    final result = await client.getJson<bool>(
      '/settings',
      decode: (json) => json['ok'] as bool,
    );

    expect(result.failureOrNull?.code, FailureCode.authSessionExpired);
    expect(invalidations, 1);
    expect(adapter.requests, hasLength(1));
  });

  test('POST transport failure is attempted exactly once', () async {
    final adapter = _RecordingAdapter(
      errorType: DioExceptionType.connectionError,
    );
    final client = _factory(adapter).createAccountClient(
      accountEnabled: true,
      readToken: () async => const Success('test-token'),
      readSessionGeneration: () => 7,
      onUnauthorized: (_) {},
    );

    final result = await client.postJson<bool>(
      '/settings',
      data: const {'theme_mode': 'dark'},
      decode: (json) => json['ok'] as bool,
    );

    expect(result.failureOrNull, isA<NetworkFailure>());
    expect(adapter.requests, hasLength(1));
  });

  test('malformed JSON is a controlled bad-response failure', () async {
    final adapter = _RecordingAdapter(body: '{"broken":');
    final client = _factory(adapter).createAccountClient(
      accountEnabled: true,
      readToken: () async => const Success('test-token'),
      readSessionGeneration: () => 7,
      onUnauthorized: (_) {},
    );

    final result = await client.getJson<bool>(
      '/auth/me',
      decode: (json) => json['ok'] as bool,
    );

    expect(result.failureOrNull?.code, FailureCode.networkBadResponse);
    expect(result.failureOrNull?.retryable, isFalse);
    expect(adapter.requests, hasLength(1));
  });

  test(
    'diagnostics client is separate and never receives bearer auth',
    () async {
      final adapter = _RecordingAdapter();
      final client = _factory(
        adapter,
      ).createDiagnosticsClient(diagnosticsEnabled: true);

      await client.post(
        '/diagnostics',
        data: const [1, 2, 3],
        headers: const {'X-Diag-Token': 'diag-secret'},
      );

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.headers, isNot(contains('Authorization')));
    },
  );

  test(
    'debug transport logging excludes tokens, credentials, and bodies',
    () async {
      final adapter = _RecordingAdapter();
      final logs = <String>[];
      final client = _factory(adapter, logs: logs).createAccountClient(
        accountEnabled: true,
        readToken: () async => const Success('jwt-do-not-log'),
        readSessionGeneration: () => 7,
        onUnauthorized: (_) {},
      );

      await client.postJson<bool>(
        '/auth/login',
        data: const {
          'email': 'secret@example.com',
          'password': 'hidden-password',
        },
        requiresAuthentication: false,
        decode: (json) => json['ok'] as bool,
      );
      await client.getJson<bool>(
        '/account?token=query-do-not-log',
        decode: (json) => json['ok'] as bool,
      );
      await client.post(
        '/account',
        headers: const {'x-correlation-id': 'caller-correlation-secret'},
      );

      final joined = logs.join('\n');
      expect(joined, contains('network.request'));
      expect(joined, contains('/auth/login'));
      expect(joined, isNot(contains('jwt-do-not-log')));
      expect(joined, isNot(contains('query-do-not-log')));
      expect(joined, isNot(contains('caller-correlation-secret')));
      expect(joined, isNot(contains('secret@example.com')));
      expect(joined, isNot(contains('hidden-password')));
      expect(joined, isNot(contains('X-Diag-Token')));
      expect(
        adapter.requests.last.headers.values,
        isNot(contains('caller-correlation-secret')),
      );
    },
  );
}
