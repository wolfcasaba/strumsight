// R12 (audit §5.2) — a 404 on `GET /community/profiles/me` is TWO different
// facts, and the repository now tells them apart on the ACTUAL wire shape.
//
// MEASURED: the live deploy runs with `STRUMSIGHT_COMMUNITY_ENABLED=false`,
// so `backend/app/main.py` never mounts the community router and FastAPI
// answers its bare `{"detail": "Not Found"}` 404 for every `/community/**`
// path. The mounted router, by contrast, answers 404 `profile_missing`
// (`backend/app/community/routers/profile.py`). Until this round both
// collapsed to `null`, which made "this server has no Community" look
// exactly like "you have no profile yet": the gate offered Create profile,
// and the POST then failed with the generic error copy.
//
//   U1 — the router's own `profile_missing` 404 still means "no row",
//   U2 — any other 404 is the community-unavailable verdict,
//   U3 — a non-404 failure is untouched (the classification is narrow).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/failures/community_availability.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  Map<String, Object?> body = const <String, Object?>{};
  int status = 200;

  RequestOptions get last => requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityProfileRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityProfileRepository(ApiClient(dio));
  });

  group('fetchMyProfile 404 classification', () {
    test('U1 the router 404 profile_missing means no row', () async {
      adapter.status = 404;
      adapter.body = const <String, Object?>{'detail': 'profile_missing'};

      expect(await repository.fetchMyProfile(), isNull);
      expect(adapter.last.path, '/community/profiles/me');
    });

    test('U2 a bare 404 means the module is not enabled', () async {
      adapter.status = 404;
      adapter.body = const <String, Object?>{'detail': 'Not Found'};

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

    test('U3 a 500 stays the transport failure', () async {
      adapter.status = 500;
      adapter.body = const <String, Object?>{'detail': 'boom'};

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
    });
  });
}
