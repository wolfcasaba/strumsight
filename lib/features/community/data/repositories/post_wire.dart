/// A poszt wire-alak KÖZÖS dekódolója (2026-09-05).
///
/// A `FeedPostItem` alakot négy felület adja vissza a szerveren — a
/// következés-feed, a klub-feed, a kitűzött posztok listája és a
/// poszt-detail —, és mindegyiket ugyanaz a `post_projection.py` állítja
/// elő. A kliens-oldalon ezért EGY dekóder tartozik hozzá: ha minden
/// repository a sajátját írná, a „hiányzó mező" kezelése négyfelé csúszna
/// szét, és a hiba csak egyetlen képernyőn jelenne meg.
///
/// **Az ismeretlen mező nem hiba, a hiányzó KÖTELEZŐ mező igen.** A
/// dekóder a nem ismert kulcsokat átlépi (a szerver bővíthető anélkül,
/// hogy a régi kliens elhasalna), de egy hiányzó `public_id` vagy
/// `created_at` `FormatException` — az a válasz nem poszt.
library;

import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_reaction.dart';
import '../../domain/entities/moderation_state.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';

/// A [CursorPage] → query-paraméter átalakítás.
///
/// A `CursorPage.initial()` és a `haltedAfterRequest()` egyaránt `null`-t
/// ad — az első kérés és a lista vége is „nincs kurzor" a huzalon. A két
/// állapot a HÍVÓ oldalán különbözik (a `halted` után nem is illik újra
/// kérni), a szerver felé nincs mit megkülönböztetni.
String? communityCursorQueryValue(Object cursor) {
  if (cursor is CursorPage) return cursor.cursor;
  throw ArgumentError.value(
    cursor,
    'cursor',
    'cursor must be a CursorPage (initial / continued / haltedAfterRequest)',
  );
}

/// A szerver `next_cursor` mezőjéből [CursorPage].
///
/// `null` ⇒ [CursorPage.haltedAfterRequest] — NEM `initial`. A
/// megkülönböztetés a `cursor_page.dart` L349-es mért csapdája: az
/// „első kérés előtt" és a „nincs több oldal" ugyanabba a nullable
/// mezőbe csúszott össze, és a lapozó a lista végén újraindult.
CursorPage communityCursorFromWire(Object? rawNextCursor) {
  if (rawNextCursor == null) return const CursorPage.haltedAfterRequest();
  if (rawNextCursor is String && rawNextCursor.isNotEmpty) {
    return CursorPage.continued(rawNextCursor);
  }
  throw const FormatException(
    'community wire: next_cursor must be a non-empty string or null',
  );
}

/// Egy `FeedPostItem` → [CommunityPost].
CommunityPost decodeCommunityPost(Map<String, Object?> json) {
  final publicId = json['public_id'];
  final authorPublicId = json['author_public_id'];
  if (publicId is! String || authorPublicId is! String) {
    throw const FormatException(
      'community post wire: public_id and author_public_id are required',
    );
  }
  return CommunityPost(
    id: ContentId(publicId),
    authorId: PublicUserId(authorPublicId),
    audience: _audienceFromWire(json['audience']),
    body: json['body'] as String?,
    // A Kör 10 konkrét artefaktum-altípusai még nem születtek meg; a
    // `schemaVersion == 0` sentinel jelöli, hogy a mező kitöltetlen.
    // Egy kitalált altípus itt azt hazudná, hogy a megosztott tartalom
    // értelmezve van.
    artifact: UnfilledCommunityShareArtifact(),
    createdAt: _requiredTime(json['created_at'], 'created_at'),
    editedAt: _resourceVersionAsEditedAt(json),
    moderationState:
        moderationStateFromWire(json['moderation_state'] as String?) ??
        ModerationState.visible,
    counts: CommunityPostCounts(
      reactionCount: _count(json['reaction_count']),
      commentCount: _count(json['comment_count']),
      bookmarkCount: _count(json['bookmark_count']),
    ),
    viewerState: CommunityViewerPostState(
      // A szerver a könyvjelzőt logikai értékként adja, időbélyeg nélkül.
      // A `bookmarkedAt` ezért `null` marad AKKOR IS, ha a néző elmentette
      // a posztot — egy kitalált „most" időbélyeg későbbi rendezéseket
      // rontana el. A UI a `myReaction`/`bookmarkedAt` helyett a
      // számlálókra és a `viewer_bookmarked`-re épít.
      bookmarkedAt: null,
      myReaction: reactionKindFromWire(json['viewer_reaction'] as String?),
    ),
  );
}

