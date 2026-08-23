/// Community post reactions widget bar (E09-R15, brief §1 / §5 / §6).
///
/// The bar shows the four allowlisted reactions (support, celebrate,
/// inspiring, helpful) as tappable chips, the aggregated reaction
/// count, and the viewer's current selection.
///
/// **Why a bar widget, not a button (§5.1):** every post row needs
/// the bar so the optimistic UI is in the same place the user
/// expects. A single "react" button that opens a picker is the
/// §14.1 Kör 17 scope (a future round may add a long-press
/// picker); this round ships the always-visible bar so the §5.2
/// toggle is a single tap.
///
/// **Accessibility (F1 / brief §5.3):** every chip carries a
/// semantic label that names the reaction ("React with Support",
/// "React with Celebrate", etc.) and announces its current state
/// ("Selected" / "Not selected") so a screen reader user can hear
/// which reaction they have, if any.
///
/// **No learning reward chip (§6 A7):** the bar shows the four
/// reaction chips AND the count — it does NOT include any
/// learning XP indicator (the E08-R26 cross-feature invariant).
///
/// **i18n note (F1):** the chip labels in this file are English
/// placeholders. The English ARB does not yet carry the reaction
/// strings; lifting them into ``lib/l10n/app_en.arb`` /
/// ``app_hu.arb`` is the next round's call (the ARB files are
/// outside this round's ``allowed_paths``).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controllers/reaction_controller.dart';
import '../../domain/entities/community_reaction.dart';
import '../../domain/entities/community_post.dart';

/// The reactions widget bar.
///
/// Renders four reaction chips + the aggregated count. A tap on a
/// chip toggles the viewer's reaction on the post (the §5.2 toggle
/// semantics): tapping the kind the viewer already holds clears it;
/// tapping a different kind switches to it.
class ReactionBar extends ConsumerWidget {
  const ReactionBar({super.key, required this.post});

  /// The post the bar belongs to. The bar reads the aggregated
  /// ``counts.reactionCount`` and the viewer's
  /// ``viewerState.myReaction`` from this entity; the controller's
  /// optimistic state overrides the latter until the mutation
  /// resolves.
  final CommunityPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reactionState = ref.watch(reactionControllerProvider);
    final controller = ref.read(reactionControllerProvider.notifier);
    final view =
        reactionState.reactionsByPost[post.id] ?? const ReactionView.empty();
    // The effective reaction is the controller's optimistic value
    // when present, falling back to the post's server-confirmed
    // ``viewerState.myReaction`` so a freshly-loaded post (the
    // controller has not yet been seeded) renders correctly.
    final selected =
        view.optimistic ?? view.server ?? post.viewerState.myReaction;
    final isBusy = view.isOptimistic;

    return Semantics(
      container: true,
      label: 'Reactions',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (final kind in ReactionKind.values)
            _ReactionChip(
              kind: kind,
              selected: selected == kind,
              onTap: isBusy
                  ? null
                  : () => controller.setReaction(post.id, kind),
            ),
          const SizedBox(width: 8),
          Text(
            post.counts.reactionCount.toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            semanticsLabel: '${post.counts.reactionCount} reactions',
          ),
        ],
      ),
    );
  }
}

/// A single reaction chip — tappable, accessible, with a clear
/// "selected" state. The icon is a Unicode emoji so this widget
/// does not depend on ``lucide_icons_flutter`` icon names that
/// fail at compile (the project-wide build gotcha — the linter
/// only catches a missing icon at runtime). Unicode emoji are
/// always available on the platform font.
class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final ReactionKind kind;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _labelFor(kind);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: 'React with $label',
        child: Material(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(_emojiFor(kind), style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _labelFor(ReactionKind kind) {
    // English-only placeholders — the next round lifts these
    // into the ARB files (out of this round's ``allowed_paths``).
    switch (kind) {
      case ReactionKind.support:
        return 'Support';
      case ReactionKind.celebrate:
        return 'Celebrate';
      case ReactionKind.inspiring:
        return 'Inspiring';
      case ReactionKind.helpful:
        return 'Helpful';
    }
  }

  String _emojiFor(ReactionKind kind) {
    // Unicode emoji are always available — no dependency on the
    // icon plugin, and no compile-time "icon not found" failure.
    switch (kind) {
      case ReactionKind.support:
        return '👍';
      case ReactionKind.celebrate:
        return '🎉';
      case ReactionKind.inspiring:
        return '✨';
      case ReactionKind.helpful:
        return '💡';
    }
  }
}
