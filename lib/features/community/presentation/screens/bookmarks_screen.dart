/// Bookmarks screen (E09-R17, ADR 0408, brief §1 / §3 / §5).
///
/// The private "saved by me" list — a Material 3 page that
/// hosts the caller's bookmarks with cursor pagination and
/// tombstone handling. The screen is a pure projection of
/// [BookmarksController] — every state transition comes from
/// the controller's state stream; the screen owns no list
/// state.
///
/// **Tombstone state (A3).** A soft-deleted or moderation-
/// removed post's bookmark appears in the list as a
/// non-interactive placeholder card. The bookmark row is
/// PRESERVED (the user explicitly asked to save it) — the
/// placeholder just tells the user "the content is no longer
/// available". A null dereference is impossible: the
/// controller emits a discriminated ``is_tombstone`` field
/// the screen reads to switch into the placeholder render.
///
/// **Tombstone row is removable.** The user can still remove
/// the bookmark (the §A3 round-trip — the row stays, the user
/// can clean it up). The card exposes a "Remove" action that
/// calls the controller's remove path; the row disappears
/// from the list immediately (optimistic local update, same
/// pattern as the comment controller's delete).
///
/// **No autoplay / no auto-scroll-pagination.** Like the
/// following feed, the pagination button is the only entry
/// point to ``loadMore()`` (the Kör 14 invariant).
///
/// **Localization note (l10n).** This round ships the screen
/// with hardcoded English labels — the ARB file is not on
/// this round's ``allowed_paths``. A follow-up round (Kör 18
/// — community surface l10n) will lift the labels into
/// ``lib/l10n/app_en.arb`` / ``app_hu.arb`` (the F1 lesson the
/// Kör 14 brief called out). The label constants live at the
/// top of the screen file so the future ARB migration is a
/// one-pass search-and-replace.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../widgets/community_theme_scope.dart';

// ---------------------------------------------------------------------------
// L10n placeholders — to be lifted into app_en.arb / app_hu.arb in a
// future round. The keys are named to match the future ARB
// identifiers.
// ---------------------------------------------------------------------------

const String _l10nBookmarksTitle = 'Bookmarks';
const String _l10nBookmarksEmpty = 'No saved posts yet.';
const String _l10nBookmarkTombstoneBody =
    'This post is no longer available. The bookmark stays in your list '
    'until you remove it.';
const String _l10nBookmarkRemoveAction = 'Remove';
const String _l10nBookmarkLoadMore = 'Load more';
const String _l10nBookmarksErrorTitle = "The bookmarks couldn't load.";

// ---------------------------------------------------------------------------
// Domain shapes — local-only, the screen does NOT import the
// backend router (the wire contract is the controller's job).
// ---------------------------------------------------------------------------

/// One row in the caller's bookmark list. The ``is_tombstone``
/// flag is the §A3 surface the screen reads to switch into the
/// placeholder render — the post side is gone, the bookmark
/// stays.
@immutable
class BookmarkRow {
  const BookmarkRow({
    required this.id,
    required this.postId,
    required this.createdAt,
    required this.isTombstone,
  });

  /// The internal row id (the cursor key).
  final int id;
  final ContentId postId;
  final DateTime createdAt;

  /// ``true`` when the joined post is soft-deleted or
  /// moderation-removed. The screen renders the placeholder
  /// card; the bookmark row stays.
  final bool isTombstone;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookmarkRow &&
          other.id == id &&
          other.postId == postId &&
          other.createdAt == createdAt &&
          other.isTombstone == isTombstone);

  @override
  int get hashCode => Object.hash(id, postId, createdAt, isTombstone);
}

// ---------------------------------------------------------------------------
// State — the controller's snapshot.
// ---------------------------------------------------------------------------

/// The single Bookmarks-screen state (loading / loaded / error).
///
/// Mirrors the Kör 14 feed / Kör 16 comment controllers — an
/// ``AsyncValue`` carrying the page items, the next-cursor key,
/// and the load-more / pending flags. The screen reactively
/// rebuilds on every state transition.
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
}

// ---------------------------------------------------------------------------
// Controller interface — the screen does NOT couple to a
// concrete repository. The test injects a fake controller; the
// production wire is the responsibility of a future round that
// owns the full Community / backend integration surface.
// ---------------------------------------------------------------------------

/// The contract the screen expects from the controller. The
/// production implementation reads from
/// ``CommunityPostRepository``; the test wires an in-memory
/// fake. The screen is reactive — it watches ``bookmarksProvider``
/// and rebuilds on every state transition.
abstract class BookmarksController {
  BookmarksState get state;
  Stream<BookmarksState> get stream;

  /// Initial load. Resets the list to the first page.
  Future<void> load();

