/// The Bookmarks screen's controller (javító sáv R5, 2026-09-06 —
/// `docs/ui/apk-functionality-audit-2026-09-06.md` §1.3).
///
/// Until this round the shipped `BookmarksScreen` was a projection of a
/// no-op controller: `load()` did nothing, the state stream never emitted,
/// so the route sat on its loading spinner forever. The server-side list
/// (`GET /community/bookmarks`, E09-R17) and the remove path
/// (`DELETE /community/bookmarks/{post_id}`, already wired as
/// `CommunityPostRepository.setBookmark`) both existed; nothing composed
/// them into the screen's [BookmarksController] contract. This file is that
/// composition.
///
/// The controller is deliberately decoupled from the repository TYPE: it
/// takes the two calls it needs as functions, so the unit test drives it
/// with scripted pages and the production provider hands it the HTTP
/// repository's methods — the same seam the screen's golden tests use.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../../domain/entities/community_bookmark.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';

/// The screen-side row type. One and the same as the domain entity — the
/// alias keeps the screen and its golden fixtures on their historical
/// name.
typedef BookmarkRow = CommunityBookmark;

/// The single Bookmarks-screen state (loading / loaded / error).
///
/// Mirrors the Kör 14 feed / Kör 16 comment controllers — the page items,
/// the next-cursor key, and the load-more / pending flags. The screen
/// reactively rebuilds on every state transition.
@immutable
class BookmarksState {
  const BookmarksState({
    required this.rows,
    required this.nextCursor,
    required this.isLoadingMore,
    required this.isRemoving,
  });

  const BookmarksState.initial()
    : rows = const <BookmarkRow>[],
      nextCursor = const CursorPage.haltedAfterRequest(),
      isLoadingMore = false,
      isRemoving = false;

  final List<BookmarkRow> rows;
  final CursorPage nextCursor;
  final bool isLoadingMore;
  final bool isRemoving;

  BookmarksState copyWith({
    List<BookmarkRow>? rows,
    CursorPage? nextCursor,
    bool? isLoadingMore,
    bool? isRemoving,
  }) {
    return BookmarksState(
      rows: rows ?? this.rows,
      nextCursor: nextCursor ?? this.nextCursor,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRemoving: isRemoving ?? this.isRemoving,
    );
  }
}

/// The contract the screen expects from the controller. The screen is
/// reactive — it watches the state stream and rebuilds on every
/// transition; it owns no list state.
abstract class BookmarksController {
  BookmarksState get state;
  Stream<BookmarksState> get stream;

  /// Initial load. Resets the list to the first page.
  Future<void> load();

  /// Load the next page (cursor-paginated, D4 keyset).
  Future<void> loadMore();

  /// Remove the bookmark with the given row id. Idempotent: a second call
  /// is a no-op (the A1 invariant the Kör 16 comment controller respects).
  Future<void> remove({required int bookmarkId});
}

/// Reads one page of the viewer's bookmarks.
typedef BookmarkPageReader =
    Future<CommunityPage<CommunityBookmark>> Function({
      required Object cursor,
      required int limit,
    });

/// Clears the viewer's bookmark on [postId].
typedef BookmarkRemover =
    Future<void> Function({
      required ContentId postId,
      required String idempotencyKey,
    });

/// The production [BookmarksController]: pages through the server list and
/// removes rows through the existing bookmark toggle.
///
/// **Errors are said out loud, never swallowed.** A failed load is pushed
/// into the stream as an error event — the screen renders its retry card
/// from it. A failed remove restores the row and re-throws to the caller;
/// the optimistic removal never turns into a silently-lost row.
final class RepositoryBookmarksController implements BookmarksController {
  RepositoryBookmarksController({
    required BookmarkPageReader readPage,
    required BookmarkRemover removeBookmark,
    this.pageSize = defaultPageSize,
    String Function()? idempotencyKey,
  }) : _readPage = readPage, // ignore: prefer_initializing_formals
       _removeBookmark = removeBookmark, // ignore: prefer_initializing_formals
       _idempotencyKey = idempotencyKey ?? _defaultIdempotencyKey;

  /// The page size the screen requests — the server clamps it to its own
  /// maximum.
  static const int defaultPageSize = 25;

  final BookmarkPageReader _readPage;
  final BookmarkRemover _removeBookmark;
  final String Function() _idempotencyKey;
  final int pageSize;

  final StreamController<BookmarksState> _states =
      StreamController<BookmarksState>.broadcast();
  BookmarksState _state = const BookmarksState.initial();
  final Set<int> _removing = <int>{};

  @override
  BookmarksState get state => _state;

  @override
  Stream<BookmarksState> get stream => _states.stream;

  @override
  Future<void> load() async {
    final CommunityPage<CommunityBookmark> page;
    try {
      page = await _readPage(
        cursor: const CursorPage.initial(),
        limit: pageSize,
      );
    } on Object catch (error, stackTrace) {
      if (!_states.isClosed) _states.addError(error, stackTrace);
      return;
    }
    _emit(
      BookmarksState(
        rows: List<BookmarkRow>.unmodifiable(page.items),
        nextCursor: page.cursor,
        isLoadingMore: false,
        isRemoving: false,
      ),
    );
  }

  @override
  Future<void> loadMore() async {
    final cursor = _state.nextCursor;
    // No further page (or the first page never loaded): nothing to ask
    // for. A re-issued first page from here would duplicate the rows.
    if (cursor.isInitial || cursor.cursor == null) return;
    if (_state.isLoadingMore) return;
    _emit(_state.copyWith(isLoadingMore: true));
    final CommunityPage<CommunityBookmark> page;
    try {
      page = await _readPage(cursor: cursor, limit: pageSize);
    } on Object catch (error, stackTrace) {
      _emit(_state.copyWith(isLoadingMore: false));
      if (!_states.isClosed) _states.addError(error, stackTrace);
      return;
    }
    final seen = <int>{for (final row in _state.rows) row.id};
    _emit(
      _state.copyWith(
        rows: List<BookmarkRow>.unmodifiable(<BookmarkRow>[
          ..._state.rows,
          for (final row in page.items)
            if (!seen.contains(row.id)) row,
        ]),
        nextCursor: page.cursor,
        isLoadingMore: false,
      ),
    );
  }

  @override
  Future<void> remove({required int bookmarkId}) async {
    if (_removing.contains(bookmarkId)) return;
    final index = _state.rows.indexWhere((row) => row.id == bookmarkId);
    if (index < 0) return;
    final row = _state.rows[index];
    _removing.add(bookmarkId);
    final before = _state.rows;
    _emit(
      _state.copyWith(
        rows: List<BookmarkRow>.unmodifiable(<BookmarkRow>[
          for (final candidate in before)
            if (candidate.id != bookmarkId) candidate,
        ]),
        isRemoving: true,
      ),
    );
    try {
      await _removeBookmark(
        postId: row.postId,
        idempotencyKey: _idempotencyKey(),
      );
    } on Object {
      // Restore the row exactly where it was — an optimistic removal that
      // failed on the server must not read as "removed".
      _emit(_state.copyWith(rows: before, isRemoving: _removing.length > 1));
      _removing.remove(bookmarkId);
      rethrow;
    }
    _removing.remove(bookmarkId);
    _emit(_state.copyWith(isRemoving: _removing.isNotEmpty));
  }

  void dispose() {
    unawaited(_states.close());
  }

  void _emit(BookmarksState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  static String _defaultIdempotencyKey() =>
      'bookmark-remove-${DateTime.now().microsecondsSinceEpoch}';
}
