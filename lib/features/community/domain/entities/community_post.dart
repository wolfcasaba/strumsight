/// Community post (E09-R05, ADR 0399 §1, SDD §11.1).
///
/// The post is the single Community content surface other than
/// comments (separate entity) and club announcements (a kind-of-post
/// in Kör 24). The post owns the [CommunityAudience] (per-content,
/// per-post), the [ModerationState] (server-authoritative), and the
/// [CommunityShareArtifact] reference. Counts and the viewer's
/// relationship to this post (bookmark, my reaction) live next to it
/// so the UI can render a row without a second round-trip.
library;

import '../policies/community_audience.dart';
import 'community_reaction.dart';
import 'moderation_state.dart';
import '../value_objects/content_id.dart';
import '../value_objects/public_user_id.dart';

/// Minimum / maximum bound for the visible post body (SDD §11.4).
/// Validation here mirrors the future Kör 11 server check.
const int kCommunityPostBodyMinLength = 0;
const int kCommunityPostBodyMaxLength = 2000;

/// Frozen counter triple the Kör 11 read-path returns.
///
/// `reactionCount` is the **signed** server total; the future voter /
/// re-counter view-layer MUST clamp to >=0 before display.
final class CommunityPostCounts {
  factory CommunityPostCounts({
    required int reactionCount,
    required int commentCount,
    required int bookmarkCount,
  }) {
    _requireNonNegative(reactionCount, 'reactionCount');
    _requireNonNegative(commentCount, 'commentCount');
    _requireNonNegative(bookmarkCount, 'bookmarkCount');
    return CommunityPostCounts._(
      reactionCount: reactionCount,
      commentCount: commentCount,
      bookmarkCount: bookmarkCount,
    );
  }

  const CommunityPostCounts._({
    required this.reactionCount,
    required this.commentCount,
    required this.bookmarkCount,
  });

  final int reactionCount;
  final int commentCount;
  final int bookmarkCount;

