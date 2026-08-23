/// Following feed screen (E09-R14, brief §1 / §3 / §5 / §6).
///
/// The screen is a pure projection of [FeedState]: every interactive
/// widget calls into the controller, every visible label reads from the
/// controller's state. The screen owns no feed-domain state of its own
/// (the items live in the controller; the cache lives in [FeedCache];
/// A3 / A5 invariance).
///
/// **Layout (top → bottom):**
///
/// 1. A Material `RefreshIndicator` wraps the list and triggers
///    ``controller.refresh()`` on a pull — the items the user is
///    looking at stay visible while the new fetch is in flight (A7).
/// 2. The list of [FeedCard]s, one per post.
/// 3. A footer that renders the right thing per [FeedStatus]:
///    * `content` / `refreshing` — an explicit "Továbbiak betöltése"
///      button (no auto-scroll-pagination — A3).
///    * `paging` — a non‑blocking progress indicator.
///    * `end` — an end-of-feed marker plus the "Gyakorlás indítása"
///      CTA (A6).
///    * `offline` — a "Kapcsolat nélküli, helyi másolat" banner.
///    * `error` — an error card with a retry button (A1).
///    * `loading` (initial) — a centred spinner.
///
/// **Strings:** the screen labels are kept in this file as constants.
/// ARB entries for the feed are a future round's scope — the Kör 14
/// ``allowed_paths`` covers the screen file only; touching
/// ``lib/l10n/**`` would be a scope violation. The labels stay here so
/// a future i18n round picks them up without a screen rewrite.
///
/// **No autoplay / no auto-scroll-pagination (brief §5.1, A3):** the
/// screen has no `NotificationListener<ScrollNotification>`, no
/// `IntersectionObserver`, no scroll-position-based prefetch. The
/// pagination button is the only entry point to ``loadMore()``. A
/// regression that wires up an automatic trigger is caught by the
/// widget test (the §6.1 measure-matrix A3 cell asserts the absence of
/// any automatic-load callback in the rendered tree).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controllers/feed_controller.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../widgets/feed_card_registry.dart';

/// Following-feed labels. Kept here (not in the ARB) because the l10n
/// catalogue for the feed is a future round's scope.
abstract final class _FeedLabels {
  static const String title = 'Követési feed';
  static const String loadingInitial = 'Feed betöltése…';
  static const String emptyState = 'Még nincs poszt a feedben.';
  static const String emptyStateCta = 'Gyakorlás indítása';
  static const String loadMore = 'Továbbiak betöltése';
  static const String loadingMore = 'Betöltés…';
  static const String endOfFeed = 'Elérted a feed végét.';
  static const String offlineBanner = 'Offline · a helyi másolat jelenik meg.';
  static const String errorTitle = 'A feed nem tölthető be.';
  static const String retry = 'Újrapróbálkozás';
  static const String refresh = 'Frissítés';
}

/// The following-feed route.
class FollowingFeedScreen extends ConsumerStatefulWidget {
  const FollowingFeedScreen({super.key});

  @override
  ConsumerState<FollowingFeedScreen> createState() =>
      _FollowingFeedScreenState();
}

class _FollowingFeedScreenState extends ConsumerState<FollowingFeedScreen> {
  @override
  void initState() {
    super.initState();
    // Kick the initial load AFTER the first frame so the controller's
    // ``state.value`` is ready by the time the spinner fades out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The guard inside ``load()`` rejects re-entry, so a hot-restart
      // that lands here twice does not fire two fetches.
      ref.read(feedControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(feedControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(_FeedLabels.title),
        actions: <Widget>[
          IconButton(
            tooltip: _FeedLabels.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _canRefresh(state.status)
                ? () => ref.read(feedControllerProvider.notifier).refresh()
                : null,
          ),
        ],
      ),
      body: _Body(
        state: state,
        onLoadMore: () => ref.read(feedControllerProvider.notifier).loadMore(),
        onRetry: () => ref.read(feedControllerProvider.notifier).retry(),
        onRefresh: () => ref.read(feedControllerProvider.notifier).refresh(),
      ),
    );
  }

  bool _canRefresh(FeedStatus status) =>
      status != FeedStatus.loading &&
      status != FeedStatus.refreshing &&
      status != FeedStatus.paging;
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.onLoadMore,
    required this.onRetry,
    required this.onRefresh,
  });

  final FeedState state;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case FeedStatus.initial:
        return const _LoadingInitial();
      case FeedStatus.loading:
        // The cache may already have items — render them under a
        // non-blocking indicator rather than wiping the screen.
        if (state.items.isNotEmpty) {
          return _Content(
            state: state,
            onLoadMore: onLoadMore,
            onRetry: onRetry,
            onRefresh: onRefresh,
          );
        }
        return const _LoadingInitial();
      case FeedStatus.content:
      case FeedStatus.refreshing:
      case FeedStatus.paging:
        return _Content(
          state: state,
          onLoadMore: onLoadMore,
          onRetry: onRetry,
          onRefresh: onRefresh,
        );
      case FeedStatus.offline:
        return _Content(
          state: state,
          onLoadMore: onLoadMore,
          onRetry: onRetry,
          onRefresh: onRefresh,
          leadingBanner: const _OfflineBanner(),
        );
      case FeedStatus.error:
        return _ErrorCard(onRetry: onRetry);
      case FeedStatus.end:
        return _Content(
          state: state,
          onLoadMore: onLoadMore,
          onRetry: onRetry,
          onRefresh: onRefresh,
          endState: const _EndOfFeed(),
        );
    }
  }
}

