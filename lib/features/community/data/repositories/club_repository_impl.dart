/// Dio-backed implementation of [CommunityClubRepository] (2026-09-06).
///
/// **Miért csak most.** A `CommunityClubRepository` szerződés a Kör 5 óta
/// állt, a provider-definíciója viszont a `club_list_screen.dart`-ban egy
/// `UnimplementedError`-t dobó seam volt („Kör 24 wire impl not in
/// scope"). A szállított kompozícióban senki nem írta felül, tehát mind a
/// három klub-képernyő (`ClubListScreen`, `ClubDetailScreen`,
/// `ClubMemberManagementScreen`) az első olvasásnál elszállt volna. A
/// provider EGYETLEN definíciója innentől ITT él; a képernyő re-exportál.
///
/// **MÉRT SZERZŐDÉS-RÉSEK.** A Dart-szerződés három olyan bemenetet kér,
/// amit a szerver felülete NEM fogad — mindhármat a séma docstringje is
/// kimondja (`backend/app/community/schemas/club.py`):
///
/// * `tags` — a `community_clubs` táblában **nincs tags oszlop**, és sem a
///   `CreateClubRequest`, sem az `UpdateClubRequest` nem deklarál ilyen
///   mezőt (`extra="forbid"`, tehát elküldve 422 lenne). A repository
///   ezért NEM küldi el — de csak ÜRES listát fogad el csendben: egy nem
///   üres címke-lista eldobása a felhasználó bevitelének néma elvesztése
///   volna, arra `ArgumentError` jár. A dekóder oldalán a `tags` mindig
///   üres lista, mert a `ClubOut`-nak nincs ilyen mezője.
/// * `resourceVersion` (`updateClub`) — az `UpdateClubRequest`-nek nincs
///   `resource_version` mezője; a szerver a klub-szerkesztést vak írásként
///   végzi. Optimista konkurencia-ellenőrzés tehát NINCS ezen a felületen.
/// * a `listClubs` **kurzora** — a `GET /community/clubs` csak
///   `page_size`-t fogad, a `list_clubs` service `limit`-alapú, és a
///   `ClubPage.next_cursor` MA MINDIG `null`. A kurzort ezért nem küldjük
///   ki: egy elfogadottnak látszó, de figyelmen kívül hagyott paraméter
///   ugyanaz a néma hibaosztály, amit a feed lapozásánál már megmértünk. A
///   válasz `haltedAfterRequest` kurzort ad — a lista egyoldalas.
///
/// **`updateClub` NEM köthető be ebben a sávban.** A végpont `PATCH
/// /community/clubs/{id}`, a megosztott `ApiClient`-nek viszont nincs
/// `PATCH` primitívje, és a `lib/core/network/api_client.dart` nem
/// tartozik ehhez a munkacsomaghoz. A metódus dokumentált
/// `UnimplementedError`-t dob — l. a `post_repository_impl.dart` azonos
/// résének indoklását.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../features/auth/public.dart';
import '../../domain/entities/community_club.dart';
import '../../domain/repositories/club_repository.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';

/// Az account-réteg Dio kliense, lustán — a fiók nélküli build sosem
/// építi fel.
final communityClubApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// A bekötött klub-repository — a szerződés EGYETLEN provider-definíciója.
final communityClubRepositoryProvider = Provider<CommunityClubRepository>((
  ref,
) {
  final client = ref.watch(communityClubApiClientProvider);
  if (client == null) return const DisabledCommunityClubRepository();
  return HttpCommunityClubRepository(client);
});

/// Fiók nélküli mód: minden hívás `ConfigurationFailure`.
final class DisabledCommunityClubRepository implements CommunityClubRepository {
  const DisabledCommunityClubRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async =>
      throw _disabled.error;

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async => throw _disabled.error;

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async => throw _disabled.error;
}

