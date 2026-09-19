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
/// * `createPost` — `POST /community/posts`. Kész. A klub-kontextusban
///   indított szerkesztő a szerződésen KÍVÜLI `createClubPost`-ot hívja
///   (E17-R11) — ugyanaz a végpont, plusz a klub publikus azonosítója.
/// * `fetchPost` — `GET /community/posts/{id}`. Kész. A 404 és a 403
///   egyaránt `null`-t ad: a szerver SZÁNDÉKOSAN egyforma 404-et küld a
///   „nincs ilyen poszt" és a „van, de nem látod" ágra (leak-guard,
///   `routers/posts.py` §5.3), tehát a kliens sem tehet közöttük
///   különbséget. A szerződés `null`-ja pontosan ezt jelenti.
/// * `deletePost`, `setReaction`, `setBookmark`, `comments`,
///   `createComment`, `deleteComment` — kész.
/// * `updatePost`, `updateComment` — **BEKÖTVE (2026-09-06).** Mindkettő
///   `PATCH`-et vár (`PATCH /community/posts/{id}`,
///   `PATCH /community/comments/{id}`); a megosztott `ApiClient`-nek eddig
///   nem volt `PATCH` primitívje, ezért a két metódus dokumentált
///   `UnimplementedError`-t dobott — a `comment_controller.editComment`
///   ÉLESEN ebbe futott bele. Az `ApiClient.patchJson` pótolja a rést, és
///   a két metódus innentől valódi kérést küld.
///
///   **A két kimenő törzs a sémákból van kimérve, nem feltételezve**
///   (`backend/app/community/schemas/{post,comment}.py`, mindkettő
///   `extra="forbid"`):
///
///   * `PatchPostRequest` = `{audience?, body?, artifact?, resource_version}`
///     — **NINCS benne `idempotency_key`**. A szerződés `idempotencyKey`
///     paraméterét ezért NEM küldjük ki: elküldve a `extra="forbid"` 422-t
///     adna, azaz minden poszt-szerkesztés elbukna. A kulcs elhagyása itt
///     NEM néma adatvesztés (gépi dedup-token, nem felhasználói bevitel) —
///     a szerkesztés maga a `resource_version` optimista ellenőrzésén
///     keresztül védett.
///   * Az `artifact` kulcsot SEM küldjük: a `patch_post` szolgáltatás
///     `model_fields_set` szemantikája szerint az EXPLICIT `artifact: null`
///     TÖRLI a poszt artefaktumát, a kulcs hiánya hagyja érintetlenül. A
///     szerződésnek nincs artefaktum-paramétere a szerkesztéshez, tehát a
///     kulcs kiküldése a megosztott tartalom néma törlése lenne.
///   * `PatchCommentRequest` = `{body, resource_version?, idempotency_key?}`
///     — itt a kulcs deklarált, tehát megy. A `resource_version` `null`-t
///     kap: a szerződés `updateComment`-je nem visz verziót, a szolgáltatás
///     pedig a `None`-t „nincs konkurencia-ellenőrzés"-ként kezeli
///     (`comment_service.edit_comment_with_resource_version` docstring).
///
///   **A 409 leképezése.** A szerver mindkét felületen 409-et ad elavult
///   `resource_version`-re (`StalePostUpdateError` / `StaleCommentUpdateError`,
///   a törzsben a JELENLEGI verzióval). Ezt `FailureCode.communityConflict`
///   kódú `ValidationFailure`-ré képezzük — a `profile_repository_impl.dart`
///   precedense —, hogy a hívó meg tudja különböztetni a „valaki más
///   szerkesztette / lejárt a szerkesztési ablak" esetet egy sima 422-es
///   validációs hibától. A `comment_controller.editComment` `AppFailure`-t
///   kap el, tehát a hiba a `lastError`-ba kerül, nem robban ki.
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
import '../../domain/entities/community_bookmark.dart';
import '../../domain/entities/community_comment.dart';
import '../../domain/entities/community_media.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_reaction.dart';
import '../../domain/entities/community_report_receipt.dart';
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
    List<String> mediaIds = const <String>[],
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
        // `media_ids` (javító sáv R27): az ÜRES listát sem küldjük ki, a
        // kulcs hiánya és a `[]` a szerveren ugyanaz, egy fölösleges mező
        // viszont minden szöveges poszt törzsét megnövelné.
        'media_ids': ?_mediaIdsPayload(mediaIds),
        'idempotency_key': idempotencyKey,
      },
      decode: decodeCommunityPost,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  /// Klub-poszt írása — `POST /community/posts` a klub PUBLIKUS
  /// azonosítójával (E17-R11).
  ///
  /// SZÁNDÉKOSAN nem része a `CommunityPostRepository` szerződésnek (a
  /// `listBookmarks` / `clubFeed` precedense): a szerződést tizenkét
  /// teszt-fake valósítja meg, és egy új absztrakt metódus mindet eltörné,
  /// miközben az egyetlen hívó a klub-kontextusban indított szerkesztő
  /// kiürítése (`community_outbox.dart`).
  ///
  /// A klubot a PUBLIKUS azonosítója nevezi meg, nem a belső egész:
  /// a kliens az utóbbit nem ismeri (ADR 0396 §1), és a szerver E17-R11
  /// óta mindkét cím-formára lefuttatja a tagsági kaput. A nem-tag /
  /// ismeretlen / törölt klub egyforma 404-et kap — a hívó ezért NEM tud
  /// (és nem is szabad tudnia) a három eset között különbséget tenni.
  Future<CommunityPost> createClubPost({
    required ContentId clubId,
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
    List<String> mediaIds = const <String>[],
  }) async {
    final result = await _client.postJson<CommunityPost>(
      '/community/posts',
      data: <String, Object?>{
        'audience': audience.wireValue,
        'body': body,
        'club_public_id': clubId.value,
        'artifact': ?_artifactPayload(artifact),
        'media_ids': ?_mediaIdsPayload(mediaIds),
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
    final result = await _client.patchJson<CommunityPost>(
      '/community/posts/${postId.value}',
      data: <String, Object?>{
        'audience': audience.wireValue,
        // A `null` törzs a szerveren „hagyd békén" (`patch_post`:
        // `if "body" in payload and payload["body"] is not None`), NEM
        // ürítés — ezen a felületen nincs mód a törzs törlésére.
        'body': body,
        'resource_version': _resourceVersionWireValue(resourceVersion),
        // `idempotency_key` és `artifact` SZÁNDÉKOSAN kimarad — l. a
        // fájl fejlécének indoklását (422, illetve néma artefaktum-törlés).
      },
      decode: decodeCommunityPost,
      conflictCode: FailureCode.communityConflict,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
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

  /// A néző mentett bejegyzései — `GET /community/bookmarks` (javító sáv
  /// R5, 2026-09-06).
  ///
  /// SZÁNDÉKOSAN nem része a `CommunityPostRepository` szerződésnek (a
  /// `clubFeed` precedense): a szerződést tizenkét teszt-fake valósítja
  /// meg, egy új absztrakt metódus mindet eltörné, miközben a lista
  /// egyetlen fogyasztója a könyvjelző-képernyő vezérlője. A végpont a
  /// `limit` nevű lapméretet olvassa (NEM `page_size`-t, mint a komment-
  /// lista) — egy `page_size` itt némán eldobott paraméter volna.
  Future<CommunityPage<CommunityBookmark>> listBookmarks({
    required Object cursor,
    required int limit,
  }) async {
    final result = await _client.getJson<CommunityPage<CommunityBookmark>>(
      '/community/bookmarks',
      queryParameters: <String, Object?>{
        'limit': limit,
        'cursor': communityCursorQueryValue(cursor),
      },
      decode: decodeCommunityBookmarkPage,
    );
    return switch (result) {
      Success(:final value) => value,
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
    final result = await _client.patchJson<CommunityComment>(
      '/community/comments/${commentId.value}',
      data: <String, Object?>{
        'body': body,
        // A szerződés nem visz `resourceVersion`-t a kommentre; a szerver
        // a `null`-t „nincs konkurencia-ellenőrzés"-ként kezeli. A kulcs
        // deklarált és nullable, tehát az `extra="forbid"` átengedi.
        'resource_version': null,
        'idempotency_key': idempotencyKey,
      },
      decode: decodeCommunityComment,
      conflictCode: FailureCode.communityConflict,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
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

  /// Média feltöltése — `POST /community/media` (javító sáv R27).
  ///
  /// SZÁNDÉKOSAN a szerződésen KÍVÜL, a `createClubPost` precedense
  /// szerint: a `CommunityPostRepository`-t tizenkét teszt-fake
  /// valósítja meg, és egy új absztrakt metódus mindet eltörné.
  ///
  /// **Az ELUTASÍTÁS nem hiba-ág.** A szerver 201-et ad egy
  /// `state: rejected` leíróval is (magic-byte, vírusirtó vagy
  /// átkódolási elutasítás), mert a sor létezik, és az elutasítás
  /// indoka a felhasználónak szóló információ. A metódus ezért az
  /// elutasított leírót is VISSZAADJA — a hívó a
  /// [CommunityMediaAttachment.state] és a `rejectionCode` alapján
  /// dönt. Kivétel csak a valóban kivételes kimenetekre repül: 413
  /// (túl nagy), 409 (kvóta), 429 (fojtás), 401/403, hálózat.
  Future<CommunityMediaAttachment> uploadMedia({
    required List<int> bytes,
    String filename = 'upload.bin',
  }) async {
    final result = await _client.postMultipartJson<CommunityMediaAttachment>(
      '/community/media',
      bytes: bytes,
      filename: filename,
      decode: decodeCommunityMedia,
      conflictCode: FailureCode.communityConflict,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  /// Tartalom-bejelentés — `POST /community/reports` (R33, M10).
  ///
  /// SZÁNDÉKOSAN a szerződésen KÍVÜL, a `createClubPost` / `uploadMedia`
  /// precedense szerint: a `CommunityPostRepository`-t tizenhárom
  /// teszt-fake valósítja meg — kettő közülük PIXELRE PINELT
  /// golden-fájlban él (`e13_r33`, `e15_r13`), amiket ez a kör nem
  /// szerkeszthet —, tehát egy új absztrakt metódus a szerződésen az
  /// egész golden-sávot eltörné.
  ///
  /// A kimenő törzs a `backend/app/community/routers/reports.py` MÉRT
  /// alakja: `{target_type, target_id, category, idempotency_key}`. Az
  /// opcionális `extra_metadata` kulcsot NEM küldjük ki: a bejelentő
  /// szabad szövegét a lap ma nem gyűjti be, egy üres objektum pedig
  /// csak zajt vinne le az eszközről.
  ///
  /// A hibák a szokásos leképezésen mennek: 422 (ismeretlen kategória)
  /// és 400 validációs hiba, 429 és 5xx `networkServer`, 404 „nincs ilyen
  /// cél VAGY nincs bejelentői profilod" — a szerver szándékosan nem
  /// különbözteti meg a kettőt, tehát a kliens sem tehet úgy, mintha
  /// tudná, melyik történt.
  Future<CommunityReportReceipt> submitReport({
    required String targetType,
    required String targetId,
    required String category,
    required String idempotencyKey,
  }) async {
    final result = await _client.postJson<CommunityReportReceipt>(
      '/community/reports',
      data: <String, Object?>{
        'target_type': targetType,
        'target_id': targetId,
        'category': category,
        'idempotency_key': idempotencyKey,
      },
      decode: decodeCommunityReportReceipt,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  /// Feltöltött média eldobása — `DELETE /community/media/{id}`.
  ///
  /// A szerver idempotens: egy már törölt sor újratörlése is 200. A
  /// nem létező és a NEM A TIÉD egyaránt 404 (leak-guard), tehát a
  /// hívó a kettő között nem tud — és nem is szabad — különbséget
  /// tenni; a szerkesztő ezért a 404-et is „eltávolítva"-ként kezeli.
  Future<void> deleteMedia({required String mediaPublicId}) async {
    final result = await _client.delete('/community/media/$mediaPublicId');
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }
}

/// Az optimista konkurencia-token wire-alakja.
///
/// A szerződés `Object`-et enged (a `CommunityPost.editedAt` egy
/// `DateTime`, a nyers wire-érték egy ISO-8601 sztring), a
/// `PatchPostRequest.resource_version` viszont KÖTELEZŐ `datetime`. Egy
/// `toString()`-gel „megmentett" ismeretlen típus itt 422-t adna a
/// szerveren — és mivel a token az egyetlen védelem a felülírás ellen, a
/// félreértett érték csendben MÁS szerkesztését dobná el. Ezért csak a két
/// értelmes alakot fogadjuk el.
String _resourceVersionWireValue(Object resourceVersion) {
  if (resourceVersion is DateTime) {
    return resourceVersion.toUtc().toIso8601String();
  }
  if (resourceVersion is String && resourceVersion.isNotEmpty) {
    return resourceVersion;
  }
  throw ArgumentError.value(
    resourceVersion,
    'resourceVersion',
    'resource version must be a DateTime or its ISO-8601 wire string',
  );
}

/// A csatolt médiák wire-alakja, vagy `null`, ha nincs mit küldeni.
///
/// A `CreatePostRequest.media_ids` nullable és `max_length`-korlátos. Az
/// ÜRES listát azért nem küldjük ki, mert a szerveren pontosan ugyanaz,
/// mint a hiányzó kulcs (`if media_ids:`), a kulcs viszont minden
/// szöveges poszt törzsében ott ülne. Az üres sztringet KISZŰRJÜK, nem
/// elnyeljük a listát: egy hibás azonosító a szerveren 400-at ad, ami a
/// helyes válasz — a néma elhagyás azt jelentené, hogy a felhasználó
/// csatolmány nélkül lát sikert.
List<String>? _mediaIdsPayload(List<String> mediaIds) {
  final cleaned = <String>[
    for (final id in mediaIds)
      if (id.isNotEmpty) id,
  ];
  return cleaned.isEmpty ? null : cleaned;
}

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
