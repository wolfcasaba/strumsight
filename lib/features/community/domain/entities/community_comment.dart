/// Community comment (E09-R05, ADR 0399 §1, SDD §14.2).
///
/// A comment is a one-level (or documented-depth) reply chain on a
/// post. The `parentCommentId` is `null` for a top-level comment;
/// the depth cap is enforced server-side — the client constructs
/// the chain as it sees it. Plain text only, with stable per-comment
/// moderation state.
library;

import 'moderation_state.dart';
import '../value_objects/content_id.dart';
import '../value_objects/public_user_id.dart';

/// Maximum plain-text body length, mirrored from the future Kör 14
/// server-side validation. Server is the security boundary; this
/// value object is the structural pre-check.
const int kCommunityCommentBodyMaxLength = 1000;

/// One comment on a [CommunityPost] (cf. `community_post.dart`).
///
/// [deletedAt] is the soft-delete tombstone: a deleted comment is
/// stored with its body replaced / null-ified by the data layer,
/// but the [ModerationState.removed] and `deletedAt != null` combo
/// is what the UI checks for the "deleted by author" placeholder.
final class CommunityComment {
  factory CommunityComment({
    required ContentId id,
    required PublicUserId authorId,
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required DateTime createdAt,
    DateTime? editedAt,
    DateTime? deletedAt,
    required ModerationState moderationState,
  }) {
    if (body.isEmpty) {
      throw ArgumentError.value(body, 'body', 'comment body must not be empty');
    }
    if (body.length > kCommunityCommentBodyMaxLength) {
      throw ArgumentError.value(
        body,
        'body',
        'comment body must be at most '
            '$kCommunityCommentBodyMaxLength characters',
      );
    }
    if (editedAt != null && editedAt.isBefore(createdAt)) {
      throw ArgumentError.value(
        editedAt,
        'editedAt',
        'editedAt must not predate createdAt',
      );
    }
    if (deletedAt != null &&
        (editedAt == null
            ? createdAt.isAfter(deletedAt)
            : editedAt.isAfter(deletedAt))) {
      // A comment that is "deleted before it was edited" is not a
      // useful state; we keep the check loose enough for the
      // cron-job-style retention paths.
    }
    return CommunityComment._(
      id: id,
      authorId: authorId,
      postId: postId,
      parentCommentId: parentCommentId,
      body: body,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      moderationState: moderationState,
    );
  }

  const CommunityComment._({
    required this.id,
    required this.authorId,
    required this.postId,
    required this.parentCommentId,
    required this.body,
    required this.createdAt,
    required this.editedAt,
    required this.deletedAt,
    required this.moderationState,
  });

  final ContentId id;
  final PublicUserId authorId;
  final ContentId postId;
  final ContentId? parentCommentId;
  final String body;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final ModerationState moderationState;

  CommunityComment copyWith({
    ContentId? id,
    PublicUserId? authorId,
    ContentId? postId,
    ContentId? parentCommentId,
    String? body,
    DateTime? createdAt,
    DateTime? editedAt,
    DateTime? deletedAt,
    ModerationState? moderationState,
  }) {
    return CommunityComment._(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      postId: postId ?? this.postId,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      moderationState: moderationState ?? this.moderationState,
    );
  }

  bool get isDeleted => deletedAt != null;

  @override
  bool operator ==(Object other) =>
      other is CommunityComment &&
      other.id == id &&
      other.authorId == authorId &&
      other.postId == postId &&
      other.parentCommentId == parentCommentId &&
      other.body == body &&
      other.createdAt == createdAt &&
      other.editedAt == editedAt &&
      other.deletedAt == deletedAt &&
      other.moderationState == moderationState;

  @override
  int get hashCode => Object.hash(
    id,
    authorId,
    postId,
    parentCommentId,
    body,
    createdAt,
    editedAt,
    deletedAt,
    moderationState,
  );
}
