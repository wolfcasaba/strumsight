import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/practice/public.dart'
    show
        PracticeDifficulty,
        nextPracticeRecommendationProvider,
        practiceCatalogProvider,
        practiceDefinitionDisplayTitle,
        practiceModeLabel,
        practiceNextReasonLabel;
import '../../../l10n/app_localizations.dart';
import '../practice_area_hub_categories.dart';

/// The Practice Area Hub (UI-06, SDD Ch13 §UI-06) — every practice tool's
/// rendezvous point: one recommended session, the guided course, quick tools
/// reachable in a single tap (A2, well under the 2-touch cap), and the whole
/// catalog browsable by goal.
///
/// Resource-free (A4, ADR 0276): this screen only *navigates* to
/// `/practice/tuner`, `/practice/metronome`, `/practice/live`,
/// `/practice/chords`, `/practice/learn` and the Song Trainer library —
/// none of those routes' screens are built inline here, so no microphone or
/// camera opens on this hub itself. Reading [practiceCatalogProvider]
/// (ADR 0508 D3) is a const-list lookup, not a resource open.
///
/// Every catalog tile navigates to Setup WITH its definition id — the
/// pre-existing "Browse by goal" chips called `/practice/setup` without one,
/// which `PracticeSetupScreen` renders as its route-error branch: five dead
/// ends in the middle of the hub. The goal groups are derived from the
/// definitions themselves ([practiceAreaHubGroups]); a goal with nothing in
/// it is not rendered.
///
/// Styled with plain Material widgets + [AppColors] (matching
/// `ProgressScreen`/the legacy `PracticeHubScreen`), not the
/// `core/design_system` component library — see `today_hub_screen.dart`'s
/// doc comment for why those widgets aren't safe under the app's current
/// root theme.
class PracticeAreaHubScreen extends ConsumerWidget {
  const PracticeAreaHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(practiceCatalogProvider);
    // MÉRT hiba (2026-09-06 review, MAJOR-3): a tervező belépési pontjait
    // csak a LEGACY `PracticeHubScreen` kapta meg, azt viszont a router
    // kizárólag `!adaptiveShellEnabled` mellett regisztrálja. A szállított
    // (Lab) buildben a shell BE van kapcsolva, tehát a `/practice` ezt a
    // képernyőt rendereli — belépő nélkül a tervező megint elérhetetlen.
    // Ugyanaz a zászló kapuz, mint a route-okat: `practiceGeneratorEnabled`.
    final flags = ref.watch(appConfigProvider).flags;
    final groups = practiceAreaHubGroups(catalog);
    // ADR 0508 D4 — `null` only for an empty catalog, so the recommended
    // card and the catalog stay consistent by construction.
    final recommendation = ref.watch(nextPracticeRecommendationProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.practiceHubTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            // ADR 0508 D4 — an empty catalog means no recommended card at
            // all (no title, no message, no button), not a CTA that
            // navigates without a definition id.
            if (recommendation != null)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.practiceAreaHubRecommendedTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      // The recommended definition by name, and the one
                      // honest sentence saying WHY it is next — derived from
                      // the learner's own history, never a generic promise.
                      Text(
                        practiceDefinitionDisplayTitle(
                          l10n,
                          recommendation.definition,
                        ),
                        key: const ValueKey('practice-hub-recommended-name'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        practiceNextReasonLabel(l10n, recommendation.reason),
                        key: const ValueKey('practice-hub-recommended-reason'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const ValueKey('practice-hub-recommended-cta'),
                        onPressed: () => _openSetup(
                          context,
                          definitionId: recommendation.definition.id,
                        ),
                        child: Text(l10n.practiceAreaHubRecommendedCta),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // The guided course (the 17-lesson curriculum) — the only path
            // that names what unlocks what. It was routed but no shell
            // button led to it; the hub is where a learner looks for it.
            Card(
              key: const ValueKey('practice-hub-course-card'),
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(
                  Icons.school_outlined,
                  color: AppColors.primary,
                ),
                title: Text(l10n.practiceAreaHubCourseTitle),
                subtitle: Text(l10n.practiceAreaHubCourseMessage),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.practiceLearn),
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                l10n.practiceAreaHubQuickToolsHeading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickTool(
                  icon: Icons.graphic_eq,
                  label: l10n.navLive,
                  onPressed: () => context.push(AppRoutes.practiceLive),
                ),
                _QuickTool(
                  icon: Icons.tune,
                  label: l10n.liveTuner,
                  onPressed: () => context.push(AppRoutes.practiceTuner),
                ),
                _QuickTool(
                  icon: Icons.av_timer,
                  label: l10n.metronomeTitle,
                  onPressed: () => context.push(AppRoutes.practiceMetronome),
                ),
                _QuickTool(
                  icon: Icons.library_music_outlined,
                  label: l10n.chordLibraryTitle,
                  onPressed: () => context.push(AppRoutes.practiceChords),
                ),
                if (flags.songTrainerV2Enabled)
                  _QuickTool(
                    key: const ValueKey('practice-hub-song-trainer'),
                    icon: Icons.queue_music,
                    label: l10n.songTrainerTitle,
                    onPressed: () => context.push(AppRoutes.songTrainerLibrary),
                  ),
              ],
            ),
            // A tervező belépői ugyanazt a zászlót kapják, mint a route-ok
            // (2026-09-06 review, MAJOR-3): kikapcsolt zászlónál egyik gomb
            // sem létezik, mert a cél-útvonal sincs regisztrálva.
            if (flags.practiceGeneratorEnabled) ...[
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(
                  l10n.planSetupTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _QuickTool(
                    key: const ValueKey('practice-area-hub-plan-builder'),
                    icon: Icons.auto_awesome_outlined,
                    label: l10n.planSetupGoalTitle,
                    onPressed: () =>
                        context.push(AppRoutes.practiceGeneratorSetup),
                  ),
                  _QuickTool(
                    key: const ValueKey('practice-area-hub-today-plan'),
                    icon: Icons.today_outlined,
                    label: l10n.todayPlanTitle,
                    onPressed: () =>
                        context.push(AppRoutes.practiceGeneratorToday),
                  ),
                ],
              ),
            ],
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(
                  l10n.practiceAreaHubCategoriesHeading,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
            for (final MapEntry(key: category, value: definitions)
                in groups) ...[
              const SizedBox(height: 16),
              Text(
                _categoryLabel(l10n, category),
                key: ValueKey('practice-hub-category-${category.name}'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              for (final definition in definitions) ...[
                Card(
                  key: ValueKey('practice-hub-definition-${definition.id}'),
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    title: Text(
                      practiceDefinitionDisplayTitle(l10n, definition),
                    ),
                    subtitle: Text(
                      '${practiceModeLabel(l10n, definition.mode)} · '
                      '${_difficultyLabel(l10n, definition.difficulty)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _openSetup(context, definitionId: definition.id),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// The one way into a scored practice: Setup, parameterized by the
  /// definition id (the same URI shape as the legacy Hub's `_openSetup`).
  static void _openSetup(BuildContext context, {required String definitionId}) {
    final uri = Uri(
      path: AppRoutes.practiceSetup,
      queryParameters: <String, String>{'id': definitionId},
    );
    context.push(uri.toString());
  }

  static String _categoryLabel(
    AppLocalizations l10n,
    PracticeAreaHubCategory category,
  ) => switch (category) {
    PracticeAreaHubCategory.warmup => l10n.practiceAreaHubCategoryWarmup,
    PracticeAreaHubCategory.chords => l10n.practiceAreaHubCategoryChords,
    PracticeAreaHubCategory.rhythm => l10n.practiceAreaHubCategoryRhythm,
    PracticeAreaHubCategory.scales => l10n.practiceAreaHubCategoryScales,
    PracticeAreaHubCategory.technique => l10n.practiceAreaHubCategoryTechnique,
  };

  static String _difficultyLabel(
    AppLocalizations l10n,
    PracticeDifficulty difficulty,
  ) => switch (difficulty) {
    PracticeDifficulty.beginner => l10n.practiceAreaHubDifficultyBeginner,
    PracticeDifficulty.intermediate =>
      l10n.practiceAreaHubDifficultyIntermediate,
    PracticeDifficulty.advanced => l10n.practiceAreaHubDifficultyAdvanced,
  };
}

/// A single-tap quick tool: icon + label, text-button weight so it never
/// competes with the hub's one primary "start recommended" action (§5.2).
class _QuickTool extends StatelessWidget {
  const _QuickTool({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: AppColors.primary),
      label: Text(label),
    );
  }
}