  CommunityPostCounts copyWith({
    int? reactionCount,
    int? commentCount,
    int? bookmarkCount,
  }) {
    return CommunityPostCounts._(
      reactionCount: reactionCount ?? this.reactionCount,
      commentCount: commentCount ?? this.commentCount,
      bookmarkCount: bookmarkCount ?? this.bookmarkCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityPostCounts &&
      other.reactionCount == reactionCount &&
      other.commentCount == commentCount &&
      other.bookmarkCount == bookmarkCount;

  @override
  int get hashCode => Object.hash(reactionCount, commentCount, bookmarkCount);
}

/// The viewer's personal state with respect to one post.
///
/// A `null` [myReaction] means "the viewer has not reacted (or the
/// viewer is the author and cannot see their own reaction)" — `null`
/// is meaningful and intentional. A `null` [bookmarkedAt] likewise
/// means "not bookmarked".
final class CommunityViewerPostState {
  const CommunityViewerPostState({
    required this.bookmarkedAt,
    required this.myReaction,
  });

  /// Empty / unknown viewer state (no bookmark, no reaction). Used
  /// when the data layer can't issue a per-viewer projection (own
  /// post, viewer is anonymous, etc.).
  const CommunityViewerPostState.empty()
    : bookmarkedAt = null,
      myReaction = null;

  final DateTime? bookmarkedAt;
  final ReactionKind? myReaction;

  @override
  bool operator ==(Object other) =>
      other is CommunityViewerPostState &&
      other.bookmarkedAt == bookmarkedAt &&
      other.myReaction == myReaction;

  @override
  int get hashCode => Object.hash(bookmarkedAt, myReaction);
}

/// Base class for the versioned share artifact a post references.
///
/// Kör 10 ("Share artifact szerződések", SDD §11.3) introduces the
/// concrete subclasses for each share source — at which point this
/// base class will gain a sealed definition. Until then the data
/// layer maps the JSONB artifact fields directly into an
/// implementation that satisfies this contract.
///
/// The class is intentionally `abstract` (not `sealed`): Kör 10 is
/// not in this round's `allowed_paths`, so the concrete variants
/// land in a later round's scope.
abstract base class CommunityShareArtifact {
  const CommunityShareArtifact({
    required this.schemaVersion,
    required this.sourceId,
    required this.createdAt,
  });

  /// The artifact's payload schema version. Bumped by Kör 10+ when
  /// the contract evolves. Kör 11/13 server-side validation uses this
  /// to reject unknown versions.
  final int schemaVersion;

  /// The originating event / row id (e.g. practice session id). The
  /// artifact MUST survive the deletion of the source row via
  /// retention policy (SDD §11.3).
  final String sourceId;

  /// When the artifact was created. Distinct from the post's
  /// `createdAt`; a share-from-history post may have an artifact
  /// older than the post itself.
  final DateTime createdAt;
}

/// Placeholder artifact shipped with Kör 5 so the post entity can
/// have a concrete value while Kör 10's real subtypes land. Its
/// `schemaVersion == 0` lets the data layer recognise it as
/// "unfilled" without an additional nullable flag.
base class UnfilledCommunityShareArtifact extends CommunityShareArtifact {
  const UnfilledCommunityShareArtifact()
    : super(schemaVersion: 0, sourceId: '', createdAt: _epoch);
}

final DateTime _epoch = DateTime.utc(1970, 1, 1);

/// A single Community post.
///
/// [body] is plain text — markdown subset, no script / HTML (SDD
/// §11.4). Kör 11 server-side validation rejects scripts; this
/// value object's validation is the structural pre-check.
final class CommunityPost {
  factory CommunityPost({
    required ContentId id,
    required PublicUserId authorId,
    required CommunityAudience audience,
    required String? body,
    required CommunityShareArtifact artifact,
    required DateTime createdAt,
    DateTime? editedAt,
    required ModerationState moderationState,
    required CommunityPostCounts counts,
    required CommunityViewerPostState viewerState,
  }) {
    if (body != null) {
      if (body.length < kCommunityPostBodyMinLength) {
        throw ArgumentError.value(
          body,
          'body',
          'post body must not be negative length',
        );
      }
      if (body.length > kCommunityPostBodyMaxLength) {
        throw ArgumentError.value(
          body,
          'body',
          'post body must be at most '
              '$kCommunityPostBodyMaxLength characters',
        );
      }
    }
    if (editedAt != null && editedAt.isBefore(createdAt)) {
      throw ArgumentError.value(
        editedAt,
        'editedAt',
        'editedAt must not predate createdAt',
      );
    }
    return CommunityPost._(
      id: id,
      authorId: authorId,
      audience: audience,
      body: body,
      artifact: artifact,
      createdAt: createdAt,
      editedAt: editedAt,
      moderationState: moderationState,
      counts: counts,
      viewerState: viewerState,
    );
  }

  const CommunityPost._({
    required this.id,
    required this.authorId,
    required this.audience,
    required this.body,
    required this.artifact,
    required this.createdAt,
    required this.editedAt,
    required this.moderationState,
    required this.counts,
    required this.viewerState,
  });

  final ContentId id;
  final PublicUserId authorId;
  final CommunityAudience audience;
  final String? body;
  final CommunityShareArtifact artifact;
  final DateTime createdAt;
  final DateTime? editedAt;
  final ModerationState moderationState;
  final CommunityPostCounts counts;
  final CommunityViewerPostState viewerState;

  CommunityPost copyWith({
    ContentId? id,
    PublicUserId? authorId,
    CommunityAudience? audience,
    String? body,
    CommunityShareArtifact? artifact,
    DateTime? createdAt,
    DateTime? editedAt,
    ModerationState? moderationState,
    CommunityPostCounts? counts,
    CommunityViewerPostState? viewerState,
  }) {
    return CommunityPost._(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      audience: audience ?? this.audience,
      body: body ?? this.body,
      artifact: artifact ?? this.artifact,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      moderationState: moderationState ?? this.moderationState,
      counts: counts ?? this.counts,
      viewerState: viewerState ?? this.viewerState,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommunityPost &&
      other.id == id &&
      other.authorId == authorId &&
      other.audience == audience &&
      other.body == body &&
      other.artifact == artifact &&
      other.createdAt == createdAt &&
      other.editedAt == editedAt &&
      other.moderationState == moderationState &&
      other.counts == counts &&
      other.viewerState == viewerState;

  @override
  int get hashCode => Object.hash(
    id,
    authorId,
    audience,
    body,
    artifact,
    createdAt,
    editedAt,
    moderationState,
    counts,
    viewerState,
  );
}

void _requireNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, '$name must not be negative');
  }
}
