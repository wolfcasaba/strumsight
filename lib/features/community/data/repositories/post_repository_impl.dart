/// Dio-backed implementation of [CommunityPostRepository] (2026-09-06).
///
/// **Miért csak most.** A `CommunityPostRepository` szerződés a Kör 5 óta
/// állt, és a provider-definíciója a `post_composer_controller.dart`-ban
/// egy `StateError`-t dobó seam volt („must be overridden in production").
/// A szállított kompozícióban SENKI nem írta felül, tehát a feed-kártya,
/// a szerkesztő, a komment-lista és a reakció-sáv is `StateError`-t kapott
/// volna az első hívásnál. A provider EGYETLEN definíciója innentől ITT
/// él; a controller csak re-exportál (a `feed_repository_impl.dart` /
/// `challenge_repository_impl.dart` precedens, és a MÉRT duplikált-seam
/// hibaosztály orvossága).
///
/// **A tíz szerződés-metódus NEM egyforma állapotú, és ezt a kód kimondja:**
///
/// * `createPost` — `POST /community/posts`. Kész.
/// * `fetchPost` — `GET /community/posts/{id}`. Kész. A 404 és a 403
///   egyaránt `null`-t ad: a szerver SZÁNDÉKOSAN egyforma 404-et küld a
///   „nincs ilyen poszt" és a „van, de nem látod" ágra (leak-guard,
///   `routers/posts.py` §5.3), tehát a kliens sem tehet közöttük
///   különbséget. A szerződés `null`-ja pontosan ezt jelenti.
/// * `deletePost`, `setReaction`, `setBookmark`, `comments`,
///   `createComment`, `deleteComment` — kész.
/// * `updatePost`, `updateComment` — **NEM köthető be ebben a sávban.**
///   A szerver mindkettőhöz `PATCH`-et vár (`PATCH /community/posts/{id}`,
///   `PATCH /community/comments/{id}`), a megosztott `ApiClient`-nek
///   viszont NINCS `PATCH` primitívje (`lib/core/network/api_client.dart`:
///   `getJson` / `postJson` / `putJson` / `post` / `delete`), és az a fájl
///   nem tartozik ehhez a munkacsomaghoz. A két metódus ezért dokumentált
///   `UnimplementedError`-t dob, és NEM hazudik: egy `PUT`-tal
///   helyettesített `PATCH` 405-öt kapna, egy csendben elhagyott
///   szerkesztés pedig a mért néma-no-op hibaosztály lenne.
///
/// **A DELETE végpontok nem visznek idempotencia-kulcsot.** A
/// `routers/posts.py`, `routers/comments.py`, `routers/reactions.py` és
/// `routers/bookmarks.py` törlő végpontjai csak a JWT-t és az útvonalat
/// olvassák — a lágy törlés természetéből adódóan idempotens (egy második
/// hívás sikeres no-op). A `?idempotency_key=…` toldalékot ezért NEM
/// küldjük: a FastAPI némán eldobná az ismeretlen query-paramétert, és egy
/// elfogadottnak látszó, de figyelmen kívül hagyott paraméter ugyanaz a
/// néma hibaosztály, amit a lapozás elnyelése okozott (L. `api_client.dart`
/// `queryParameters` megjegyzése).
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../features/auth/public.dart';
import '../../domain/entities/community_comment.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_reaction.dart';
import '../../domain/entities/moderation_state.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/public_user_id.dart';
import 'post_wire.dart';

/// Az account-réteg Dio kliense, lustán — a fiók nélküli build sosem
/// építi fel. Ugyanaz a minta, mint a `communityFeedApiClientProvider`.
final communityPostApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// A bekötött poszt-repository — a szerződés EGYETLEN provider-definíciója.
///
/// A fiókréteg kikapcsolt állásán a [DisabledCommunityPostRepository]
/// felel; a hívó kód mindkét ágon ugyanaz.
final communityPostRepositoryProvider = Provider<CommunityPostRepository>((
  ref,
) {
  final client = ref.watch(communityPostApiClientProvider);
  if (client == null) return const DisabledCommunityPostRepository();
  return HttpCommunityPostRepository(client);
});

/// Fiók nélküli mód: minden hívás `ConfigurationFailure`.
final class DisabledCommunityPostRepository implements CommunityPostRepository {
  const DisabledCommunityPostRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) async =>
      throw _disabled.error;

  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;

  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) async => throw _disabled.error;
}

/// Élő, HTTP-alapú poszt- és engagement-repository.
final class HttpCommunityPostRepository implements CommunityPostRepository {
  const HttpCommunityPostRepository(this._client);

  final ApiClient _client;

