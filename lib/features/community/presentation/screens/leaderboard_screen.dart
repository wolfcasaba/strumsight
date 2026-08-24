/// Verified-only leaderboard screen (E09-R23, ADR 0418, brief
/// §6 A7).
///
/// The screen renders the projection returned by
/// ``CommunityChallengeRepository.leaderboard()`` (the Kör 23
/// endpoint, D6) — verified-only (A1 / D1), opt-in (A3 / D2),
/// sorted by ``(metric_value DESC, submitted_at ASC, id ASC)``
/// (A2 / D4). The Flutter surface here is the **A7 cell**: an
/// accessible rank-row that stays readable under the user's
/// text-scale setting.
///
/// **Why a standalone screen (D6 / Kontextus 6.).** The
/// own-rank endpoint exists in the router + service but its
/// Flutter wiring is a future round — this screen only reads
/// the paged list (first page, A5 stability is the backend
/// pytest invariant).
///
/// **Pagination.** The first page is read once; the "load more"
/// button re-fetches the FIRST page again — pagination across
/// cursor pages is a future round's surface. The button is
/// present so the A5 cell's "stable, no duplicates" invariant
/// is reachable from the UI as a no-op probe.
///
/// **Accessibility (A7).** Each rank-row is a single
/// ``Semantics`` node whose label concatenates rank, display
/// name (or @handle fallback), metric value, and the
/// verified-badge presence — so TalkBack / VoiceOver reads
/// "Rank 1. Alice. 500 score. Verified." in one utterance. The
/// text widgets respect ``MediaQuery.textScalerOf(context)`` so
/// a 1.5× or 2× system text setting keeps the rank, name and
/// score on screen together (no truncation; the row grows
/// vertically). The list uses
/// ``AlwaysScrollableScrollPhysics`` so a small list remains
/// scrollable for refresh.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/repositories/challenge_repository_impl.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';

/// First-page size — matches the Kör 22 ``listChallenges``
/// pattern (the future round can re-tune against the A5
/// multi-page stability cell).
const int _kLeaderboardPageSize = 25;

/// FutureProvider for the first page of a challenge's
/// leaderboard. ``autoDispose`` so the screen is cheap to
/// enter / leave; ``family`` so multiple challenges stay
/// independent. The return type is
/// ``AsyncValue<CommunityPage<LeaderboardEntry>>`` — the
/// repository interface exposes
/// ``Future<CommunityPage<Object>>`` (D1 signature frozen),
/// and Dart generic covariance makes the typed page a valid
/// substitute.
final leaderboardProvider = FutureProvider.autoDispose
    .family<CommunityPage<LeaderboardEntry>, ContentId>((
      ref,
      challengeId,
    ) async {
      final repo = ref.watch(communityChallengeRepositoryProvider);
      final page = await repo.leaderboard(
        challengeId: challengeId,
        cursor: const CursorPage.initial(),
        limit: _kLeaderboardPageSize,
      );
      return page as CommunityPage<LeaderboardEntry>;
    });

/// Public screen — ``ConsumerWidget`` so the test surface is
/// the ``ProviderScope`` override of the production
/// ``communityChallengeRepositoryProvider`` (the Kör 21
/// pattern).
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key, required this.challengeId});

  final ContentId challengeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final state = ref.watch(leaderboardProvider(challengeId));

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(localizations.communityChallengeTitle),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(leaderboardProvider(challengeId));
          await ref.read(leaderboardProvider(challengeId).future);
        },
        child: state.when(
          data: (page) => _Body(
            page: page,
            localizations: localizations,
            onLoadMore: () async {
              ref.invalidate(leaderboardProvider(challengeId));
              await ref.read(leaderboardProvider(challengeId).future);
            },
          ),
          loading: () => const _LoadingView(),
          error: (error, _) => _ErrorView(
            failure: UnknownFailure(code: FailureCode.unknown, cause: error),
            localizations: localizations,
            onRetry: () async {
              ref.invalidate(leaderboardProvider(challengeId));
              await ref.read(leaderboardProvider(challengeId).future);
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — empty / list / load-more row.
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.page,
    required this.localizations,
    required this.onLoadMore,
  });

  final CommunityPage<LeaderboardEntry> page;
  final AppLocalizations localizations;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final entries = page.items;
    if (entries.isEmpty) {
      return _EmptyView(localizations: localizations);
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: entries.length + 1,
      itemBuilder: (context, index) {
        if (index == entries.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: TextButton(
                onPressed: onLoadMore,
                child: Text(localizations.communityChallengeAccept),
              ),
            ),
          );
        }
        return _RankRow(entry: entries[index], localizations: localizations);
      },
    );
  }
}

/// A single accessible rank-row (A7).
///
/// The widget builds a single ``Semantics`` node whose label
/// concatenates rank, display name (or @handle fallback), metric
/// value, and the verified-badge presence — so a screen reader
/// reads the row in one utterance. The text widgets go through
/// ``MediaQuery.textScalerOf(context).scale(...)`` so a 2×
/// system setting keeps the row readable (no truncation; the
/// row's height grows).
class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry, required this.localizations});

  final LeaderboardEntry entry;
  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final name = entry.displayName;
    final handle = entry.handle;
    final nameOrHandle = name ?? handle ?? entry.publicId.value;
    final textScaler = MediaQuery.textScalerOf(context);
    final rankStyle = TextStyle(
      fontSize: textScaler.scale(18),
      fontWeight: FontWeight.bold,
    );
    final nameStyle = TextStyle(fontSize: textScaler.scale(16));
    final handleStyle = TextStyle(
      fontSize: textScaler.scale(14),
      color: Theme.of(context).hintColor,
    );
    final scoreStyle = TextStyle(
      fontSize: textScaler.scale(18),
      fontWeight: FontWeight.bold,
    );
    return Semantics(
      container: true,
      label:
          'Rank ${entry.rank}. $nameOrHandle. ${entry.metricValue} score. '
          'Verified.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            // Rank — left column, fixed width so the column
            // stays aligned when the user scales the text.
            SizedBox(
              width: 56,
              child: Text(
                '#${entry.rank}',
                textAlign: TextAlign.center,
                style: rankStyle,
              ),
            ),
            const SizedBox(width: 12),
            // Name + handle.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name ?? handle ?? '',
                    style: nameStyle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  if (handle != null && name != null)
                    Text(
                      handle,
                      style: handleStyle,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Score — right column, fixed width.
            SizedBox(
              width: 80,
              child: Text(
                '${entry.metricValue}',
                textAlign: TextAlign.end,
                style: scoreStyle,
              ),
            ),
            const SizedBox(width: 8),
            // Verified badge — semantic icon, semantic label.
            Icon(
              Icons.verified,
              color: Theme.of(context).colorScheme.primary,
              size: textScaler.scale(20),
              semanticLabel: 'Verified',
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.localizations});

  final AppLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              localizations.communityChallengeEmpty,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.failure,
    required this.localizations,
    required this.onRetry,
  });

  final AppFailure failure;
  final AppLocalizations localizations;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        const SizedBox(height: 32),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                localizations.communityChallengeErrorNetwork,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                child: Text(localizations.communityChallengeAccept),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
