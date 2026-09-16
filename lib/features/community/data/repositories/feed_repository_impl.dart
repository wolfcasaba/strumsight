/// Dio-backed implementation of [CommunityFeedRepository] (2026-09-05).
///
/// **Miért csak most.** A `CommunityFeedRepository` szerződés a Kör 5 óta
/// áll, implementáció nélkül — a feed-képernyők így nem tudtak valódi
/// adatot kérni. A szerver-oldali hiány három részből állt, és mind a
/// három ebben a sávban zárult: a feed nem küldött interakció-számlálókat,
/// a klub-feednek nem volt HTTP-felülete, és a kitűzött posztoknak sem.
///
/// **A három metódus NEM egyforma állapotú, és ezt a kód kimondja:**
///
/// * `followingFeed` — `GET /community/feed`. Kész.
/// * `clubPinned` — `GET /community/clubs/{id}/pinned`. Kész. A lista
///   egyoldalas (a kitűzhető posztok száma korlátos), ezért a válasz
///   `haltedAfterRequest` kurzort ad, nem `initial`-t.
/// * `profilePosts` — **NINCS végpontja.** Se route, se service: a
///   profil-posztok láthatósági szűrése (közönség + blokk + némítás)
///   sosem készült el. A metódus ezért `UnimplementedError`-t dob, és
///   NEM ad üres oldalt: az üres lista azt állítaná, hogy ennek a
///   felhasználónak nincs posztja — magabiztos hamis állítás, miközben
///   az igazság az, hogy nem tudjuk. A hiány a
///   `docs/contracts/client-backend-endpoints.json` `known_gap` sorában
///   is szerepel.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/network/api_client.dart';
import '../../../../features/auth/public.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/repositories/feed_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/public_user_id.dart';
import 'post_wire.dart';

/// Az account-réteg Dio kliense, lustán. A fiók nélküli build így sosem
/// építi fel — ugyanaz a minta, mint a `communitySocialApiClientProvider`.
final communityFeedApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// A bekötött feed-repository. A fiókréteg kikapcsolt állásán a
/// [DisabledCommunityFeedRepository] felel — a hívó kód mindkét ágon
/// ugyanaz.
final communityFeedRepositoryProvider = Provider<CommunityFeedRepository>((
  ref,
) {
  final client = ref.watch(communityFeedApiClientProvider);
  if (client == null) return const DisabledCommunityFeedRepository();
  return HttpCommunityFeedRepository(client);
});

/// Fiók nélküli mód: minden hívás `ConfigurationFailure`.
final class DisabledCommunityFeedRepository implements CommunityFeedRepository {
  const DisabledCommunityFeedRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityPage<CommunityPost>> followingFeed({
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPage<CommunityPost>> profilePosts({
    required PublicUserId userId,
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;

  @override
  Future<CommunityPage<CommunityPost>> clubPinned({
    required ContentId clubId,
    required Object cursor,
    required int limit,
  }) async => throw _disabled.error;
}

/// Élő, HTTP-alapú feed-repository.
final class HttpCommunityFeedRepository implements CommunityFeedRepository {
  const HttpCommunityFeedRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommunityPage<CommunityPost>> followingFeed({
    required Object cursor,
    required int limit,
  }) async {
    final result = await _client.getJson<CommunityPage<CommunityPost>>(
      '/community/feed',
      queryParameters: <String, Object?>{
        'page_size': limit,
        // A `null` kurzort az `ApiClient` kihagyja — a szerver
        // `extra="forbid"` sémája egy `cursor=null`-t ismeretlen
        // bemenetként utasítana el.
        'cursor': communityCursorQueryValue(cursor),
      },
      decode: decodeCommunityPostPage,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityPage<CommunityPost>> profilePosts({
    required PublicUserId userId,
    required Object cursor,
    required int limit,
  }) async {
    throw UnimplementedError(
      'A profil-posztok listájának nincs szerver-oldali végpontja '
      '(se route, se service): a láthatósági szűrés — közönség, blokk, '
      'némítás — sosem készült el. Üres oldalt szándékosan NEM adunk: az '
      'azt állítaná, hogy ennek a profilnak nincs posztja, holott az '
      'igazság az, hogy nem tudjuk.',
    );
  }

  @override
  Future<CommunityPage<CommunityPost>> clubPinned({
    required ContentId clubId,
    required Object cursor,
    required int limit,
  }) async {
    // A kitűzött posztok listája egyoldalas — a szerver nem ad
    // `next_cursor`-t, és a `limit`/`cursor` paraméterre sincs felülete.
    // A szerződés mindkettőt kéri; itt szándékosan NEM küldjük tovább
    // őket, mert egy elfogadott, de figyelmen kívül hagyott paraméter
    // ugyanaz a néma hibaosztály, ami a lapozást elrontotta.
    final result = await _client.getJson<CommunityPage<CommunityPost>>(
      '/community/clubs/${clubId.value}/pinned',
      decode: decodeCommunityPostPage,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }

  /// A klub posztfolyama — a `clubPinned`-től KÜLÖN metódus.
  ///
  /// A `CommunityFeedRepository` szerződésben nem szerepel (a Kör 5 még
  /// nem ismerte a klub-feedet), de a klub-részletek képernyőnek erre van
  /// szüksége, nem a kitűzöttek listájára. Külön névvel, hogy a kettőt ne
  /// lehessen összetéveszteni.
  Future<CommunityPage<CommunityPost>> clubFeed({
    required ContentId clubId,
    required Object cursor,
    required int limit,
  }) async {
    final result = await _client.getJson<CommunityPage<CommunityPost>>(
      '/community/clubs/${clubId.value}/feed',
      queryParameters: <String, Object?>{
        'page_size': limit,
        'cursor': communityCursorQueryValue(cursor),
      },
      decode: decodeCommunityPostPage,
    );
    return switch (result) {
      Success(:final value) => value,
      Failure(:final error) => throw error,
    };
  }
}