/// Egy `{items, next_cursor}` boríték → [CommunityPage].
CommunityPage<CommunityPost> decodeCommunityPostPage(Map<String, Object?> json) {
  final rawItems = json['items'];
  if (rawItems is! List) {
    throw const FormatException('community post page wire: items must be a list');
  }
  return CommunityPage<CommunityPost>(
    items: [
      for (final raw in rawItems)
        if (raw is Map<String, Object?>)
          decodeCommunityPost(raw)
        else
          throw const FormatException(
            'community post page wire: every item must be a JSON object',
          ),
    ],
    // A kitűzött-poszt lista SZÁNDÉKOSAN nem visz `next_cursor` mezőt (a
    // kitűzhető posztok száma korlátos), ezért a hiányzó kulcs itt
    // `halted` — nem hiba.
    cursor: communityCursorFromWire(json['next_cursor']),
  );
}

/// A néző poszthoz fűződő viszonya — a reakció-végpont válaszából.
///
/// A `PUT`/`DELETE /community/posts/{id}/reaction` a művelet UTÁNI
/// állapotot adja vissza; ezt olvassa ki a repository, hogy a UI a
/// szerver számát vegye át, ne a sajátját számolja.
({String postPublicId, ReactionKind? viewerReaction, int reactionCount})
decodeReactionState(Map<String, Object?> json) {
  final postPublicId = json['post_public_id'];
  if (postPublicId is! String) {
    throw const FormatException(
      'reaction state wire: post_public_id is required',
    );
  }
  return (
    postPublicId: postPublicId,
    viewerReaction: reactionKindFromWire(json['viewer_reaction'] as String?),
    reactionCount: _count(json['reaction_count']),
  );
}

CommunityAudience _audienceFromWire(Object? raw) {
  for (final value in CommunityAudience.values) {
    if (value.wireValue == raw) return value;
  }
  // Ismeretlen közönség: a LEGSZŰKEBB értelmezés. Egy ismeretlen érték
  // `public`-ra kerekítése azt jelentené, hogy egy jövőbeli, szűkebb
  // közönségű poszt a régi kliensen nyilvánosnak látszik.
  return CommunityAudience.private;
}

DateTime _requiredTime(Object? raw, String field) {
  if (raw is! String) {
    throw FormatException('community post wire: $field is required');
  }
  return DateTime.parse(raw).toUtc();
}

/// A `resource_version` (a szerver `updated_at`-je) csak akkor
/// szerkesztés-időpont, ha KÉSŐBBI a létrehozásnál.
///
/// A szerver minden poszthoz ad `resource_version`-t (optimista
/// konkurenciához), és egy soha nem szerkesztett poszton ez megegyezik a
/// `created_at`-tel. Vakon átvéve minden poszt „szerkesztve" jelölést
/// kapna — és az entitás sem fogadná el, ha korábbi lenne.
DateTime? _resourceVersionAsEditedAt(Map<String, Object?> json) {
  final raw = json['resource_version'];
  if (raw is! String) return null;
  final createdAt = _requiredTime(json['created_at'], 'created_at');
  final version = DateTime.parse(raw).toUtc();
  return version.isAfter(createdAt) ? version : null;
}

int _count(Object? raw) {
  if (raw is int) return raw < 0 ? 0 : raw;
  return 0;
}
