// R12 (audit §5.2) — a 404 on `GET /community/profiles/me` is TWO different
// facts, and the repository now tells them apart on the ACTUAL wire shape.
//
// MEASURED: the live deploy runs with `STRUMSIGHT_COMMUNITY_ENABLED=false`,
// so `backend/app/main.py` never mounts the community router and FastAPI
// answers its bare `{"detail": "Not Found"}` 404 for every `/community/**`
// path (pinned by `backend/tests/test_community_mounting.py` A1). The
// mounted router, by contrast, answers 404 `{"detail": "profile_missing"}`
// (`backend/app/community/routers/profile.py:113`). Until R12 both
// collapsed to `null`, which made "this server has no Community" look
// exactly like "you have no profile yet": the gate offered Create profile,
// and the POST then failed with the generic error copy.
//
// R19 (audit M3) — this test now builds its client through [DioFactory],
// the ONLY production constructor. The previous version constructed a bare
// `Dio(BaseOptions(...))`, which does NOT ship: the real factory sets
// `receiveDataWhenStatusError: false`, so `response.data` was `null` on
// every error status and the classification below collapsed the other way
// — EVERY 404 read as "module missing", so a server WITH Community would
// have refused to offer profile creation to a user who has no row yet. The
// distinction now rides `ApiClient.getJson`'s narrow `readsErrorDetail`
// opt-in, and this file measures the client that actually ships.
//
//   U1 — the router's own `profile_missing` 404 still means "no row",
//   U2 — any other 404 is the community-unavailable verdict, including a
//        body that is not JSON at all,
//   U3 — a non-404 failure is untouched (the classification is narrow),
//        and a 401 still expires the authenticated session,
//   U4 — the success path still decodes, despite `ResponseType.plain`.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/network/dio_factory.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/failures/community_availability.dart';

/// A wire probe: it only ever sees a request the interceptor chain let
/// through, and answers with a byte-exact body + content type.
final class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  int status = 200;
  String body = '{}';
  String contentType = Headers.jsonContentType;

  RequestOptions get last => requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioFactory _factory(_RecordingAdapter adapter) => DioFactory(
  baseUrl: 'https://api.strumsight.test',
  appVersion: 'test',
  logger: const NoopAppLogger(),
  adapter: adapter,
  correlationIdGenerator: () => 'community-profile-probe',
);

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityProfileRepository repository;
  late int invalidations;

  setUp(() {
    adapter = _RecordingAdapter();
    invalidations = 0;
    final client = _factory(adapter).createAccountClient(
      accountEnabled: true,
      readToken: () async => const Success('jwt-test-token'),
      readSessionGeneration: () => 7,
      onUnauthorized: (_) => invalidations++,
    );
    repository = HttpCommunityProfileRepository(client);
  });

  group('fetchMyProfile 404 classification on a DioFactory client', () {
    test('U1 the router 404 profile_missing means no row', () async {
      adapter.status = 404;
      adapter.body = '{"detail": "profile_missing"}';

      expect(await repository.fetchMyProfile(), isNull);
      expect(adapter.last.path, '/community/profiles/me');
      // The mechanism, not just the outcome: the request opted into keeping
      // the error body, and asked for it undecoded.
      expect(adapter.last.receiveDataWhenStatusError, isTrue);
      expect(adapter.last.responseType, ResponseType.plain);
    });

    test('U2a the framework 404 means the module is not mounted', () async {
      adapter.status = 404;
      adapter.body = '{"detail": "Not Found"}';

      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            CommunityFailureCode.unavailable,
          ),
        ),
      );
    });

    test('U2b an empty 404 body means the module is not mounted', () async {
      adapter.status = 404;
      adapter.body = '';

      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            CommunityFailureCode.unavailable,
          ),
        ),
      );
    });

    test('U2c an HTML 404 body means the module is not mounted', () async {
      adapter.status = 404;
      adapter.body = '<html><body>404 Not Found</body></html>';
      adapter.contentType = 'text/html';

      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            CommunityFailureCode.unavailable,
          ),
        ),
      );
    });

    test('U2d a malformed JSON 404 body never loses the status', () async {
      adapter.status = 404;
      adapter.body = '{"detail":';

      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<AppFailure>().having(
            (failure) => failure.code,
            'code',
            CommunityFailureCode.unavailable,
          ),
        ),
      );
    });
  });

  group('fetchMyProfile non-404 answers are untouched', () {
    test('U3a a 401 expires the authenticated session', () async {
      adapter.status = 401;
      adapter.body = '{"detail": "Not authenticated"}';

      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<AuthenticationFailure>().having(
            (failure) => failure.code,
            'code',
            FailureCode.authSessionExpired,
          ),
        ),
      );
      expect(invalidations, 1);
    });

    test('U3b a malformed 401 body still expires the session', () async {
      adapter.status = 401;
      adapter.body = '{"broken":';

      await expectLater(
        repository.fetchMyProfile(),
        throwsA(isA<AuthenticationFailure>()),
      );
      expect(invalidations, 1);
    });

    test('U3c a 500 stays the transport failure', () async {
      adapter.status = 500;
      adapter.body = '{"detail": "boom"}';

      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<NetworkFailure>().having(
            (failure) => failure.code,
            'code',
            FailureCode.networkServer,
          ),
        ),
      );
      expect(invalidations, 0);
    });
  });

  group('fetchMyProfile success path', () {
    test('U4a the plain response type still decodes the profile', () async {
      adapter.status = 200;
      adapter.body =
          '{"public_id": "01931f2a-0000-7000-8000-000000000001", '
          '"display_name": "Ada", '
          '"created_at": "2026-09-01T10:00:00Z", '
          '"handle": "adalovelace"}';

      final profile = await repository.fetchMyProfile();

      expect(profile, isNotNull);
      expect(profile!.handle.value, 'adalovelace');
      expect(profile.displayName, 'Ada');
    });

    test('U4b a malformed 200 body is a bad-response failure', () async {
      adapter.status = 200;
      adapter.body = '{"public_id":';

      await expectLater(
        repository.fetchMyProfile(),
        throwsA(
          isA<NetworkFailure>().having(
            (failure) => failure.code,
            'code',
            FailureCode.networkBadResponse,
          ),
        ),
      );
    });
  });
}
