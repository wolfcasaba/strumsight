import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/auth/data/auth_repository.dart';

/// Canned transport: either a status + body, or a thrown [DioException].
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.status = 200, this.body = '{}', this.throws});

  final int status;
  final String body;
  final DioExceptionType? throws;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throws != null) {
      throw DioException(requestOptions: options, type: throws!);
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

AuthRepository _repo(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'))
    // Non-2xx must reach us as a DioException so the mapper sees the status.
    ..httpClientAdapter = adapter;
  return HttpAuthRepository(dio);
}

void main() {
  test('login returns the access token on success', () async {
    final result = await _repo(
      _FakeAdapter(body: '{"access_token":"jwt-1"}'),
    ).login('player@strumsight.app', 'sixstrings');

    expect(result, isA<Success<String>>());
    expect(result.valueOrNull, 'jwt-1');
  });

  test('401 → invalid credentials, not retryable', () async {
    final result = await _repo(
      _FakeAdapter(status: 401, body: '{"detail":"bad"}'),
    ).login('player@strumsight.app', 'wrong');

    final failure = result.failureOrNull!;
    expect(failure, isA<AuthenticationFailure>());
    expect(failure.code, FailureCode.authInvalidCredentials);
    expect(failure.retryable, isFalse);
  });

  test('409 → e-mail taken', () async {
    final result = await _repo(
      _FakeAdapter(status: 409, body: '{"detail":"taken"}'),
    ).register('taken@strumsight.app', 'sixstrings');

    expect(result.failureOrNull!.code, FailureCode.validationEmailTaken);
  });

  test('5xx → retryable server failure', () async {
    final result = await _repo(
      _FakeAdapter(status: 503, body: '{}'),
    ).login('player@strumsight.app', 'sixstrings');

    final failure = result.failureOrNull!;
    expect(failure.code, FailureCode.networkServer);
    expect(failure.retryable, isTrue);
  });

  test('connection error → retryable network failure', () async {
    final result = await _repo(
      _FakeAdapter(throws: DioExceptionType.connectionError),
    ).login('player@strumsight.app', 'sixstrings');

    final failure = result.failureOrNull!;
    expect(failure, isA<NetworkFailure>());
    expect(failure.code, FailureCode.networkUnavailable);
    expect(failure.retryable, isTrue);
  });

  test('timeout → timeout code', () async {
    final result = await _repo(
      _FakeAdapter(throws: DioExceptionType.receiveTimeout),
    ).me();

    expect(result.failureOrNull!.code, FailureCode.networkTimeout);
  });

  test('cancellation is not an error to report', () async {
    final result = await _repo(
      _FakeAdapter(throws: DioExceptionType.cancel),
    ).me();

    expect(result.failureOrNull, isA<CancelledFailure>());
  });

  test('a 2xx without a token is a bad response, never a success', () async {
    final result = await _repo(
      _FakeAdapter(body: '{"unexpected":true}'),
    ).login('player@strumsight.app', 'sixstrings');

    expect(result.failureOrNull!.code, FailureCode.networkBadResponse);
  });

  test('a malformed user payload is a bad response, not a crash', () async {
    final result = await _repo(_FakeAdapter(body: '{"id":"NaN"}')).me();

    expect(result.failureOrNull!.code, FailureCode.networkBadResponse);
  });

  test('no DioException ever escapes the repository', () async {
    for (final type in DioExceptionType.values) {
      final result = await _repo(_FakeAdapter(throws: type)).me();
      expect(result, isA<Failure<dynamic>>(), reason: type.name);
      expect(result.failureOrNull, isA<AppFailure>(), reason: type.name);
    }
  });

  test('me() returns the signed-in user', () async {
    final result = await _repo(
      _FakeAdapter(body: '{"id":1,"email":"player@strumsight.app"}'),
    ).me();

    expect(result.valueOrNull!.email, 'player@strumsight.app');
  });
}
