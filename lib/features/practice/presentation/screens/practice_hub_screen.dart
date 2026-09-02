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

import '../../../../app/config/app_config.dart';
import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/public.dart';
import '../../../../core/foundation/app_result.dart';
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
    // E15-R07 F1 (ADR 0491 D1/D3) — the ONE entry point into the Practice
    // Generator flow. Flag-gated independently of the catalog above; the
    // card's copy is deliberately "build a plan", never "your plan is
    // ready" — the wizard it opens does not generate a plan yet (D3).
    final practiceGeneratorEnabled = ref
        .watch(appConfigProvider)
        .flags
        .practiceGeneratorEnabled;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.practiceHubTitle)),
      body: SafeArea(
        child: catalog.isEmpty
            ? const _EmptyCatalogLayout()
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  SsSpacing.space5,
                  SsSpacing.space3,
                  SsSpacing.space5,
                  SsSpacing.space8,
                ),
                children: [
                  Text(
                    l10n.practiceHubSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: SsSpacing.space4),
                  if (catalog.isNotEmpty) ...[
                    _QuickStartCard(
                      definition: catalog.first,
                      onOpen: () => _openSetup(context, catalog.first),
                    ),
                    const SizedBox(height: SsSpacing.space3),
                  ],
                  _DailyChallengeCard(
                    result: definitionResult,
                    onOpen: () {
                      if (definitionResult case Success(:final value)) {
                        _openSetup(context, value);
                      }
                    },
                  ),
                  if (practiceGeneratorEnabled) ...[
                    const SizedBox(height: SsSpacing.space3),
                    _PlanBuilderCard(onOpen: () => _openPlanBuilder(context)),
                  ],
                  const SizedBox(height: SsSpacing.space5),
                  _ModeFilterRow(active: activeMode, all: catalog),
                  const SizedBox(height: SsSpacing.space3),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: SsSpacing.space3,
                      ),
                      child: Text(
                        l10n.practiceHubEmptyCatalogSubtitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    ...filtered.map(
                      (def) => Padding(
                        padding: const EdgeInsets.only(
                          bottom: SsSpacing.space3,
                        ),
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

  void _openPlanBuilder(BuildContext context) {
    context.go(AppRoutes.practiceGeneratorSetup);
  }
}

/// The empty-catalog state (`practiceCatalogProvider` returning no
/// definitions never happens today — [BuiltinPracticeCatalog] is a const
/// list — but the Hub still renders this defensively for a future
/// data-driven catalog).
///
/// Built from design tokens directly rather than [SsEmptyState]: that
/// component mandates an `onAction` (§5.2), and the only candidate action —
/// invalidating [practiceCatalogProvider] — re-reads the same const list, so
/// it is provably a no-op (measured: `practice_catalog_controller.dart`).
/// The E15-R04 review flagged the previous "Retry" button as a dead control
/// borrowed from the session-retry copy; this mirrors
/// [SpeedBuilderScreen]'s `_UnavailableLayout`, the same documented §5.2
/// exception for a provably actionless informational state.
class _EmptyCatalogLayout extends StatelessWidget {
  const _EmptyCatalogLayout();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_outlined,
              color: colors.textSecondary,
              size: 40,
            ),
            const SizedBox(height: SsSpacing.space4),
            Text(
              l10n.practiceHubEmptyCatalogTitle,
              style: typography.titleMedium.copyWith(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SsSpacing.space2),
            Text(
              l10n.practiceHubEmptyCatalogSubtitle,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
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
            const SizedBox(width: SsSpacing.space2),
            for (final mode in PracticeMode.values) ...[
              ChoiceChip(
                label: Text(practiceModeLabel(l10n, mode)),
                selected: active == mode,
                onSelected: (_) => notifier.set(mode),
              ),
              const SizedBox(width: SsSpacing.space2),
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

/// The ONE entry point into the Practice Generator flow (E15-R07 F1, ADR
/// 0491 D1/D3). Opens [PlanSetupScreen] — a locally resumable wizard that
/// does NOT generate a plan at its last step (`plan_setup_screen.dart:96-99`
/// only advances the wizard); the label/subtitle here must stay honest about
/// that (ADR 0078 precedent) rather than implying a finished plan. Reuses
/// [AppLocalizations.planSetupTitle]/[AppLocalizations.planSetupGoalTitle] —
/// both already ship in `en`+`hu` — instead of adding a new ARB key, which
/// this round's file list does not cover.
class _PlanBuilderCard extends StatelessWidget {
  const _PlanBuilderCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _HubCard(
      title: l10n.planSetupTitle,
      subtitle: l10n.planSetupGoalTitle,
      trailing: Icons.auto_awesome_outlined,
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final color = enabled ? colors.brand : colors.textDisabled;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: l10n.practiceHubOpenSetup(title),
      child: SsSurface(
        radius: SsSurfaceRadius.md,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SsSpacing.space4,
              vertical: SsSpacing.space3,
            ),
            // ExcludeSemantics blocks the descendant Text widgets from
            // being merged into the parent Semantics label — otherwise
            // a screen reader would announce "Open Quick start\nQuick
            // start\nBegin the first practice in the catalog" instead
            // of the single label.
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Icon(trailing, size: 24, color: color),
                  const SizedBox(width: SsSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: typography.labelLarge.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: SsSpacing.space1),
                        Text(
                          subtitle,
                          style: typography.bodyMedium.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (enabled)
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
