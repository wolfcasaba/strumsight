/// Repository contract for Community post writes + engagement
/// (E09-R05, ADR 0399 §1, SDD §14, §21.4-§21.5).
///
/// All create / update / delete mutations take an `idempotencyKey`;
/// Kör 11 enforces it server-side as the §19.2 receipt key.
library;

import '../entities/community_comment.dart';
import '../entities/community_post.dart';
import '../policies/community_audience.dart';
import '../value_objects/content_id.dart';
import 'community_page.dart';

abstract interface class CommunityPostRepository {
  /// Create a post. [audience] is the per-post audience (decoupled
  /// from the profile's visibility — Kör 4 audience values). Body
  /// length validation lives in [CommunityPost] itself.
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  });

  /// Fetch a single post. Returns `null` when the post is not
  /// visible to the viewer per the §5.2 access policy.
  Future<CommunityPost?> fetchPost({required ContentId postId});

  /// Edit the body and/or audience of [postId]. Server enforces the
  /// §11.5 edit-immutability rule (verified receipt IDs do not move
  /// between posts).
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  });

  /// Soft-delete a post (SDD §11.5). The post row remains as a
  /// tombstone until the retention policy hard-deletes it.
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  });

  /// Set the viewer's reaction on [postId]. Removing an existing
  /// reaction is the same call with `kind: null` — Kör 13 will
  /// validate that the reaction itself is in the supported allowlist
  /// (already enforced by [kind] being a [ReactionKind] enum).
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  });

  /// Toggle the viewer's bookmark on [postId]. Bookmarks are
  /// privately counted; this call sets/clears the single (post,
  /// viewer) row.
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  });

  /// Paged comments on [postId]. Top-level comments first; replies
  /// are flattened by the server within the documented depth limit.
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  });

  /// Create a comment on [postId]. [parentCommentId] is `null` for
  /// a top-level comment and a reply target otherwise.
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  });

  /// Edit a comment. Server enforces the edit-window; the client
  /// surfaces 409 if the window has elapsed.
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  });

  /// Soft-delete a comment.
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  });
}
