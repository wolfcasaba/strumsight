// A profil-lekérés bekötésének mérése (javító sáv R5, 2026-09-06) — a
// TÉNYLEGES kimenő kérésen és a TÉNYLEGES szerver-válasz alakján.
//
// MÉRT hiány: a `fetchById` `UnsupportedError`-t dobott („Kör 7+
// implementáció"), pedig a `GET /community/profiles/{public_id}` végpont a
// szerveren megvolt — a követő-listák ezért csak helyőrző sorokat mutattak.
//
//   P1 — az útvonal és a válasz leképezése (handle + display_name),
//   P2 — a hiányzó display_name (nullable oszlop) a handle-re esik vissza,
//   P3 — a hiba (404) kivétel, nem üres profil.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';

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

const String _userId = '99999999-9999-4999-8999-999999999999';

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityProfileRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityProfileRepository(ApiClient(dio));
  });

  group('fetchById', () {
    test('P1 — a profil a /community/profiles/{id}-ról jön', () async {
      adapter.body = const <String, Object?>{
        'public_id': _userId,
        'display_name': 'Anna',
        'created_at': '2026-09-06T10:00:00Z',
        'handle': 'anna_plays',
      };

      final profile = await repository.fetchById(PublicUserId(_userId));

      expect(adapter.last.path, '/community/profiles/$_userId');
      expect(adapter.last.method, 'GET');
      expect(profile.userId, PublicUserId(_userId));
      expect(profile.displayName, 'Anna');
      expect(profile.handle.value, 'anna_plays');
      expect(profile.visibility, ProfileVisibility.private);
    });

    test('P2 — a hiányzó display_name a handle-re esik vissza', () async {
      adapter.body = const <String, Object?>{
        'public_id': _userId,
        'display_name': null,
        'created_at': '2026-09-06T10:00:00Z',
        'handle': 'anna_plays',
      };

      final profile = await repository.fetchById(PublicUserId(_userId));

      expect(profile.displayName, 'anna_plays');
    });

    test('P3 — a 404 kivétel, nem üres profil', () async {
      adapter.status = 404;
      adapter.body = const <String, Object?>{'detail': 'not found'};

      await expectLater(
        repository.fetchById(PublicUserId(_userId)),
        throwsA(isA<AppFailure>()),
      );
    });
  });
}