  // ---- poszt-életciklus -------------------------------------------------

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<CommunityPost>(
      '/community/posts',
      data: <String, Object?>{
        'audience': audience.wireValue,
        // A `CreatePostRequest.body` KÖTELEZŐ és `min_length=1`. A
        // szerződés `String?`-t enged, a szerver nem: egy törzs nélküli,
        // csak artefaktumot hordozó poszt ma 422-vel tér vissza. A kulcsot
        // `null` esetén sem hagyjuk el csendben — a hívó a validációs
        // hibából megtudja, hogy a törzs kell.
        'body': body,
        // `extra="forbid"`: az ÜRES artefaktum-térkép nem küldhető el,
        // mert a `parse_share_artifact` diszkriminátort vár. A szerkesztő
        // alapértelmezése épp az üres térkép (`composerSourceArtifactProvider`).
        'artifact': ?_artifactPayload(artifact),
        'idempotency_key': idempotencyKey,
      },
      decode: decodeCommunityPost,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) async {
    final result = await _client.getJson<CommunityPost>(
      '/community/posts/${postId.value}',
      decode: decodeCommunityPost,
    );
    return switch (result) {
      Success(:final value) => value,
      // A szerződés `null`-ja = „a néző számára nem látható". A szerver a
      // nem létező és a REJTETT posztot megkülönböztethetetlenül 404-eli
      // (`routers/posts.py` §5.3 leak-guard); a 403 ugyanezt jelenti a
      // hitelesítési rétegből. A státusz a `DioException`-ből jön, NEM a
      // `FailureCode`-ból: a `networkBadResponse` egy elrontott JSON-ra is
      // ráillik, és arra `null`-t adni azt hazudná, hogy a poszt rejtett.
      Failure(:final error) when _isHiddenOrMissing(error) => null,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError(_patchGapMessage('PATCH /community/posts/{id}'));
  }

  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) async {
    final result = await _client.delete('/community/posts/${postId.value}');
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }

  // ---- engagement -------------------------------------------------------

  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) async {
    final path = '/community/posts/${postId.value}/reaction';
    if (kind == null) {
      // A reakció TÖRLÉSE külön ige a szerveren (`DELETE .../reaction`),
      // nem egy `kind: null` törzs — a `SetReactionRequest.kind` kötelező.
      final removed = await _client.delete(path);
      return switch (removed) {
        Success() => null,
        Failure(:final error) => throw error,
      };
    }
    final result = await _client.putJson<void>(
      path,
      data: <String, Object?>{
        'kind': _reactionWireValue(kind),
        'idempotency_key': idempotencyKey,
      },
      // A válasz a művelet UTÁNI állapotot hordozza (`ReactionStateOut`).
      // A szerződés `Future<void>`, ezért csak ÉRVÉNYESÍTJÜK a választ —
      // egy alakilag rossz nyugta így nem megy át sikerként.
      decode: (json) {
        decodeReactionState(json);
      },
    );
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) async {
    final path = '/community/bookmarks/${postId.value}';
    final result = bookmarked
        ? await _client.post(path)
        : await _client.delete(path);
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }

  // ---- kommentek --------------------------------------------------------

  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) async {
    final result = await _client.getJson<CommunityPage<CommunityComment>>(
      '/community/posts/${postId.value}/comments',
      queryParameters: <String, Object?>{
        'page_size': limit,
        // A `null` kurzort az `ApiClient` kihagyja — a szerver egy
        // `cursor=null`-t ismeretlen bemenetként kezelne.
        'cursor': communityCursorQueryValue(cursor),
      },
      decode: decodeCommunityCommentPage,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<CommunityComment>(
      '/community/posts/${postId.value}/comments',
      data: <String, Object?>{
        'body': body,
        // `extra="forbid"` mellett a `null` szülő kulcsa MEHET (a mező
        // deklarált és nullable) — a felső szintű komment így jelöli
        // magát, és nem kell két külön törzs-alak.
        'parent_public_id': parentCommentId?.value,
        'idempotency_key': idempotencyKey,
      },
      decode: decodeCommunityComment,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError(
      _patchGapMessage('PATCH /community/comments/{id}'),
    );
  }

  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) async {
    final result = await _client.delete(
      '/community/comments/${commentId.value}',
    );
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }
}

/// A `PATCH`-hiány EGYETLEN, szó szerinti megfogalmazása.
///
/// Külön függvény, hogy a két hívási hely üzenete ne csúszhasson szét, és
/// hogy a rés megszűnésekor egy helyen kelljen törölni.
String _patchGapMessage(String endpoint) =>
    'A szerkesztés végpontja `$endpoint`, a megosztott `ApiClient`-nek '
    'viszont nincs PATCH primitívje (getJson / postJson / putJson / post / '
    'delete). A hiány pótlása a `lib/core/network/api_client.dart` fájlt '
    'érinti, ami nem tartozik ehhez a munkacsomaghoz. Egy PUT-tal '
    'helyettesített PATCH 405-öt kapna, egy csendben eldobott szerkesztés '
    'pedig néma adatvesztés lenne — ezért ez a metódus HIBÁT ad, nem '
    'hamis sikert.';

