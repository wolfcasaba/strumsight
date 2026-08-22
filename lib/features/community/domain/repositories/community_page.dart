/// Generic paged-response envelope used by all Kör 6+ repository
/// read methods (E09-R05, ADR 0399 §1, SDD §13.4).
///
/// The page bundles the items returned by the server with the opaque
/// follow-up cursor; the cursor itself lives in [CursorPage]
/// (`value_objects/cursor_page.dart`) and is a 1:1 mirror of the API's
/// `nextCursor` field — including the empty / halted-after-request
/// distinction. The repository hands the page to the UI; the UI
/// re-reads it via [cursor] and asks the repository for the next.
library;

import '../value_objects/cursor_page.dart';

/// Result of a single list-fetch repository call.
///
/// [items] is the slice the server returned. [cursor] is the opaque
/// continuation handle:
///
/// * the result of a NEVER-PAGED fetch returns [CursorPage.initial];
/// * the result of a fetch that returned a non-null `nextCursor`
///   returns [CursorPage.continued];
/// * the result of a fetch that returned null (end-of-feed OR halted)
///   returns [CursorPage.haltedAfterRequest].
final class CommunityPage<T> {
  const CommunityPage({required this.items, required this.cursor});

  /// The list slice the repository returned for this fetch.
  final List<T> items;

  /// The opaque follow-up cursor (see [CursorPage] for the
  /// initial-vs-halted vs continued semantics).
  final CursorPage cursor;

  bool get isHaltedAfterRequest => !cursor.isInitial && cursor.cursor == null;

  @override
  bool operator ==(Object other) =>
      other is CommunityPage<T> &&
      other.cursor == cursor &&
      _sameItems(other.items, items);

  @override
  int get hashCode => Object.hash(cursor, Object.hashAll(items));
}

bool _sameItems<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
