/// Repository contract for the social graph (E09-R05, ADR 0399 §1,
/// SDD §10, §21.3, §21.5).
///
/// Follows, follow requests, blocks and mutes all live here so the
/// Kör 8 read-path policy can call a single repository per query.
/// Every mutation takes an `idempotencyKey` — the corresponding
/// backend endpoint (SDD §19.2) requires one and re-using a key MUST
/// be safe across retry (ADR 0398 §5).
library;

import '../entities/community_profile.dart';
import '../value_objects/content_id.dart';
import '../value_objects/public_user_id.dart';
import 'community_page.dart';

abstract interface class SocialGraphRepository {
  /// Paged following list for [userId].
  Future<CommunityPage<CommunityProfile>> followingPage({
    required PublicUserId userId,
    required Object cursor,
  });

  /// Paged follower list for [userId].
  Future<CommunityPage<CommunityProfile>> followersPage({
    required PublicUserId userId,
    required Object cursor,
  });

  /// Follow [target]. Public profile ⇒ immediate `following`;
  /// private profile ⇒ returns the pending follow request id, the
  /// follow becomes `following` after accept (Kör 7).
  Future<ContentId> follow({
    required PublicUserId target,
    required String idempotencyKey,
  });

  /// Unfollow [target].
  Future<void> unfollow({
    required PublicUserId target,
    required String idempotencyKey,
  });

  /// Remove a follower (profile owner removing an unwanted follower,
  /// SDD §10.3 — distinct from block).
  Future<void> removeFollower({
    required PublicUserId follower,
    required String idempotencyKey,
  });

  /// Accept an incoming follow request — used by the profile owner
  /// when their profile is `private`.
  Future<void> acceptFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  });

  /// Decline an incoming follow request.
  Future<void> declineFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  });

  /// Block [target]. All existing follow edges are removed as a
  /// transaction (SDD §10.5).
  Future<void> block({
    required PublicUserId target,
    required String idempotencyKey,
  });

  /// Unblock [target]. Does NOT recreate previously removed follow
  /// edges (SDD §10.5 invariant).
  Future<void> unblock({
    required PublicUserId target,
    required String idempotencyKey,
  });

  /// Mute [target] — view-only, does not mutate the social graph.
  Future<void> mute({
    required PublicUserId target,
    required String idempotencyKey,
  });

  /// Unmute [target].
  Future<void> unmute({
    required PublicUserId target,
    required String idempotencyKey,
  });
}