  /// Load the next page (cursor-paginated, D4 keyset).
  Future<void> loadMore();

  /// Remove the bookmark with the given row id. Idempotent: a
  /// second call is a no-op (the A1 invariant the Kör 16
  /// comment controller respects).
  Future<void> remove({required int bookmarkId});
}

/// The reactive provider the screen watches. The default
/// factory returns an in-memory fake — the test overrides the
/// provider via Riverpod's ``overrideWith`` (the same seam the
/// Kör 14 / Kör 16 tests use).
final bookmarksProvider = StreamProvider<BookmarksState>(
  (ref) => const Stream<BookmarksState>.empty(),
);

/// The controller factory — production wires the real
/// repository here; tests inject a fake.
final bookmarksControllerProvider = Provider<BookmarksController>(
  (ref) => _NoopBookmarksController(),
);

class _NoopBookmarksController implements BookmarksController {
  @override
  BookmarksState get state => const BookmarksState.initial();
  @override
  Stream<BookmarksState> get stream => const Stream<BookmarksState>.empty();
  @override
  Future<void> load() async {}
  @override
  Future<void> loadMore() async {}
  @override
  Future<void> remove({required int bookmarkId}) async {}
}

// ---------------------------------------------------------------------------
// The screen widget.
// ---------------------------------------------------------------------------

/// The bookmarks route. A Material 3 ``Scaffold`` whose body is
/// a reactive projection of [BookmarksState] — the screen
/// owns no list state (the controller is the source of truth).
class BookmarksScreen extends ConsumerStatefulWidget {
  const BookmarksScreen({super.key});

  @override
  ConsumerState<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends ConsumerState<BookmarksScreen> {
  @override
  void initState() {
    super.initState();
    // Kick the initial load AFTER the first frame so the
    // controller's state stream is subscribed before the call
    // lands.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bookmarksControllerProvider).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    // The screen reads the controller's state via the
    // ``bookmarksProvider`` — the controller pushes into the
    // stream, the screen rebuilds. A failure renders the
    // error card; the user retries via the explicit button.
    final asyncState = ref.watch(bookmarksProvider);
    return CommunityThemeScope(
      child: Scaffold(
        appBar: AppBar(title: const Text(_l10nBookmarksTitle)),
        body: SafeArea(
          child: asyncState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (failure, _) => _ErrorView(
              failure: failure,
              onRetry: () => ref.read(bookmarksControllerProvider).load(),
            ),
            data: _renderBody,
          ),
        ),
      ),
    );
  }

  Widget _renderBody(BookmarksState state) {
    if (state.rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(_l10nBookmarksEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      itemCount: state.rows.length + 1,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == state.rows.length) {
          return _LoadMoreFooter(
            state: state,
            onPressed: () => ref.read(bookmarksControllerProvider).loadMore(),
          );
        }
        final row = state.rows[index];
        if (row.isTombstone) {
          return _TombstoneCard(
            row: row,
            onRemove: () => ref
                .read(bookmarksControllerProvider)
                .remove(bookmarkId: row.id),
          );
        }
        return _BookmarkCard(
          row: row,
          onRemove: () =>
              ref.read(bookmarksControllerProvider).remove(bookmarkId: row.id),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Per-row widgets — kept file-private; the only public surface
// is the BookmarksScreen route.
// ---------------------------------------------------------------------------

class _BookmarkCard extends StatelessWidget {
  const _BookmarkCard({required this.row, required this.onRemove});
  final BookmarkRow row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text('Post ${row.postId.value}'),
      subtitle: Text('Saved at ${row.createdAt.toIso8601String()}'),
      trailing: IconButton(
        tooltip: _l10nBookmarkRemoveAction,
        icon: const Icon(Icons.bookmark_remove_outlined),
        onPressed: onRemove,
      ),
    );
  }
}

class _TombstoneCard extends StatelessWidget {
  const _TombstoneCard({required this.row, required this.onRemove});
  final BookmarkRow row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SsSurface(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              const Icon(Icons.archive_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Post ${row.postId.value}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _l10nBookmarkTombstoneBody,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _l10nBookmarkRemoveAction,
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.state, required this.onPressed});
  final BookmarksState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final hasMore =
        !state.nextCursor.isInitial && state.nextCursor.cursor != null;
    if (!hasMore) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: SsButton(
          variant: SsButtonVariant.secondary,
          onPressed: onPressed,
          label: _l10nBookmarkLoadMore,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.failure, required this.onRetry});
  final Object failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_l10nBookmarksErrorTitle, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(failure.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SsButton(
              variant: SsButtonVariant.secondary,
              onPressed: onRetry,
              label: 'Retry',
            ),
          ],
        ),
      ),
    );
  }
}
