import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/practice/public.dart' show practiceCatalogProvider;
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
                        onPressed: () {
                          final uri = Uri(
                            path: AppRoutes.practiceSetup,
                            queryParameters: <String, String>{
                              'id': catalog.first.id,
                            },
                          );
                          context.go(uri.toString());
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
                for (final label in [
                  l10n.practiceAreaHubCategoryWarmup,
                  l10n.practiceAreaHubCategoryChords,
                  l10n.practiceAreaHubCategoryRhythm,
                  l10n.practiceAreaHubCategoryScales,
                  l10n.practiceAreaHubCategoryTechnique,
                ])
                  ActionChip(
                    label: Text(label),
                    onPressed: () => context.go(AppRoutes.practiceSetup),
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
