/// One row of the viewer's private "saved by me" list (2026-09-06, javító
/// sáv R5 — `docs/ui/apk-functionality-audit-2026-09-06.md` §1.3).
///
/// The shape mirrors the server's `BookmarkOut` one-for-one
/// (`backend/app/community/routers/bookmarks.py`): the internal row id is
/// the cursor key, the post's public id is the deep-link key, and
/// `isTombstone` is the §A3 surface — a `true` row's post is soft-deleted
/// or moderation-removed, the bookmark itself is preserved until the user
/// removes it.
library;

import 'package:meta/meta.dart';

import '../value_objects/content_id.dart';

@immutable
final class CommunityBookmark {
  const CommunityBookmark({
    required this.id,
    required this.postId,
    required this.createdAt,
    required this.isTombstone,
  });

  /// The internal row id (the cursor key on the server side).
  final int id;
  final ContentId postId;
  final DateTime createdAt;

  /// `true` when the joined post is soft-deleted or moderation-removed.
  final bool isTombstone;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CommunityBookmark &&
          other.id == id &&
          other.postId == postId &&
          other.createdAt == createdAt &&
          other.isTombstone == isTombstone);

  @override
  int get hashCode => Object.hash(id, postId, createdAt, isTombstone);
}