/// A poszt-artefaktum wire-alakja, vagy `null`, ha nincs mit küldeni.
///
/// Az ÜRES térkép nem artefaktum: a szerkesztő alapértelmezése ez, és a
/// szerver `parse_share_artifact`-ja diszkriminátort vár, tehát egy üres
/// objektum 422 lenne. Egy nem-térkép artefaktum viszont NEM nyelhető el
/// csendben — az a felhasználó megosztott tartalmának néma elvesztése.
Map<String, Object?>? _artifactPayload(Object artifact) {
  if (artifact is Map<String, Object?>) {
    return artifact.isEmpty ? null : artifact;
  }
  if (artifact is Map) {
    final converted = <String, Object?>{};
    for (final entry in artifact.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(
          artifact,
          'artifact',
          'artifact json keys must be strings',
        );
      }
      converted[key] = entry.value;
    }
    return converted.isEmpty ? null : converted;
  }
  throw ArgumentError.value(
    artifact,
    'artifact',
    'artifact must be the ShareArtifact.toJson() map; the wire schema '
        'has no other representation',
  );
}

/// A reakció fajtájának wire-alakja.
///
/// A hívók (`ReactionController`) az ENUM-ot adják át; a szerződés
/// `Object?`-et enged, ezért a nyers wire-sztringet is elfogadjuk. Minden
/// más típus hiba — egy `toString()`-gel „megmentett" ismeretlen érték a
/// szerver allowlistjén úgyis elhasalna, csak később és homályosabban.
String _reactionWireValue(Object kind) {
  if (kind is ReactionKind) return kind.wireValue;
  if (kind is String && kind.isNotEmpty) return kind;
  throw ArgumentError.value(
    kind,
    'kind',
    'reaction kind must be a ReactionKind or its wire string',
  );
}

/// Igaz, ha a hiba a „nem létezik VAGY nem látható" ág.
///
/// A státuszt a `DioException`-ből olvassuk, nem a `FailureCode`-ból: a
/// 404-et a `mapNetworkFailure` `networkBadResponse`-ra képezi, amire egy
/// elrontott JSON-válasz is ráillik — arra `null`-t adni azt állítaná,
/// hogy a poszt rejtett, holott csak a válasz volt hibás.
bool _isHiddenOrMissing(AppFailure failure) {
  final cause = failure.cause;
  if (cause is! DioException) return false;
  final status = cause.response?.statusCode;
  return status == 404 || status == 403;
}

/// Egy `CommentOut` → [CommunityComment].
///
/// **Az ismeretlen mező nem hiba, a hiányzó KÖTELEZŐ mező igen** — ugyanaz
/// a szabály, amit a `post_wire.dart` dokumentál.
CommunityComment decodeCommunityComment(Map<String, Object?> json) {
  final publicId = json['public_id'];
  final postPublicId = json['post_public_id'];
  final authorPublicId = json['author_public_id'];
  final body = json['body'];
  if (publicId is! String ||
      postPublicId is! String ||
      authorPublicId is! String ||
      body is! String) {
    throw const FormatException(
      'community comment wire: public_id, post_public_id, '
      'author_public_id and body are required',
    );
  }
  final parentPublicId = json['parent_public_id'];
  final createdAt = _requiredTime(json['created_at'], 'created_at');
  final deletedAt = _optionalTime(json['deleted_at']);
  return CommunityComment(
    id: ContentId(publicId),
    authorId: PublicUserId(authorPublicId),
    postId: ContentId(postPublicId),
    parentCommentId: parentPublicId is String && parentPublicId.isNotEmpty
        ? ContentId(parentPublicId)
        : null,
    body: body,
    createdAt: createdAt,
    // A `resource_version` a szerver `updated_at`-je, és minden kommenten
    // ott van (optimista konkurenciához). Vakon átvéve MINDEN komment
    // „szerkesztve" jelölést kapna — ezért csak akkor szerkesztés-időpont,
    // ha KÉSŐBBI a létrehozásnál (a `post_wire.dart` mért precedense).
    editedAt: _resourceVersionAsEditedAt(json, createdAt),
    deletedAt: deletedAt,
    moderationState:
        moderationStateFromWire(json['moderation_state'] as String?) ??
        ModerationState.visible,
  );
}

/// Egy `CommentPage` boríték → [CommunityPage].
CommunityPage<CommunityComment> decodeCommunityCommentPage(
  Map<String, Object?> json,
) {
  final rawItems = json['items'];
  if (rawItems is! List) {
    throw const FormatException(
      'community comment page wire: items must be a list',
    );
  }
  return CommunityPage<CommunityComment>(
    items: [
      for (final raw in rawItems)
        if (raw is Map<String, Object?>)
          decodeCommunityComment(raw)
        else
          throw const FormatException(
            'community comment page wire: every item must be a JSON object',
          ),
    ],
    cursor: communityCursorFromWire(json['next_cursor']),
  );
}

DateTime _requiredTime(Object? raw, String field) {
  if (raw is! String) {
    throw FormatException('community comment wire: $field is required');
  }
  return DateTime.parse(raw).toUtc();
}

DateTime? _optionalTime(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.parse(raw).toUtc();
}

DateTime? _resourceVersionAsEditedAt(
  Map<String, Object?> json,
  DateTime createdAt,
) {
  final raw = json['resource_version'];
  if (raw is! String) return null;
  final version = DateTime.parse(raw).toUtc();
  return version.isAfter(createdAt) ? version : null;
}
