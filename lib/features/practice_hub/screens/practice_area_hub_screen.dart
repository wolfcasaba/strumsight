import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/practice/public.dart'
    show PracticeGoal, practiceCatalogProvider, resolvePracticeGoals;
import '../../../l10n/app_localizations.dart';

/// The Practice Area Hub (UI-06, SDD Ch13 §UI-06) — every practice tool's
/// rendezvous point: one recommended session, quick tools reachable in a
/// single tap (A2, well under the 2-touch cap), and goal-based catalog
/// categories.
///
/// Resource-free (A4, ADR 0276): this screen only *navigates* to
/// `/practice/tuner`, `/practice/metronome`, `/practice/live` and
/// `/practice/chords` — none of those routes' screens are built inline
/// here, so no microphone or camera opens on this hub itself. Reading
/// [practiceCatalogProvider] (ADR 0508 D3) is a const-list lookup, not a
/// resource open.
///
/// Every navigation here is a `context.push`, never `context.go`: the tool
/// routes are registered as siblings of this hub inside the Practice branch,
/// so `go` REPLACED the branch stack with a single page and the Android
/// system back then closed the app instead of returning here (E18-R01
/// emulator finding F4, 4/4 reproduced). A push stacks the tool above the
/// hub, so back — and the in-screen back arrow — pop to it.
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
    // E18-R01 F6: each goal chip opens the practice the catalogue resolves
    // for it; a goal the catalogue cannot serve says so IN PLACE instead of
    // landing on "Practice unavailable". (All five chips stay rendered — the
    // e13_r17 pixel golden of this hub is regenerated only on the box.)
    final goals = {
      for (final entry in resolvePracticeGoals(catalog))
        entry.goal: entry.definitionId,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.practiceHubTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            // ADR 0508 D4 — an empty catalog means no recommended card at
            // all (no title, no message, no button), not a CTA that
            // navigates without a definition id.
            if (catalog.isNotEmpty)
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
                      Text(
                        l10n.practiceAreaHubRecommendedMessage,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const ValueKey('practice-hub-recommended-cta'),
                        onPressed: () {
                          final uri = Uri(
                            path: AppRoutes.practiceSetup,
                            queryParameters: <String, String>{
                              'id': catalog.first.id,
                            },
                          );
                          context.push(uri.toString());
                        },
                        child: Text(l10n.practiceAreaHubRecommendedCta),
                      ),
                    ],
                  ),
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
                // The curriculum's down/up rhythm pillar. A registered route
                // with no entry point is a screen nobody can reach.
                _QuickTool(
                  icon: Icons.swap_vert,
                  label: l10n.curriculumRhythmTitle,
                  onPressed: () => context.push(AppRoutes.curriculumRhythm),
                ),
                // The course itself, not just one rung of it. Same rule as the
                // line above: a registered route with no entry point is a screen
                // nobody can reach, and until this existed the ladder, its gating
                // and its ordering were visible only in tests.
                _QuickTool(
                  icon: Icons.stairs,
                  label: l10n.curriculumLadderTitle,
                  onPressed: () => context.push(AppRoutes.curriculumLadder),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                l10n.practiceAreaHubCategoriesHeading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final goal in PracticeGoal.values)
                  ActionChip(
                    key: ValueKey('practice-hub-goal-${goal.name}'),
                    label: Text(_goalLabel(l10n, goal)),
                    onPressed: () => _openGoal(context, l10n, goals[goal]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _openGoal(
  BuildContext context,
  AppLocalizations l10n,
  String? definitionId,
) {
  if (definitionId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.practiceAreaHubGoalUnavailable)),
    );
    return;
  }
  context.push(
    Uri(
      path: AppRoutes.practiceSetup,
      queryParameters: <String, String>{'id': definitionId},
    ).toString(),
  );
}

String _goalLabel(AppLocalizations l10n, PracticeGoal goal) => switch (goal) {
  PracticeGoal.warmup => l10n.practiceAreaHubCategoryWarmup,
  PracticeGoal.chords => l10n.practiceAreaHubCategoryChords,
  PracticeGoal.rhythm => l10n.practiceAreaHubCategoryRhythm,
  PracticeGoal.scales => l10n.practiceAreaHubCategoryScales,
  PracticeGoal.technique => l10n.practiceAreaHubCategoryTechnique,
};

/// A single-tap quick tool: icon + label, text-button weight so it never
/// competes with the hub's one primary "start recommended" action (§5.2).
class _QuickTool extends StatelessWidget {
  const _QuickTool({
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
