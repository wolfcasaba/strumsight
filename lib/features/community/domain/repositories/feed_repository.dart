/// Repository contract for the Community feeds (E09-R05, ADR 0399 §1,
/// SDD §13, §21.4).
///
/// Three feed types share this contract: the following feed
/// (time-ordered), club feed and profile posts. Each of the three
/// is a separate method because the route paths and the cursor
/// namespaces differ on the server, and a single overloaded method
/// would hide that distinction.
library;

import '../entities/community_post.dart';
import '../value_objects/content_id.dart';
import '../value_objects/public_user_id.dart';
import 'community_page.dart';

abstract interface class CommunityFeedRepository {
  /// Following feed (SDD §13.2): posts from profiles the viewer
  /// follows (and optionally the viewer's own posts). Server applies
  /// the block / mute / audience filters before returning the page.
  Future<CommunityPage<CommunityPost>> followingFeed({
    required Object cursor,
    required int limit,
  });

  /// Posts on a single profile (SDD §21.4: `/profiles/{id}/posts`).
  /// The repository applies the audience / block filters that the
  /// profile's visibility implies — the §6 SUMMARY placeholder is
  /// the server's responsibility (ADR 0398 §4).
  Future<CommunityPage<CommunityPost>> profilePosts({
    required PublicUserId userId,
    required Object cursor,
    required int limit,
  });

  /// Posts pinned in a club feed (Kör 24). Until the club feature
  /// lands, [clubId] is reserved; the Kör 5 stub will throw
  /// `UnsupportedError`.
  Future<CommunityPage<CommunityPost>> clubPinned({
    required ContentId clubId,
    required Object cursor,
    required int limit,
  });
}
