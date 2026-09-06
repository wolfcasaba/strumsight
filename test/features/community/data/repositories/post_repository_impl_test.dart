// A poszt-repository bekötésének mérése — a TÉNYLEGES kimenő kérésen és a
// TÉNYLEGES szerver-válasz alakján, nem fake repository-n.
//
// MÉRT hiány (2026-09-06): a `CommunityPostRepository` szerződés a Kör 5 óta
// állt implementáció nélkül, a provider-definíciója pedig egy `StateError`-t
// dobó seam volt a `post_composer_controller.dart`-ban. A szállított
// kompozícióban senki nem írta felül, tehát a feed-kártya, a szerkesztő, a
// komment-lista és a reakció-sáv is kivételt kapott volna.
//
// A bekötés hat ponton dönthetett rosszul, és mindegyiket cella méri:
//
//   1. a rejtett/nem létező poszt (404/403) KIVÉTEL-e vagy `null` (a
//      szerződés `null`-ja a leak-guard, l. `routers/posts.py` §5.3),
//   2. a lapozás elnyelése a komment-listán (a `cursor` felépül, de nem
//      megy ki),
//   3. a lista végének összemosása az első kéréssel (`halted` vs
//      `initial`),
//   4. a reakció TÖRLÉSE külön ige-e (`DELETE`), vagy egy `kind: null`
//      törzs (amit a szerver `extra="forbid"` sémája elutasítana),
//   5. az ÜRES artefaktum-térkép kiküldése (422 lenne),
//   6. a `PATCH` hiánya: a szerkesztés NEM hazudhat sikert.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/domain/entities/community_reaction.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';

/// Hálózat NÉLKÜLI adapter: rögzíti a kimenő kéréseket, és a tesztben
/// beállított törzset / státuszt adja vissza.
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

