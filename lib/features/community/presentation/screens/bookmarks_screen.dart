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
import 'package:go_router/go_router.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/foundation/app_failure.dart';
import '../../application/controllers/bookmarks_controller.dart';
import '../../data/repositories/post_repository_impl.dart';
import '../../domain/entities/community_bookmark.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/content_id.dart';
import '../widgets/community_theme_scope.dart';

export '../../application/controllers/bookmarks_controller.dart'
    show BookmarkRow, BookmarksController, BookmarksState;

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
// Controller wiring (javító sáv R5, 2026-09-06).
//
// The row / state / controller shapes moved to
// `application/controllers/bookmarks_controller.dart` together with the
// production controller; they are re-exported here so the golden fixtures
// keep their historical import. Until this round the default controller
// was a no-op and the state stream never emitted — the route sat on its
// loading spinner forever.
// ---------------------------------------------------------------------------

/// The reactive provider the screen watches — the production controller's
/// state stream. Tests override it with a scripted stream (the same seam
/// the Kör 14 / Kör 16 tests use).
final bookmarksProvider = StreamProvider<BookmarksState>(
  (ref) => ref.watch(bookmarksControllerProvider).stream,
);

/// The controller factory — production pages through
/// `GET /community/bookmarks` and removes through the existing bookmark
/// toggle (`DELETE /community/bookmarks/{post_id}`). Without an account
/// layer the read fails with `ConfigurationFailure`, which the screen
/// renders as its error card — the honest answer, not an empty list.
final bookmarksControllerProvider = Provider<BookmarksController>((ref) {
  final repository = ref.watch(communityPostRepositoryProvider);

  Future<CommunityPage<CommunityBookmark>> readPage({
    required Object cursor,
    required int limit,
  }) {
    if (repository is! HttpCommunityPostRepository) {
      throw const ConfigurationFailure();
    }
    return repository.listBookmarks(cursor: cursor, limit: limit);
  }

  Future<void> removeBookmark({
    required ContentId postId,
    required String idempotencyKey,
  }) {
    return repository.setBookmark(
      postId: postId,
      bookmarked: false,
      idempotencyKey: idempotencyKey,
    );
  }

  final controller = RepositoryBookmarksController(
    readPage: readPage,
    removeBookmark: removeBookmark,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

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
      key: Key('bookmark-row-${row.postId.value}'),
      title: Text('Post ${row.postId.value}'),
      subtitle: Text('Saved at ${row.createdAt.toIso8601String()}'),
      // WP-C (2026-09-06) — a mentett tétel megnyitja a bejegyzés
      // beszélgetését. Külön poszt-részlet képernyő NINCS a fában; a
      // kommentek képernyő a bejegyzés kanonikus nézete.
      // A sírkő-sor (tombstone) szándékosan NEM navigál: a tartalom
      // már nincs meg, a sor csak eltávolítható.
      onTap: () => context.push(
        AppRoutes.communityComments.replaceFirst(':postId', row.postId.value),
      ),
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