class _LoadingInitial extends StatelessWidget {
  const _LoadingInitial();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(_FeedLabels.loadingInitial),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
            const SizedBox(height: 16),
            Text(
              _FeedLabels.errorTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text(_FeedLabels.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off, size: 16, color: theme.iconTheme.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _FeedLabels.offlineBanner,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EndOfFeed extends StatelessWidget {
  const _EndOfFeed();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.check_circle_outline, color: theme.iconTheme.color),
              const SizedBox(width: 8),
              Text(
                _FeedLabels.endOfFeed,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text(_FeedLabels.emptyStateCta),
            onPressed: () {
              // The CTA's nav is a future round's job — for now it
              // surfaces a non-blocking message so the user sees the
              // affordance is wired.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'A gyakorlás indítása a jövőbeli körökben érhető el.',
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Content extends StatefulWidget {
  const _Content({
    required this.state,
    required this.onLoadMore,
    required this.onRetry,
    required this.onRefresh,
    this.leadingBanner,
    this.endState,
  });

  final FeedState state;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final Widget? leadingBanner;
  final Widget? endState;

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  final ScrollController _scrollController = ScrollController();
  double? _scrollAtRefreshStart;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_rememberScroll);
  }

  /// Track the most recent scroll position so a refresh can restore
  /// it after the new content is laid out (A7).
  void _rememberScroll() {
    _scrollAtRefreshStart = _scrollController.position.pixels;
  }

  @override
  void didUpdateWidget(covariant _Content oldWidget) {
    super.didUpdateWidget(oldWidget);
    // After the list rebuilds post-refresh, re-anchor the scroll to
    // the position we remember from the pre-refresh frame. The exact
    // pixel may shift slightly because the rebuilt list re-lays-out,
    // but the row stays in view (A7 — scroll position preserved).
    final rememberedScroll = _scrollAtRefreshStart;
    if (rememberedScroll != null &&
        widget.state.status == FeedStatus.content &&
        oldWidget.state.status == FeedStatus.refreshing) {
      _scrollAtRefreshStart = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final clamped = rememberedScroll.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(clamped);
      });
    }
  }

  // PROBE — REMOVED. The real-violation probe (§6.1) lived here
  // temporarily and was reverted; the A3 widget test is the durable
  // guarantee that no scroll-driven auto-paging ever returns.

  @override
  void dispose() {
    _scrollController
      ..removeListener(_rememberScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.state.items;
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: Column(
        children: <Widget>[
          if (widget.leadingBanner != null) widget.leadingBanner!,
          Expanded(
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const <Widget>[
                      SizedBox(height: 80),
                      _EmptyState(),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length + 1,
                    itemBuilder: (context, index) {
                      if (index < items.length) {
                        return FeedCard(post: items[index]);
                      }
                      return _Footer(
                        state: widget.state,
                        onLoadMore: widget.onLoadMore,
                        onRetry: widget.onRetry,
                        endState: widget.endState,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        children: <Widget>[
          Text(_FeedLabels.emptyState, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text(_FeedLabels.emptyStateCta),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'A gyakorlás indítása a jövőbeli körökben érhető el.',
                  ),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.state,
    required this.onLoadMore,
    required this.onRetry,
    this.endState,
  });

  final FeedState state;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;
  final Widget? endState;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case FeedStatus.end:
        return endState ?? const _EndOfFeed();
      case FeedStatus.paging:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Column(
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 8),
                Text(_FeedLabels.loadingMore),
              ],
            ),
          ),
        );
      case FeedStatus.refreshing:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Column(
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 8),
                Text(_FeedLabels.refresh),
              ],
            ),
          ),
        );
      default:
        // Content / offline: the explicit "Továbbiak betöltése"
        // button. NO scroll-listener triggers this — A3.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: FilledButton.icon(
              icon: const Icon(Icons.expand_more),
              label: const Text(_FeedLabels.loadMore),
              onPressed: _canLoadMore(state.cursor) ? onLoadMore : null,
            ),
          ),
        );
    }
  }

  bool _canLoadMore(CursorPage? cursor) {
    if (cursor == null) return false;
    return cursor.isInitial || cursor.cursor != null;
  }
}