Map<String, Object?> _postJson({
  String publicId = '11111111-1111-4111-8111-111111111111',
  String audience = 'public',
  String createdAt = '2026-09-06T10:00:00Z',
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
  'created_at': createdAt,
  'resource_version': createdAt,
  'deleted_at': null,
};

Map<String, Object?> _commentJson({
  String publicId = '33333333-3333-4333-8333-333333333333',
  String? parentPublicId,
  String moderationState = 'visible',
  String createdAt = '2026-09-06T10:00:00Z',
  String? resourceVersion,
  String? deletedAt,
}) => <String, Object?>{
  'public_id': publicId,
  'post_public_id': '11111111-1111-4111-8111-111111111111',
  'author_public_id': '22222222-2222-4222-8222-222222222222',
  'parent_public_id': parentPublicId,
  'depth': parentPublicId == null ? 0 : 1,
  'body': 'komment',
  'moderation_state': moderationState,
  'created_at': createdAt,
  'resource_version': resourceVersion ?? createdAt,
  'deleted_at': deletedAt,
};

const String _postId = '11111111-1111-4111-8111-111111111111';

void main() {
  late _RecordingAdapter adapter;
  late HttpCommunityPostRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityPostRepository(ApiClient(dio));
  });

  Map<String, Object?> sentBody() => adapter.last.data! as Map<String, Object?>;

  group('createPost', () {
    test('C1 — a poszt a /community/posts-ra megy, POST-tal', () async {
      adapter.status = 201;
      adapter.body = _postJson();

      final post = await repository.createPost(
        audience: CommunityAudience.followers,
        body: 'szia',
        artifact: const <String, Object?>{},
        idempotencyKey: 'key-1',
      );

      expect(adapter.last.path, '/community/posts');
      expect(adapter.last.method, 'POST');
      expect(sentBody()['audience'], CommunityAudience.followers.wireValue);
      expect(sentBody()['body'], 'szia');
      expect(sentBody()['idempotency_key'], 'key-1');
      expect(post.id, ContentId(_postId));
    });

    test('C2 — az ÜRES artefaktum-térkép NEM megy ki', () async {
      // A szerver `parse_share_artifact`-ja diszkriminátort vár; egy üres
      // objektum 422 lenne. A szerkesztő alapértelmezése épp ez.
      adapter.status = 201;
      adapter.body = _postJson();

      await repository.createPost(
        audience: CommunityAudience.public,
        body: 'szia',
        artifact: const <String, Object?>{},
        idempotencyKey: 'key-2',
      );

      expect(sentBody().containsKey('artifact'), isFalse);
    });

    test('C3 — a nem üres artefaktum viszont kimegy', () async {
      adapter.status = 201;
      adapter.body = _postJson();

      await repository.createPost(
        audience: CommunityAudience.public,
        body: 'szia',
        artifact: const <String, Object?>{
          'type': 'session',
          'schemaVersion': 1,
        },
        idempotencyKey: 'key-3',
      );

      expect(sentBody()['artifact'], <String, Object?>{
        'type': 'session',
        'schemaVersion': 1,
      });
    });

    test('C4 — a nem-térkép artefaktum HIBA, nem néma eldobás', () async {
      // Egy csendben elhagyott artefaktum a felhasználó megosztott
      // tartalmának néma elvesztése lenne.
      await expectLater(
        repository.createPost(
          audience: CommunityAudience.public,
          body: 'szia',
          artifact: 'nem térkép',
          idempotencyKey: 'key-4',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('fetchPost', () {
    test('C5 — a látható poszt a saját útvonaláról jön', () async {
      adapter.body = _postJson();

      final post = await repository.fetchPost(postId: ContentId(_postId));

      expect(adapter.last.path, '/community/posts/$_postId');
      expect(adapter.last.method, 'GET');
      expect(post, isNotNull);
      expect(post!.audience, CommunityAudience.public);
    });

    test('C6 — a 404 NULL, nem kivétel', () async {
      // A szerver a nem létező és a néző elől REJTETT posztot
      // megkülönböztethetetlenül 404-eli (leak-guard). A szerződés
      // `null`-ja pontosan ezt jelenti.
      adapter.status = 404;
      adapter.body = const <String, Object?>{'detail': 'post not found'};

      expect(await repository.fetchPost(postId: ContentId(_postId)), isNull);
    });

    test('C7 — a 403 is NULL', () async {
      adapter.status = 403;
      adapter.body = const <String, Object?>{'detail': 'forbidden'};

      expect(await repository.fetchPost(postId: ContentId(_postId)), isNull);
    });

    test('C8 — az 500 KIVÉTEL, nem „nincs ilyen poszt"', () async {
      // A kontrollcella: ha minden hibát `null`-ra fordítanánk, egy
      // szerverhiba „a poszt nem látható"-ként jelenne meg a UI-on.
      adapter.status = 500;
      adapter.body = const <String, Object?>{'detail': 'boom'};

      await expectLater(
        repository.fetchPost(postId: ContentId(_postId)),
        throwsA(isA<Object>()),
      );
    });
  });

  group('törlés és engagement', () {
    test('C9 — a poszt törlése DELETE, kulcs-toldalék NÉLKÜL', () async {
      // A végpont nem olvas `idempotency_key`-t; egy kiküldött, némán
      // eldobott query-paraméter ugyanaz a néma hibaosztály, amit a
      // lapozás elnyelése okozott.
      await repository.deletePost(
        postId: ContentId(_postId),
        idempotencyKey: 'key-5',
      );

      expect(adapter.last.method, 'DELETE');
      expect(adapter.last.path, '/community/posts/$_postId');
      expect(adapter.last.path.contains('idempotency_key'), isFalse);
    });

    test('C10 — a reakció beállítása PUT, wire-fajtával', () async {
      adapter.body = const <String, Object?>{
        'post_public_id': _postId,
        'viewer_reaction': 'celebrate',
        'reaction_count': 3,
      };

      await repository.setReaction(
        postId: ContentId(_postId),
        kind: ReactionKind.celebrate,
        idempotencyKey: 'key-6',
      );

      expect(adapter.last.method, 'PUT');
      expect(adapter.last.path, '/community/posts/$_postId/reaction');
      expect(sentBody()['kind'], ReactionKind.celebrate.wireValue);
      expect(sentBody()['idempotency_key'], 'key-6');
    });

    test('C11 — a reakció TÖRLÉSE külön ige (DELETE), nem kind:null', () async {
      // A `SetReactionRequest.kind` kötelező; egy `kind: null` törzs 422
      // lenne. A törlésnek saját végpontja van.
      await repository.setReaction(
        postId: ContentId(_postId),
        kind: null,
        idempotencyKey: 'key-7',
      );

      expect(adapter.last.method, 'DELETE');
      expect(adapter.last.path, '/community/posts/$_postId/reaction');
    });

    test('C12 — az ismeretlen reakció-típus HIBA', () async {
      await expectLater(
        repository.setReaction(
          postId: ContentId(_postId),
          kind: 42,
          idempotencyKey: 'key-8',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('C13 — a könyvjelző két IRÁNYA két külön ige', () async {
      await repository.setBookmark(
        postId: ContentId(_postId),
        bookmarked: true,
        idempotencyKey: 'key-9',
      );
      expect(adapter.last.method, 'POST');
      expect(adapter.last.path, '/community/bookmarks/$_postId');

      await repository.setBookmark(
        postId: ContentId(_postId),
        bookmarked: false,
        idempotencyKey: 'key-10',
      );
      expect(adapter.last.method, 'DELETE');
      expect(adapter.last.path, '/community/bookmarks/$_postId');
    });
  });

  group('kommentek', () {
    test('C14 — az első oldal kurzor NÉLKÜL megy ki', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': null,
      };

      await repository.comments(
        postId: ContentId(_postId),
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(adapter.last.path, '/community/posts/$_postId/comments');
      expect(adapter.last.queryParameters['page_size'], 25);
      expect(adapter.last.queryParameters.containsKey('cursor'), isFalse);
    });

    test('C15 — a folytatólagos kurzor TÉNYLEGESEN kimegy', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[],
        'next_cursor': 'next-token',
      };

      final page = await repository.comments(
        postId: ContentId(_postId),
        cursor: const CursorPage.continued('opaque'),
        limit: 10,
      );

      expect(adapter.last.queryParameters['cursor'], 'opaque');
      expect(adapter.last.queryParameters['page_size'], 10);
      expect(page.cursor, const CursorPage.continued('next-token'));
    });

    test('C16 — a lista vége HALTED, nem INITIAL', () async {
      adapter.body = <String, Object?>{
        'items': <Object?>[_commentJson()],
        'next_cursor': null,
      };

      final page = await repository.comments(
        postId: ContentId(_postId),
        cursor: const CursorPage.continued('t'),
        limit: 25,
      );

      expect(page.cursor, const CursorPage.haltedAfterRequest());
      expect(page.cursor.isInitial, isFalse);
      expect(page.items.single.parentCommentId, isNull);
    });

    test('C17 — a nem szerkesztett komment editedAt-ja null marad', () async {
      // A szerver MINDEN kommenthez ad `resource_version`-t; vakon átvéve
      // minden komment „szerkesztve" jelölést kapna.
      adapter.body = <String, Object?>{
        'items': <Object?>[
          _commentJson(resourceVersion: '2026-09-06T10:00:00Z'),
          _commentJson(
            publicId: '44444444-4444-4444-8444-444444444444',
            resourceVersion: '2026-09-06T11:00:00Z',
          ),
        ],
        'next_cursor': null,
      };

      final page = await repository.comments(
        postId: ContentId(_postId),
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(page.items.first.editedAt, isNull);
      expect(page.items.last.editedAt, isNotNull);
    });

    test('C18 — az ismeretlen moderációs állapot LÁTHATÓ-ra esik', () async {
      adapter.body = <String, Object?>{
        'items': <Object?>[_commentJson(moderationState: 'future_state')],
        'next_cursor': null,
      };

      final page = await repository.comments(
        postId: ContentId(_postId),
        cursor: const CursorPage.initial(),
        limit: 25,
      );

      expect(page.items.single.moderationState, ModerationState.visible);
    });

    test('C19 — a hiányzó kötelező mező hiba, nem néma üres komment', () async {
      adapter.body = const <String, Object?>{
        'items': <Object?>[
          <String, Object?>{'body': 'azonosító nélkül'},
        ],
        'next_cursor': null,
      };

      await expectLater(
        repository.comments(
          postId: ContentId(_postId),
          cursor: const CursorPage.initial(),
          limit: 25,
        ),
        throwsA(isA<Object>()),
      );
    });

    test('C20 — a válasz-komment a poszt alá, a szülővel megy fel', () async {
      adapter.status = 201;
      adapter.body = _commentJson(
        parentPublicId: '55555555-5555-4555-8555-555555555555',
      );

      final comment = await repository.createComment(
        postId: ContentId(_postId),
        parentCommentId: ContentId('55555555-5555-4555-8555-555555555555'),
        body: 'válasz',
        idempotencyKey: 'key-11',
      );

      expect(adapter.last.method, 'POST');
      expect(adapter.last.path, '/community/posts/$_postId/comments');
      expect(sentBody()['body'], 'válasz');
      expect(
        sentBody()['parent_public_id'],
        '55555555-5555-4555-8555-555555555555',
      );
      expect(sentBody()['idempotency_key'], 'key-11');
      expect(comment.parentCommentId, isNotNull);
    });

    test('C21 — a komment törlése a KOMMENT útvonalára megy', () async {
      await repository.deleteComment(
        commentId: ContentId('33333333-3333-4333-8333-333333333333'),
        idempotencyKey: 'key-12',
      );

      expect(adapter.last.method, 'DELETE');
      expect(
        adapter.last.path,
        '/community/comments/33333333-3333-4333-8333-333333333333',
      );
    });
  });

  group('a PATCH-hiány', () {
    test('C22 — a poszt szerkesztése HIBA, nem hamis siker', () async {
      // A `lib/core/network/api_client.dart`-nak nincs PATCH primitívje, és
      // az a fájl nem tartozik ehhez a munkacsomaghoz. Egy csendben
      // eldobott szerkesztés néma adatvesztés lenne.
      await expectLater(
        repository.updatePost(
          postId: ContentId(_postId),
          body: 'új törzs',
          audience: CommunityAudience.public,
          resourceVersion: '2026-09-06T10:00:00Z',
          idempotencyKey: 'key-13',
        ),
        throwsA(isA<UnimplementedError>()),
      );
      // A kérés EL SEM INDULT — nincs olyan primitív, amivel elindulhatna.
      expect(adapter.requests, isEmpty);
    });

    test('C23 — a komment szerkesztése is HIBA', () async {
      await expectLater(
        repository.updateComment(
          commentId: ContentId('33333333-3333-4333-8333-333333333333'),
          body: 'új törzs',
          idempotencyKey: 'key-14',
        ),
        throwsA(isA<UnimplementedError>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });
}
