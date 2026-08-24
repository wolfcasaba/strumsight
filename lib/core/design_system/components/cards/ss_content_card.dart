import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import '../actions/ss_button.dart';
import '../surfaces/ss_surface.dart';

/// The two content densities the Ch13 card set supports (§3, §5.6).
enum SsCardDensity { compact, expanded }

/// A single actionable affordance a card can expose — the unit the §6.1
/// action-count cells (0 / 1 / 2+) are measured against.
@immutable
final class SsCardAction {
  const SsCardAction({required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
}

/// Applies the §5.3 action-count contract to [child]: **zero** actions
/// renders [child] as pure information (no tap target anywhere); **one**
/// action wraps the whole surface in a single tap target — the entire card
/// IS the button; **two or more** render as their own buttons below [child]
/// and leave the surface itself untappable, so a background tap never fires
/// an action the user can't identify in advance (§5.3, ADR 0278 §5).
///
/// This is shared by every card in this round rather than reimplemented per
/// file (§0.0/D3's `SsSurface`-based cards all need the identical rule), and
/// each card only builds its own [child] content.
final class SsCardActionRegion extends StatelessWidget {
  const SsCardActionRegion({
    super.key,
    required this.actions,
    required this.child,
  });

  final List<SsCardAction> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return child;

    if (actions.length == 1) {
      return InkWell(onTap: actions.single.onPressed, child: child);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: SsSpacing.space2),
        Padding(
          padding: const EdgeInsets.only(
            left: SsSpacing.space4,
            right: SsSpacing.space4,
            bottom: SsSpacing.space4,
          ),
          child: Wrap(
            spacing: SsSpacing.space2,
            runSpacing: SsSpacing.space2,
            children: [
              for (final action in actions)
                SsButton(
                  label: action.label,
                  icon: action.icon,
                  variant: SsButtonVariant.tertiary,
                  onPressed: action.onPressed,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A general-purpose information card: an optional leading icon, a title, an
/// optional message, and 0/1/2+ [actions] (§6.1). Built on [SsSurface], not
/// `SsCard` (§0.0/D3 — the catalog's exact-count guard already owns the one
/// `SsCard` in the tree).
///
/// The title never overflows its row at any text scale (§5.6): it is wrapped
/// in [Expanded] with a two-line ellipsis instead of a bare [Text].
final class SsContentCard extends StatelessWidget {
  const SsContentCard({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.actions = const [],
    this.density = SsCardDensity.expanded,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final List<SsCardAction> actions;
  final SsCardDensity density;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final isCompact = density == SsCardDensity.compact;

    final header = Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: colors.textSecondary, size: 20),
          const SizedBox(width: SsSpacing.space2),
        ],
        Expanded(
          child: Text(
            title,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actions.length == 1) ...[
          const SizedBox(width: SsSpacing.space2),
          Icon(Icons.chevron_right, color: colors.textSecondary, size: 20),
        ],
      ],
    );

    final body = Padding(
      padding: EdgeInsets.all(isCompact ? SsSpacing.space3 : SsSpacing.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          if (message != null) ...[
            const SizedBox(height: SsSpacing.space1),
            Text(
              message!,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
              maxLines: isCompact ? 2 : 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );

    return SsSurface(
      child: SsCardActionRegion(actions: actions, child: body),
    );
  }
}
