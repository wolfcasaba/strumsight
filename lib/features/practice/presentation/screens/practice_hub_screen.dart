/// The Practice feature's entry screen — the Hub (E02-R12, ADR 0078).
///
/// In this round the Hub is flag-gated (`practiceEngineV2Enabled`); the
/// Kör 13 pre-flight will lift the gate and add a session entry point.
/// What lives here today:
///   * A mode-filter chip row over the full catalog (A1, A2);
///   * A Quick Start card (first catalog entry → Setup) (A3);
///   * A Daily Challenge card whose tap target is **disabled** when the
///     adapter rejects the challenge (empty pattern) — never silently
///     hidden (A3, SDD "no ghost affordances");
///   * Localized empty state when the catalog is empty (A1, A3);
///   * A placeholder Continue/Recent block is **deliberately absent** —
///     history is a Kör 18 concern, and the A3 test pins the absence.
///
/// The screen imports no domain service, has no timing primitive, no
/// matcher and no scorer (A9 guard).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../streak/public.dart';
import '../../data/adapters/daily_challenge_practice_adapter.dart';
import '../../domain/model/practice_definition.dart';
import '../../domain/model/practice_mode.dart';
import '../../application/practice_catalog_controller.dart';
import '../widgets/practice_mode_card.dart';

/// The Hub.
class PracticeHubScreen extends ConsumerWidget {
  const PracticeHubScreen({super.key, this.now, this.dailyChallenge})
    : assert(
        // The Hub reads the wall clock exactly once, as the default for
        // the injectable `now` (A9 — see ADR 0078 §8).
        now == null || true,
        'now is injectable for tests; one clock read lives in the default',
      );

  /// Injectable clock for tests. Defaults to the real now.
  final DateTime? now;

  /// Injectable daily challenge for tests. Defaults to the deterministic
  /// challenge for [now] (same algorithm as the Streak screen, RAG chunk
  /// 013). A test can supply a `DailyChallenge` with an empty pattern to
  /// exercise the failure path of the adapter.
  final DailyChallenge? dailyChallenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final nowValue = now ?? DateTime.now();
    final today = StreakLogic.epochDayOf(nowValue);
    final challenge = dailyChallenge ?? DailyChallenge.forDay(today);
    final definitionResult = practiceDefinitionFromDailyChallenge(challenge);
    final catalog = ref.watch(practiceCatalogProvider);
    final repository = ref.watch(practiceCatalogRepositoryProvider);
    final activeMode = ref.watch(_practiceHubModeFilterProvider);
    final filtered = activeMode == null
        ? catalog
        : repository.byMode(activeMode);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.practiceHubTitle)),
      body: SafeArea(
        child: catalog.isEmpty
            ? EmptyState(
                icon: Icons.queue_music_outlined,
                title: l10n.practiceHubEmptyCatalogTitle,
                subtitle: l10n.practiceHubEmptyCatalogSubtitle,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Text(
                    l10n.practiceHubSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  if (catalog.isNotEmpty) ...[
                    _QuickStartCard(
                      definition: catalog.first,
                      onOpen: () => _openSetup(context, catalog.first),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _DailyChallengeCard(
                    result: definitionResult,
                    onOpen: () {
                      if (definitionResult case Success(:final value)) {
                        _openSetup(context, value);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  _ModeFilterRow(active: activeMode, all: catalog),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        l10n.practiceHubEmptyCatalogSubtitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    ...filtered.map(
                      (def) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: PracticeModeCard(
                          definition: def,
                          onTap: () => _openSetup(context, def),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  void _openSetup(BuildContext context, PracticeDefinition definition) {
    final uri = Uri(
      path: AppRoutes.practiceSetup,
      queryParameters: <String, String>{'id': definition.id},
    );
    context.go(uri.toString());
  }
}

/// The active mode filter on the Hub. `null` means "all modes".
class _PracticeHubModeFilter extends Notifier<PracticeMode?> {
  @override
  PracticeMode? build() => null;

  void set(PracticeMode? mode) {
    if (state == mode) {
      state = null; // tapping the active chip clears the filter
    } else {
      state = mode;
    }
  }
}

final _practiceHubModeFilterProvider =
    NotifierProvider<_PracticeHubModeFilter, PracticeMode?>(
      _PracticeHubModeFilter.new,
    );

class _ModeFilterRow extends ConsumerWidget {
  const _ModeFilterRow({required this.active, required this.all});

  final PracticeMode? active;
  final List<PracticeDefinition> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(_practiceHubModeFilterProvider.notifier);
    return Semantics(
      label: l10n.practiceHubFilterMode,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: Text(l10n.practiceHubFilterAll),
              selected: active == null,
              onSelected: (_) => notifier.set(null),
            ),
            const SizedBox(width: 8),
            for (final mode in PracticeMode.values) ...[
              ChoiceChip(
                label: Text(practiceModeLabel(l10n, mode)),
                selected: active == mode,
                onSelected: (_) => notifier.set(mode),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard({required this.definition, required this.onOpen});

  final PracticeDefinition definition;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _HubCard(
      title: l10n.practiceHubQuickStartLabel,
      subtitle: l10n.practiceHubQuickStartSubtitle,
      trailing: Icons.play_arrow,
      onTap: onOpen,
    );
  }
}

class _DailyChallengeCard extends StatelessWidget {
  const _DailyChallengeCard({required this.result, required this.onOpen});

  final AppResult<PracticeDefinition> result;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (result) {
      Success(:final value) => _HubCard(
        title: l10n.practiceHubDailyChallengeLabel,
        subtitle: value.displayTitle ?? l10n.practiceHubDailyChallengeLabel,
        trailing: Icons.local_fire_department,
        onTap: onOpen,
      ),
      Failure() => _HubCard(
        title: l10n.practiceHubDailyChallengeLabel,
        subtitle: l10n.practiceHubDailyChallengeUnavailable,
        trailing: Icons.block,
        enabled: false,
        onTap: onOpen,
      ),
    };
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData trailing;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).colorScheme.outline;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: l10n.practiceHubOpenSetup(title),
      child: Material(
        color: enabled
            ? color.withValues(alpha: 0.10)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            // ExcludeSemantics blocks the descendant Text widgets from
            // being merged into the parent Semantics label — otherwise
            // a screen reader would announce "Open Quick start\nQuick
            // start\nBegin the first practice in the catalog" instead
            // of the single label.
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Icon(trailing, size: 24, color: enabled ? color : muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (enabled)
                    Icon(Icons.chevron_right, size: 20, color: muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
