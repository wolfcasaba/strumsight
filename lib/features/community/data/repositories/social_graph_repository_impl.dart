/// Production [SocialGraphRepository] wiring (E09-R07 / E09-R08
/// contract; production wiring round 2026-09-15).
///
/// The HTTP implementation of the social graph already exists —
/// [HttpSocialGraphRepository] in ``relationship_repository_impl.dart``
/// covers all 13 methods and ``socialGraphRepositoryProvider`` resolves
/// it from ``accountApiClientProvider`` on its own
/// (``community_production_chain_test.dart`` pins that chain). This
/// file does NOT duplicate it. It adds the one thing the measured
/// wire has wrong:
///
/// **Dropped cursor + limit on the two paged follow reads.**
/// ``HttpSocialGraphRepository.followingPage`` / ``followersPage``
/// build a ``params`` map (``limit: 50`` + the cursor) and then call
/// ``getJson`` with the bare path — ``ApiClient.getJson`` takes no
/// query map, so the map is never sent. The backend
/// (``routers/social_graph.py::get_followers`` / ``get_following``)
/// reads ``?cursor=&limit=``; without them every "load more" on the
/// followers / following screens re-fetches page one with the
/// server's default limit. The block / mute lists in the same class
/// already inline the query string (``_buildPagePath``); the two
/// follow lists never got the same fix.
///
/// [HttpCommunitySocialGraphRepository] is a thin decorator: the two
/// follow-list reads are re-issued here WITH the query string (the
/// ``_buildPagePath`` shape, same ``public_ids`` envelope decoder),
/// every other method delegates to the wrapped
/// [HttpSocialGraphRepository] unchanged. The decorator cannot reach
/// the delegate's private ``_decodePage`` / ``_placeholderProfile``,
/// so the envelope decoder is restated here — the wire contract
/// (``{"public_ids": [...], "next_cursor": ...}``) is pinned by
/// ``relationship_repository_impl_test.dart`` and the repository
/// test next to this file.
///
/// The production override (``lib/app/bootstrap/
/// community_social_production_overrides.dart``) binds
/// ``socialGraphRepositoryProvider`` to [createCommunitySocialGraphRepository]
/// so the routed screens read the cursor-forwarding shape.
library;

import '../../../../core/foundation/app_result.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/repositories/social_graph_repository.dart';
import '../../domain/value_objects/community_handle.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';
import 'community_repository_support.dart';
import 'relationship_repository_impl.dart';

export 'relationship_repository_impl.dart'
    show
        DisabledSocialGraphRepository,
        HttpSocialGraphRepository,
        communitySocialApiClientProvider,
        socialGraphRepositoryProvider;

/// Page size of the two follow-list reads — the value the wrapped
/// implementation intended to send (``limit: 50``) and the block /
/// mute lists already send.
const int kCommunityFollowListPageSize = 50;

/// Pick the implementation for the given client: the cursor-forwarding
/// HTTP decorator when the account layer is on, the disabled stand-in
/// otherwise (the ``createCommunityPostRepository`` precedent).
SocialGraphRepository createCommunitySocialGraphRepository(ApiClient? client) {
  if (client == null) return const DisabledSocialGraphRepository();
  return HttpCommunitySocialGraphRepository(
    client,
    delegate: HttpSocialGraphRepository(client),
  );
}

/// Cursor-forwarding decorator over [HttpSocialGraphRepository].
class HttpCommunitySocialGraphRepository implements SocialGraphRepository {
  HttpCommunitySocialGraphRepository(this._client, {required this._delegate});

  final ApiClient _client;
  final SocialGraphRepository _delegate;

  /// ``GET /community/profiles/{id}/following?limit=50&cursor=…``
  @override
  Future<CommunityPage<CommunityProfile>> followingPage({
    required PublicUserId userId,
    required Object cursor,
  }) =>
      _fetchFollowList('/community/profiles/${userId.value}/following', cursor);

  /// ``GET /community/profiles/{id}/followers?limit=50&cursor=…``
  @override
  Future<CommunityPage<CommunityProfile>> followersPage({
    required PublicUserId userId,
    required Object cursor,
  }) =>
      _fetchFollowList('/community/profiles/${userId.value}/followers', cursor);

  @override
  Future<ContentId> follow({
    required PublicUserId target,
    required String idempotencyKey,
  }) => _delegate.follow(target: target, idempotencyKey: idempotencyKey);

