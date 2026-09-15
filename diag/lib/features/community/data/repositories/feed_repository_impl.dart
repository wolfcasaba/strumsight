/// Dio-backed implementation of [CommunityFeedRepository].
///
/// Wired against the backend ``feed.py`` router (E09-R13, ADR 0406):
///
/// * ``followingFeed`` → ``GET /community/feed?page_size=…&cursor=…``
///   returning ``{"items": [FeedPostItem…], "next_cursor": …}``.
///   ``next_cursor`` is ``null`` on the last page; the page is mapped
///   to ``CursorPage.haltedAfterRequest`` then (the
///   [CommunityPage] contract) so the feed controller flips to its
///   explicit ``end`` state (A6) instead of offering a load-more
///   button that would refetch the first page.
/// * ``profilePosts`` / ``clubPinned`` — no backend route exists
///   (``grep -rn "posts" backend/app/community/routers/profile.py`` →
///   empty; no clubs router). Both throw the typed
///   ``ConfigurationFailure`` from [communityEndpointUnavailable] —
///   never ``UnimplementedError`` / ``UnsupportedError`` — so a
///   caller that reaches them sees a failure state, not a crash.
///
/// The repository rides the **shared** ``accountApiClientProvider``
/// (JWT + base-URL wiring in one place) exactly like
/// ``profile_repository_impl.dart``. The account-disabled build gets
/// [DisabledCommunityFeedRepository], whose every call throws
/// ``ConfigurationFailure`` — the feed controller catches
/// ``AppFailure`` and renders the error / offline state.
///
/// The ``communityFeedRepositoryProvider`` itself lives in
/// ``feed_controller.dart`` (it throws until overridden); the
/// production override in ``lib/app/bootstrap/
/// community_production_overrides.dart`` binds it through
/// [createCommunityFeedRepository].
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
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';
import '../dto/post_dto.dart';
import 'community_repository_support.dart';

/// The shared account client, read lazily so the account-disabled
/// build never constructs a Dio instance (the
/// ``communityApiClientProvider`` precedent).
final communityFeedApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// Pick the implementation for the given client: the HTTP one when
/// the account layer is on, the disabled stand-in otherwise. The
/// production override and the tests share this single decision.
CommunityFeedRepository createCommunityFeedRepository(ApiClient? client) {
  if (client == null) return const DisabledCommunityFeedRepository();
  return HttpCommunityFeedRepository(client);
}

/// Disabled-mode fallback: every call throws ``ConfigurationFailure``.
/// Mirrors ``DisabledCommunityProfileRepository`` so the controller
/// code path is uniform across repository flavours.
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

/// Live HTTP-backed feed repository.
class HttpCommunityFeedRepository implements CommunityFeedRepository {
  HttpCommunityFeedRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommunityPage<CommunityPost>> followingFeed({
    required Object cursor,
    required int limit,
  }) async {
    // The query string is inlined because ``ApiClient.getJson`` takes
    // no query-parameter map (the Kör 9 search precedent, ADR 0401
    // §1). ``page_size`` is the backend's parameter name (``feed.py``
    // — NOT ``limit``); the router clamps it to its own maximum, so
    // an oversized request degrades to a full page, never a 422.
    final params = <String>['page_size=$limit'];
    final cursorValue = communityCursorQueryValue(cursor);
    if (cursorValue != null) {
      params.add('cursor=${Uri.encodeQueryComponent(cursorValue)}');
    }
    final path = '/community/feed?${params.join('&')}';
    final result = await _client.getJson<CommunityPage<CommunityPost>>(
      path,
      decode: decodeFeedPage,
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
  }) async => throw communityEndpointUnavailable(
    'GET /community/profiles/{id}/posts',
  );

  @override
  Future<CommunityPage<CommunityPost>> clubPinned({
    required ContentId clubId,
    required Object cursor,
    required int limit,
  }) async => throw communityEndpointUnavailable(
    'GET /community/clubs/{id}/pinned',
  );

  /// Decode the ``FeedPage`` envelope (``{"items": […],
  /// "next_cursor": …}``) into the domain page.
  ///
  /// Cursor type-state: a non-null ``next_cursor`` becomes
  /// ``CursorPage.continued``; ``null`` becomes
  /// ``CursorPage.haltedAfterRequest`` regardless of whether the
  /// page carried items — the server says "no further page" and the
  /// controller's end-of-feed cell (A6) reads exactly that bit.
  ///
  /// Public (not ``_``-prefixed) so the DTO round-trip is testable
  /// without a transport.
  static CommunityPage<CommunityPost> decodeFeedPage(
    Map<String, Object?> json,
  ) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('community feed wire: items must be a list');
    }
    final items = <CommunityPost>[];
    for (final entry in rawItems) {
      if (entry is! Map) {
        throw const FormatException(
          'community feed wire: every item must be an object',
        );
      }
      final object = <String, Object?>{
        for (final e in entry.entries)
          if (e.key is String) e.key as String: e.value,
      };
      items.add(CommunityPostDto.fromJson(object).toDomain());
    }
    final nextCursor = json['next_cursor'];
    final cursorPage = nextCursor is String && nextCursor.isNotEmpty
        ? CursorPage.continued(nextCursor)
        : const CursorPage.haltedAfterRequest();
    return CommunityPage<CommunityPost>(
      items: List<CommunityPost>.unmodifiable(items),
      cursor: cursorPage,
    );
  }
}
