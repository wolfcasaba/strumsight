// A feed-repository bekötésének mérése — a TÉNYLEGES kimenő kérésen és a
// TÉNYLEGES szerver-válasz alakján, nem fake repository-n.
//
// MÉRT hiány (2026-09-05): a `CommunityFeedRepository` szerződés a Kör 5 óta
// állt implementáció nélkül, ezért a feed-képernyők nem tudtak valódi adatot
// kérni. A mostani bekötés három ponton dönthetett rosszul, és mindhármat
// cella méri:
//
//   1. a lapozás elnyelése (a `cursor` felépül, de nem megy ki),
//   2. a lista végének összemosása az első kéréssel (`halted` vs `initial`),
//   3. az ismeretlen közönség NYITOTTABB értelmezése.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/data/repositories/feed_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_reaction.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';

/// Hálózat NÉLKÜLI adapter: rögzíti a kimenő kérést, és a tesztben
/// beállított törzset adja vissza.
class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Map<String, Object?> body = const {'items': <Object?>[], 'next_cursor': null};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _postJson({
  String publicId = '11111111-1111-4111-8111-111111111111',
  String audience = 'public',
  int reactionCount = 0,
  int commentCount = 0,
  int bookmarkCount = 0,
  String? viewerReaction,
  String createdAt = '2026-09-05T10:00:00Z',
  String? resourceVersion,
}) => <String, Object?>{
  'public_id': publicId,
  'author_public_id': '22222222-2222-4222-8222-222222222222',
  'audience': audience,
  'club_id': null,
  'body': 'poszt',
  'artifact_type': null,
  'artifact_schema_version': null,
  'artifact_payload': null,
  'moderation_state': 'visible',
  'reaction_count': reactionCount,
  'comment_count': commentCount,
  'bookmark_count': bookmarkCount,
  'viewer_bookmarked': false,
  'viewer_reaction': viewerReaction,
  'created_at': createdAt,
  'resource_version': resourceVersion ?? createdAt,
  'deleted_at': null,
};

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityFeedRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityFeedRepository(ApiClient(dio));
  });

  group('followingFeed', () {
    test('B1 — az első oldal kurzor NÉLKÜL megy ki', () async {
      await repository.followingFeed(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(adapter.lastRequest!.path, '/community/feed');
      expect(adapter.lastRequest!.queryParameters['page_size'], 25);
      // A `null` kurzus-kulcs KIMARAD: a szerver `extra="forbid"` sémája
      // egy `cursor=null` paramétert ismeretlen bemenetként utasítana el.
      expect(adapter.lastRequest!.queryParameters.containsKey('cursor'), isFalse);
    });

    test('B2 — a folytatólagos kurzor TÉNYLEGESEN kimegy', () async {
      // Ez az a cella, ami a mért néma hibát fogja: a kurzor felépült, de
      // nem került a kérésbe, ezért minden lapozás az első oldalt kérte
      // újra. A B1 a kontrollja — ott a hiány a helyes viselkedés.
      await repository.followingFeed(
        cursor: const CursorPage.continued('opaque-token'),
        limit: 10,
      );

      expect(adapter.lastRequest!.queryParameters['cursor'], 'opaque-token');
      expect(adapter.lastRequest!.queryParameters['page_size'], 10);
    });

    test('B3 — a számlálók és a néző reakciója a válaszból jön', () async {
      adapter.body = {
        'items': [
          _postJson(
            reactionCount: 3,
            commentCount: 2,
            bookmarkCount: 1,
            viewerReaction: 'celebrate',
          ),
        ],
        'next_cursor': null,
      };

      final page = await repository.followingFeed(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      final post = page.items.single;
      expect(post.counts.reactionCount, 3);
      expect(post.counts.commentCount, 2);
      expect(post.counts.bookmarkCount, 1);
      expect(post.viewerState.myReaction, ReactionKind.celebrate);
    });

    test('B4 — a lista vége HALTED, nem INITIAL', () async {
      // A két állapot összemosása mért csapda (`cursor_page.dart`, L349): a
      // lapozó a lista végén újraindulna az első oldalról.
      adapter.body = {'items': <Object?>[], 'next_cursor': null};

      final page = await repository.followingFeed(
        cursor: const CursorPage.continued('t'),
        limit: 25,
      );

      expect(page.cursor, const CursorPage.haltedAfterRequest());
      expect(page.cursor.isInitial, isFalse);
    });

    test('B5 — a nem üres kurzor folytatólagos oldalt jelöl', () async {
      adapter.body = {'items': <Object?>[], 'next_cursor': 'next-token'};

      final page = await repository.followingFeed(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(page.cursor, const CursorPage.continued('next-token'));
    });
  });

  group('a wire-alak értelmezése', () {
    test('B6 — az ismeretlen közönség a LEGSZŰKEBB értelmezést kapja', () async {
      // Egy jövőbeli, szűkebb közönség `public`-ra kerekítése azt
      // jelentené, hogy a régi kliens nyilvánosnak MUTAT egy nem
      // nyilvános posztot. A kontroll a B3, ahol a `public` végig public.
      adapter.body = {
        'items': [_postJson(audience: 'club_members_only_future_value')],
        'next_cursor': null,
      };

      final page = await repository.followingFeed(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(page.items.single.audience, CommunityAudience.private);
    });

    test('B7 — a nem szerkesztett poszt editedAt-ja null marad', () async {
      // A szerver MINDEN poszthoz ad `resource_version`-t (optimista
      // konkurenciához); egy soha nem szerkesztett poszton ez megegyezik a
      // `created_at`-tel. Vakon átvéve minden poszt „szerkesztve" jelölést
      // kapna.
      adapter.body = {
        'items': [
          _postJson(
            createdAt: '2026-09-05T10:00:00Z',
            resourceVersion: '2026-09-05T10:00:00Z',
          ),
          _postJson(
            publicId: '33333333-3333-4333-8333-333333333333',
            createdAt: '2026-09-05T10:00:00Z',
            resourceVersion: '2026-09-05T11:00:00Z',
          ),
        ],
        'next_cursor': null,
      };

      final page = await repository.followingFeed(
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(page.items.first.editedAt, isNull);
      expect(page.items.last.editedAt, isNotNull);
    });

    test('B8 — a hiányzó kötelező mező hiba, nem néma nulla', () async {
      adapter.body = {
        'items': [
          <String, Object?>{'body': 'azonosító nélkül'},
        ],
        'next_cursor': null,
      };

      await expectLater(
        repository.followingFeed(cursor: const CursorPage.initial(), limit: 25),
        throwsA(isA<Object>()),
      );
    });
  });

  group('clubPinned / clubFeed', () {
    test('B9 — a kitűzöttek listája a klub útvonalára megy', () async {
      adapter.body = {
        'items': [_postJson(reactionCount: 4)],
      };

      final page = await repository.clubPinned(
        clubId: ContentId('44444444-4444-4444-8444-444444444444'),
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(
        adapter.lastRequest!.path,
        '/community/clubs/44444444-4444-4444-8444-444444444444/pinned',
      );
      // A kitűzött poszt TELJES elem — a számláló valódi, nem kitalált nulla.
      expect(page.items.single.counts.reactionCount, 4);
      // A hiányzó `next_cursor` kulcs itt SZÁNDÉKOS: a lista egyoldalas.
      expect(page.cursor, const CursorPage.haltedAfterRequest());
    });

    test('B10 — a klub posztfolyama külön útvonal, lapozással', () async {
      await repository.clubFeed(
        clubId: ContentId('44444444-4444-4444-8444-444444444444'),
        cursor: const CursorPage.continued('club-token'),
        limit: 15,
      );

      expect(
        adapter.lastRequest!.path,
        '/community/clubs/44444444-4444-4444-8444-444444444444/feed',
      );
      expect(adapter.lastRequest!.queryParameters['cursor'], 'club-token');
      expect(adapter.lastRequest!.queryParameters['page_size'], 15);
    });
  });

  test('B11 — a profil-posztok hiánya HIBA, nem üres oldal', () async {
    // Egy üres oldal azt ÁLLÍTANÁ, hogy ennek a profilnak nincs posztja.
    // Az igazság az, hogy nincs végpont — se route, se service. A
    // `UNKNOWN > CONFIDENTLY WRONG` elv szerint a nem tudás nem
    // öltözhet válasznak.
    await expectLater(
      repository.profilePosts(
        userId: PublicUserId('55555555-5555-4555-8555-555555555555'),
        cursor: const CursorPage.initial(),
        limit: 25,
      ),
      throwsA(isA<UnimplementedError>()),
    );
    // A kérés EL SEM INDULT — nincs olyan végpont, amit eltalálhatna.
    expect(adapter.lastRequest, isNull);
  });
}