  @override
  Future<void> unfollow({
    required PublicUserId target,
    required String idempotencyKey,
  }) => _delegate.unfollow(target: target, idempotencyKey: idempotencyKey);

  @override
  Future<void> removeFollower({
    required PublicUserId follower,
    required String idempotencyKey,
  }) => _delegate.removeFollower(
    follower: follower,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<void> acceptFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) => _delegate.acceptFollowRequest(
    requestId: requestId,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<void> declineFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) => _delegate.declineFollowRequest(
    requestId: requestId,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<void> block({
    required PublicUserId target,
    required String idempotencyKey,
  }) => _delegate.block(target: target, idempotencyKey: idempotencyKey);

  @override
  Future<void> unblock({
    required PublicUserId target,
    required String idempotencyKey,
  }) => _delegate.unblock(target: target, idempotencyKey: idempotencyKey);

  @override
  Future<void> mute({
    required PublicUserId target,
    required String idempotencyKey,
  }) => _delegate.mute(target: target, idempotencyKey: idempotencyKey);

  @override
  Future<void> unmute({
    required PublicUserId target,
    required String idempotencyKey,
  }) => _delegate.unmute(target: target, idempotencyKey: idempotencyKey);

  @override
  Future<CommunityPage<CommunityProfile>> blockedProfilesPage({
    required Object cursor,
  }) => _delegate.blockedProfilesPage(cursor: cursor);

  @override
  Future<CommunityPage<CommunityProfile>> mutedProfilesPage({
    required Object cursor,
  }) => _delegate.mutedProfilesPage(cursor: cursor);

  // ---- internal ----------------------------------------------------------

  Future<CommunityPage<CommunityProfile>> _fetchFollowList(
    String base,
    Object cursor,
  ) async {
    final cursorValue = communityCursorQueryValue(cursor);
    final querySegments = <String>[
      'limit=$kCommunityFollowListPageSize',
      if (cursorValue != null)
        'cursor=${Uri.encodeQueryComponent(cursorValue)}',
    ];
    final path = '$base?${querySegments.join('&')}';
    final result = await _client.getJson<dynamic>(
      path,
      decode: decodeFollowListPage,
    );
    return switch (result) {
      Success(:final value) => value as CommunityPage<CommunityProfile>,
      Failure(:final error) => throw error,
    };
  }

  /// Decode the Kör 7 ``{"public_ids": [...], "next_cursor": ...}``
  /// envelope into placeholder profile rows — the same contract
  /// ``HttpSocialGraphRepository._decodePage`` implements (the full
  /// profile arrives through the canonical ``fetchById`` follow-up).
  CommunityPage<CommunityProfile> decodeFollowListPage(
    Map<String, Object?> json,
  ) {
    final rawIds = json['public_ids'];
    if (rawIds is! List) {
      throw const FormatException(
        'community follow-list wire: public_ids must be a list',
      );
    }
    final publicIds = rawIds
        .whereType<String>()
        .map(PublicUserId.new)
        .toList(growable: false);
    final nextCursor = json['next_cursor'];
    final cursorPage = nextCursor == null
        ? (publicIds.isEmpty
              ? const CursorPage.haltedAfterRequest()
              : const CursorPage.initial())
        : CursorPage.continued(nextCursor as String);
    final items = publicIds
        .map(communityFollowListPlaceholderProfile)
        .toList(growable: false);
    return CommunityPage<CommunityProfile>(items: items, cursor: cursorPage);
  }
}

/// The placeholder row a ``public_ids``-only page materialises —
/// field-for-field the ``relationship_repository_impl.dart``
/// ``_placeholderProfile`` (a non-empty display name keeps the
/// ``CommunityProfile`` factory invariant; the real name arrives via
/// ``fetchById``).
CommunityProfile communityFollowListPlaceholderProfile(PublicUserId userId) {
  return CommunityProfile(
    userId: userId,
    handle: CommunityHandle('placeholder-x1'),
    displayName: 'placeholder',
    visibility: ProfileVisibility.followers,
    avatarUrl: null,
    bio: null,
    skillInterests: const <String>[],
    badges: const <String>[],
    relationship: CommunityRelationshipToViewer.notRelated,
    createdAt: DateTime.utc(2026),
  );
}
