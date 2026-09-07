// A klub-poszt írás bekötésének mérése a TÉNYLEGES kimenő kérésen
// (E17-R11) — nem fake repository-n.
//
// MÉRT hiány (`docs/ui/apk-functionality-audit-2026-09-06.md` §5.2): a
// kliens nem tudott klubba posztolni, mert a szerver poszt-írása csak a
// BELSŐ egész klub-azonosítót fogadta, amit a kliens nem ismer (és ADR
// 0396 §1 szerint nem is ismerhet). A szerver E17-R11 óta a PUBLIKUS
// azonosítót is elfogadja; ez a modul azt méri, hogy a kliens tényleg azt
// küldi ki, és hogy a klub nélküli írás alakja NEM változott.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';

/// Hálózat NÉLKÜLI adapter: rögzíti a kimenő kérést, és a tesztben
/// beállított törzset adja vissza.
class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  int status = 201;
  Map<String, Object?> body = _postJson();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
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

Map<String, Object?> _postJson() => <String, Object?>{
  'public_id': '11111111-1111-4111-8111-111111111111',
  'author_public_id': '22222222-2222-4222-8222-222222222222',
  'audience': 'public',
  'club_id': 7,
  'club_public_id': '44444444-4444-4444-8444-444444444444',
  'body': 'klub-poszt',
  'artifact_type': null,
  'artifact_schema_version': null,
  'artifact_payload': null,
  'moderation_state': 'visible',
  'created_at': '2026-09-06T10:00:00Z',
  'resource_version': '2026-09-06T10:00:00Z',
  'deleted_at': null,
};

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityPostRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityPostRepository(ApiClient(dio));
  });

  group('createClubPost', () {
    test('N1 — a klub PUBLIKUS azonosítója megy ki, nem a belső', () async {
      await repository.createClubPost(
        clubId: ContentId('44444444-4444-4444-8444-444444444444'),
        audience: CommunityAudience.public,
        body: 'klub-poszt',
        artifact: const <String, Object?>{},
        idempotencyKey: 'n1',
      );

      expect(adapter.lastRequest!.path, '/community/posts');
      final sent = adapter.lastRequest!.data! as Map;
      expect(sent['club_public_id'], '44444444-4444-4444-8444-444444444444');
      // A belső egész azonosító kulcsa NEM mehet ki: a kliens nem ismeri,
      // és a szerver sémája `extra="forbid"` — egy kitalált érték vagy
      // 422-t adna, vagy (a lyuk befoltozása előtt) idegen klubba írna.
      expect(sent.containsKey('club_id'), isFalse);
      expect(sent['audience'], 'public');
      expect(sent['idempotency_key'], 'n1');
    });

    test('N2 — az ÜRES artefaktum kulcsa kimarad a törzsből', () async {
      // A szerkesztő alapértelmezése az üres térkép; a szerver
      // `parse_share_artifact`-ja diszkriminátort vár, tehát az üres
      // térkép elküldése 422-t adna minden klub-poszton.
      await repository.createClubPost(
        clubId: ContentId('44444444-4444-4444-8444-444444444444'),
        audience: CommunityAudience.followers,
        body: 'törzs',
        artifact: const <String, Object?>{},
        idempotencyKey: 'n2',
      );

      final sent = adapter.lastRequest!.data! as Map;
      expect(sent.containsKey('artifact'), isFalse);
    });

    test('N3 — a klub nélküli createPost NEM visz klub-kulcsot', () async {
      // Kontroll: a meglévő útvonal alakja bájtra változatlan. Egy
      // `club_public_id: null` kulcs a szerver `extra="forbid"` sémáján
      // nem bukna el, de a klub nélküli és a klub-poszt közti különbséget
      // elmosná — a két hívási hely szándéka a törzsből legyen olvasható.
      adapter.body = <String, Object?>{
        ..._postJson(),
        'club_id': null,
        'club_public_id': null,
      };

      await repository.createPost(
        audience: CommunityAudience.public,
        body: 'sima',
        artifact: const <String, Object?>{},
        idempotencyKey: 'n3',
      );

      final sent = adapter.lastRequest!.data! as Map;
      expect(sent.containsKey('club_public_id'), isFalse);
      expect(sent.containsKey('club_id'), isFalse);
    });

    test('N4 — a szerver 404-e HIBAKÉNT jut a hívóhoz', () async {
      // A szerver a nem-tag, az ismeretlen és a törölt klubra EGYFORMA
      // 404-et ad (leak-guard). A kliens ezért nem tehet úgy, mintha a
      // poszt kiment volna: a hiba kibukik, és a kimenő sor a rekordot
      // megtartja.
      adapter.status = 404;
      adapter.body = <String, Object?>{'detail': 'club not found'};

      await expectLater(
        repository.createClubPost(
          clubId: ContentId('44444444-4444-4444-8444-444444444444'),
          audience: CommunityAudience.public,
          body: 'idegen klub',
          artifact: const <String, Object?>{},
          idempotencyKey: 'n4',
        ),
        throwsA(isA<Object>()),
      );
    });
  });
}