/// Élő, HTTP-alapú klub-repository.
final class HttpCommunityClubRepository implements CommunityClubRepository {
  const HttpCommunityClubRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async {
    // A `cursor` SZÁNDÉKOSAN nem megy ki — l. a modul docstringjét. A
    // paraméter a szerződés része, a felület nem ismeri; egy kiküldött,
    // némán eldobott kurzor rosszabb, mint a be nem küldött.
    final result = await _client.getJson<CommunityPage<CommunityClub>>(
      '/community/clubs',
      queryParameters: <String, Object?>{'page_size': limit},
      decode: decodeCommunityClubPage,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async {
    final result = await _client.getJson<CommunityClub>(
      '/community/clubs/${clubId.value}',
      decode: decodeCommunityClub,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async {
    _rejectUnsupportedTags(tags);
    final result = await _client.postJson<CommunityClub>(
      '/community/clubs',
      data: <String, Object?>{
        'name': name,
        'description': description,
        'visibility': clubVisibilityToWire(visibility),
        'idempotency_key': idempotencyKey,
      },
      decode: decodeCommunityClub,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError(
      'A klub szerkesztésének végpontja `PATCH /community/clubs/{id}`, a '
      'megosztott `ApiClient`-nek viszont nincs PATCH primitívje (getJson / '
      'postJson / putJson / post / delete). A hiány pótlása a '
      '`lib/core/network/api_client.dart` fájlt érinti, ami nem tartozik '
      'ehhez a munkacsomaghoz. Egy PUT-tal helyettesített PATCH 405-öt '
      'kapna, egy csendben eldobott szerkesztés pedig néma adatvesztés '
      'lenne — ezért ez a metódus HIBÁT ad, nem hamis sikert. (A felület '
      'ráadásul sem `tags`-et, sem `resource_version`-t nem fogad.)',
    );
  }

  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/clubs/${clubId.value}/join',
      data: <String, Object?>{'idempotency_key': idempotencyKey},
    );
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/clubs/${clubId.value}/invites',
      data: <String, Object?>{
        'target_public_id': target.value,
        'idempotency_key': idempotencyKey,
      },
    );
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/clubs/${clubId.value}/leave',
      data: <String, Object?>{'idempotency_key': idempotencyKey},
    );
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async {
    // A `DELETE .../members/{target}` sem törzset, sem idempotencia-kulcsot
    // nem olvas — a tag eltávolítása természetéből adódóan idempotens. A
    // kulcsot ezért nem toldjuk query-paraméterként sem: a FastAPI némán
    // eldobná, és az elfogadottnak látszó, figyelmen kívül hagyott
    // paraméter a mért néma hibaosztály.
    final result = await _client.delete(
      '/community/clubs/${clubId.value}/members/${memberId.value}',
    );
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async {
    final result = await _client.post(
      '/community/clubs/${clubId.value}/owner',
      data: <String, Object?>{
        'target_public_id': newOwnerId.value,
        'idempotency_key': idempotencyKey,
      },
    );
    return switch (result) {
      Success() => null,
      Failure(:final error) => throw error,
    };
  }
}

/// A `tags` szerződés-paraméter őre.
///
/// A felület nem ismeri a címkéket. Egy ÜRES lista elhagyása veszteség
/// nélküli (ma minden hívó ezt adja), egy nem üres listáé viszont a
/// felhasználó bevitelének néma elvesztése lenne.
void _rejectUnsupportedTags(List<String> tags) {
  if (tags.isEmpty) return;
  throw ArgumentError.value(
    tags,
    'tags',
    'a klub-címkézésnek nincs szerver-oldali felülete (nincs tags oszlop, '
        'és a CreateClubRequest / UpdateClubRequest extra="forbid"); a '
        'címkék csendes eldobása helyett a hívás elutasított',
  );
}

/// Egy `ClubOut` → [CommunityClub].
CommunityClub decodeCommunityClub(Map<String, Object?> json) {
  final publicId = json['public_id'];
  final ownerPublicId = json['owner_public_id'];
  final name = json['name'];
  if (publicId is! String || ownerPublicId is! String || name is! String) {
    throw const FormatException(
      'community club wire: public_id, owner_public_id and name are required',
    );
  }
  return CommunityClub(
    id: ContentId(publicId),
    name: name,
    description: json['description'] as String? ?? '',
    // Ismeretlen láthatóság: a LEGSZŰKEBB értelmezés. Egy jövőbeli,
    // szűkebb érték `public`-ra kerekítése azt jelentené, hogy a régi
    // kliens nyilvánosnak MUTAT egy nem nyilvános klubot.
    visibility:
        clubVisibilityFromWire(json['visibility'] as String?) ??
        ClubVisibility.private,
    // A `ClubOut`-nak NINCS `tags` mezője (nincs mögötte oszlop sem). Az
    // üres lista itt nem állítás a címkékről, hanem a hiányzó felület
    // egyenes leképezése — l. a modul docstringjét.
    tags: const <String>[],
    ownerId: PublicUserId(ownerPublicId),
    memberCount: _memberCount(json['member_count']),
    myRole: _roleFromWire(json['my_role']),
    createdAt: _requiredTime(json['created_at'], 'created_at'),
  );
}

/// Egy `ClubPage` boríték → [CommunityPage].
CommunityPage<CommunityClub> decodeCommunityClubPage(
  Map<String, Object?> json,
) {
  final rawItems = json['items'];
  if (rawItems is! List) {
    throw const FormatException(
      'community club page wire: items must be a list',
    );
  }
  return CommunityPage<CommunityClub>(
    items: [
      for (final raw in rawItems)
        if (raw is Map<String, Object?>)
          decodeCommunityClub(raw)
        else
          throw const FormatException(
            'community club page wire: every item must be a JSON object',
          ),
    ],
    // A `next_cursor` ma MINDIG `null` (a service `limit`-alapú), tehát a
    // lista egyoldalas: `halted`, nem `initial`. A két állapot összemosása
    // mért csapda — a lapozó a lista végén újraindulna.
    cursor: _clubPageCursor(json['next_cursor']),
  );
}

CursorPage _clubPageCursor(Object? rawNextCursor) {
  if (rawNextCursor == null) return const CursorPage.haltedAfterRequest();
  if (rawNextCursor is String && rawNextCursor.isNotEmpty) {
    return CursorPage.continued(rawNextCursor);
  }
  throw const FormatException(
    'community club page wire: next_cursor must be a non-empty string or null',
  );
}

/// A NÉZŐ szerepe a klubban — `null`, ha nem tag.
///
/// Ismeretlen szerep-sztring `null`-t ad: a `myRole == null` az a bemenet,
/// amire a képernyők a TARTALMAT ELREJTIK. Egy ismeretlen értéket
/// `member`-re kerekítve egy jövőbeli, szűkebb jogú szerep teljes
/// klub-tartalmat látna — ez a szivárgás iránya, tehát a fallback a
/// szigorúbb ág.
ClubRole? _roleFromWire(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  for (final role in ClubRole.values) {
    if (role.name == raw) return role;
  }
  return null;
}

/// A tagszám a `CommunityClub` dokumentált korlátai közé vágva.
///
/// Az alsó vágás (1) szerkezeti igazság: a tulajdonos mindig tag. A felső
/// vágás azt az esetet fedi, amikor a szerver-oldali korlát elmozdul a
/// kliensé alól — a klub-sor eldobása (kivétel a dekódolás közben) az
/// EGÉSZ listát megölné egyetlen elavult konstans miatt. A vágás nem
/// állítás a valódi tagszámról, hanem a lista életben tartása.
int _memberCount(Object? raw) {
  if (raw is! int) return 1;
  if (raw < 1) return 1;
  if (raw > kCommunityClubMaxMembers) return kCommunityClubMaxMembers;
  return raw;
}

DateTime _requiredTime(Object? raw, String field) {
  if (raw is! String) {
    throw FormatException('community club wire: $field is required');
  }
  return DateTime.parse(raw).toUtc();
}
