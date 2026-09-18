import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/practice/public.dart'
    show PracticeDefinition, practiceCatalogProvider;
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
                        onPressed: () =>
                            context.go(_practiceSetupUri(catalog.first.id)),
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
                  onPressed: () => context.go(AppRoutes.practiceLive),
                ),
                _QuickTool(
                  icon: Icons.tune,
                  label: l10n.liveTuner,
                  onPressed: () => context.go(AppRoutes.practiceTuner),
                ),
                _QuickTool(
                  icon: Icons.av_timer,
                  label: l10n.metronomeTitle,
                  onPressed: () => context.go(AppRoutes.practiceMetronome),
                ),
                _QuickTool(
                  icon: Icons.library_music_outlined,
                  label: l10n.chordLibraryTitle,
                  onPressed: () => context.go(AppRoutes.practiceChords),
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
                // A chip navigates ONLY with a definition id the catalog
                // resolved for that goal; a category with no content is
                // disabled instead — the same ADR 0508 D4 rule the
                // recommended card follows for an empty catalog, because
                // `/practice/setup` without `?id=` is
                // `PracticeSetupRequest.missing` and renders the error panel.
                for (final category in _PracticeCategory.values)
                  _CategoryChip(
                    category: category,
                    definition: category.firstIn(catalog),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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

/// The `/practice/setup?id=<definitionId>` deep link the setup screen reads.
///
/// Single definition of the query shape so the recommended CTA and the
/// category chips can never drift into two different spellings of `id`.
String _practiceSetupUri(String definitionId) => Uri(
  path: AppRoutes.practiceSetup,
  queryParameters: <String, String>{'id': definitionId},
).toString();

/// A goal-shaped grouping over the practice catalog, derived from each
/// definition's own declared `skillTags`.
///
/// This is a PRESENTATION grouping, not a new catalog field: a retagged
/// definition changes category by itself, and the hub never has to hold a
/// second copy of the catalog's content.
///
/// [skillTags] is ORDERED — the tag that most characterises the category
/// first — and [firstIn] resolves tag-major. Categories deliberately overlap
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
/// [scales] matches no shipped definition — the catalog has no scale
/// content. That is expressed as an empty match (the chip renders disabled),
/// never as a navigation to `/practice/setup` without an id.
enum _PracticeCategory {
  warmup(['downstrokes']),
  chords(['chordChanges', 'chordProgression']),
  rhythm(['rhythm', 'rhythmOnly', 'eighthNotes', 'quarterNotes']),
  scales(['scales']),
  technique(['offBeat', 'syncopation', 'upstrokes', 'freePlay']);

  const _PracticeCategory(this.skillTags);

  /// The `PracticeDefinition.skillTags` values that place a definition in this
  /// category, most characteristic first — the order [firstIn] resolves in.
  final List<String> skillTags;

  String label(AppLocalizations l10n) => switch (this) {
    _PracticeCategory.warmup => l10n.practiceAreaHubCategoryWarmup,
    _PracticeCategory.chords => l10n.practiceAreaHubCategoryChords,
    _PracticeCategory.rhythm => l10n.practiceAreaHubCategoryRhythm,
    _PracticeCategory.scales => l10n.practiceAreaHubCategoryScales,
    _PracticeCategory.technique => l10n.practiceAreaHubCategoryTechnique,
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
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.definition});

  final _PracticeCategory category;
  final PracticeDefinition? definition;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final target = definition;
    final chip = ActionChip(
      label: Text(category.label(l10n)),
      onPressed: target == null
          ? null
          : () => context.go(_practiceSetupUri(target.id)),
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
