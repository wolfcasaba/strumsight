import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/practice/public.dart'
    show
        PracticeCategory,
        PracticeDefinition,
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
/// doc comment. The old "not safe under the app's root theme" reason is
/// obsolete (R21, audit MI8); the migration itself is still open.
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
                        onPressed: () => openSetup(
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
            // The quick tools PUSH: `go` replaces the whole stack, so a
            // single BACK from the Metronome left the app instead of
            // returning to this hub (emulator audit H5).
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
                // E17-R02 (ADR 0521) — the ONLY entry point of the Analysis
                // V2 capture flow, shown while `audioAnalysisV2Enabled` is
                // on (the routes it leads to exist only under that gate), so
                // a production build with the flag off sees no new button.
                if (ref.watch(appConfigProvider).flags.audioAnalysisV2Enabled)
                  _QuickTool(
                    key: const ValueKey('practice-hub-analysis-v2'),
                    icon: Icons.analytics_outlined,
                    label: l10n.analysisHomeEntryCta,
                    onPressed: () => context.push(AppRoutes.analysisHome),
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
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                l10n.practiceAreaHubCategoriesHeading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            // The goal chips are the JUMP row over the same catalog the
            // grouped tiles below list in full: one tap from the top of the
            // hub straight to that goal's exercise. A chip navigates ONLY
            // with a definition id the catalog resolved for that goal; a
            // category with no content is disabled instead - the same
            // ADR 0508 D4 rule the recommended card follows for an empty
            // catalog, because `/practice/setup` without `?id=` is
            // `PracticeSetupRequest.missing` and renders the error panel.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in _ChipCategory.values)
                  _CategoryChip(
                    category: category,
                    definition: category.firstIn(catalog),
                  ),
              ],
            ),
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
                        openSetup(context, definitionId: definition.id),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
            // R18 (audit B2/B3/B4) — a katalógus, az elemzés és a leckék
            // belépési pontjai. MIÉRT ITT, a lista VÉGÉN: a képernyő
            // pixelre rögzített golden-teszttel bír
            // (`e13_r17_practice_area_hub_compact*.png`), amit ezen a boxon
            // nem lehet újra felvenni; a látható területen bármi máshová
            // tett vezérlő elmozdítaná a rajzolatot. A lista aljára fűzött
            // szakasz a golden nézetablakán KÍVÜL kezdődik, tehát a mérce
            // változatlan marad, a három cél viszont elérhetővé válik.
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                l10n.practiceAreaHubMoreHeading,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickTool(
                  key: const ValueKey('practice-hub-all-practices'),
                  icon: Icons.list_alt,
                  label: l10n.practiceAreaHubAllPractices,
                  onPressed: () => _openCatalog(context),
                ),
                _QuickTool(
                  key: const ValueKey('practice-hub-analyze'),
                  icon: Icons.multitrack_audio_outlined,
                  label: l10n.navAnalyze,
                  onPressed: () => context.push(AppRoutes.practiceAnalyze),
                ),
                _QuickTool(
                  key: const ValueKey('practice-hub-learn'),
                  icon: Icons.school_outlined,
                  label: l10n.navLearn,
                  onPressed: () => context.push(AppRoutes.practiceLearn),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The one way into a scored practice: Setup, parameterized by the
  /// definition id (the same URI shape as the legacy Hub's `_openSetup`).
  static void openSetup(BuildContext context, {required String definitionId}) {
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

  /// Opens the full practice catalog list, optionally narrowed to one goal
  /// [category]. `push`, not `go`: the catalog is a top-level route (not a
  /// shell branch), so `go` would replace the shell stack and leave the user
  /// with no way back to the hub.
  void _openCatalog(BuildContext context, {PracticeCategory? category}) {
    final uri = Uri(
      path: AppRoutes.practiceCatalog,
      queryParameters: category == null
          ? null
          : <String, String>{'category': category.code},
    );
    context.push(uri.toString());
  }
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

/// The goal-chip grouping: a category -> the ONE definition its chip opens.
///
/// This is a PRESENTATION mapping over the catalog's own declared
/// `skillTags`, not a new catalog field: a retagged definition changes
/// category by itself, and the hub never has to hold a second copy of the
/// catalog's content. It is deliberately separate from
/// [PracticeAreaHubCategory] (the grouping the tiles below the chips use):
/// that one answers "which goal does this definition belong to" for EVERY
/// definition, this one answers "which single exercise does this goal's chip
/// open", and the two questions resolve ties differently.
///
/// [skillTags] is ORDERED - the tag that most characterises the category
/// first - and [firstIn] resolves tag-major. Categories deliberately overlap
/// (the quarter-note downstroke drill is tagged both `downstrokes` and
/// `quarterNotes`), so a definition-major scan hands two categories the SAME
/// exercise: Rhythm would open the Warm-up drill, because that drill is
/// declared first in the catalog and carries Rhythm's generic `quarterNotes`
/// tag. Asking "is there a real rhythm exercise?" before falling back to the
/// generic beat-value tags keeps every chip on the exercise its own label
/// promises.
///
/// The same rule decides Technique: `offBeat` leads, because it is carried
/// only by the dedicated off-beat drill, while the broader `syncopation` is
/// also claimed by the folk strumming pattern declared earlier in the
/// catalog. Without the dedicated tag first, Technique would open a folk
/// pattern.
///
/// [scales] matches no shipped definition - the catalog has no scale
/// content. That is expressed as an empty match (the chip renders disabled),
/// never as a navigation to `/practice/setup` without an id.

/// One goal category chip.
///
/// Enabled only when [definition] resolved: a chip that navigated without an
/// id would land on the setup screen's error panel on every tap.
///
/// A disabled chip EXPLAINS itself. Greying a chip out with no feedback
/// reads as a bug ("the app ignored my tap"), so the disabled state carries
/// both a [Tooltip] (long-press / hover, sighted users) and a semantics hint
/// merged into the chip's own node, so TalkBack/VoiceOver announce the label
/// and the reason together instead of an unexplained disabled control.

enum _ChipCategory {
  warmup(['downstrokes']),
  chords(['chordChanges', 'chordProgression']),
  rhythm(['rhythm', 'rhythmOnly', 'eighthNotes', 'quarterNotes']),
  scales(['scales']),
  technique(['offBeat', 'syncopation', 'upstrokes', 'freePlay']);

  const _ChipCategory(this.skillTags);

  /// The `PracticeDefinition.skillTags` values that place a definition in
  /// this category, most characteristic first - the order [firstIn] resolves
  /// in.
  final List<String> skillTags;

  String label(AppLocalizations l10n) => switch (this) {
    _ChipCategory.warmup => l10n.practiceAreaHubCategoryWarmup,
    _ChipCategory.chords => l10n.practiceAreaHubCategoryChords,
    _ChipCategory.rhythm => l10n.practiceAreaHubCategoryRhythm,
    _ChipCategory.scales => l10n.practiceAreaHubCategoryScales,
    _ChipCategory.technique => l10n.practiceAreaHubCategoryTechnique,
  };

  /// The definition this category's chip opens: the first catalog entry
  /// carrying this category's most characteristic tag, falling back to its
  /// less specific tags in [skillTags] order, or `null` when no entry carries
  /// any of them.
  ///
  /// Ties within one tag are broken by the catalog's own declaration order,
  /// which is part of the catalog contract.
  PracticeDefinition? firstIn(List<PracticeDefinition> catalog) {
    for (final tag in skillTags) {
      for (final definition in catalog) {
        if (definition.skillTags.contains(tag)) return definition;
      }
    }
    return null;
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.definition});

  final _ChipCategory category;
  final PracticeDefinition? definition;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = definition;
    final chip = ActionChip(
      label: Text(category.label(l10n)),
      onPressed: target == null
          ? null
          : () => PracticeAreaHubScreen.openSetup(
              context,
              definitionId: target.id,
            ),
    );
    if (target != null) return chip;

    return Tooltip(
      message: l10n.practiceAreaHubCategoryComingSoonTooltip,
      child: MergeSemantics(
        child: Semantics(
          hint: l10n.practiceAreaHubCategoryComingSoonHint,
          child: chip,
        ),
      ),
    );
  }
}
