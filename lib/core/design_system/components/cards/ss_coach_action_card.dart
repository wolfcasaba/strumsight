import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_semantics.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import '../actions/ss_icon_button.dart';
import '../surfaces/ss_surface.dart';
import 'ss_content_card.dart';

/// A coach-suggested next step (§3): [onAction] is the single main action
/// (§5.3), so the whole card is one tap target — no separate button is drawn
/// for it. The optional [onDismiss] is a SEPARATE, smaller icon button
/// layered on top via [Stack]/[Positioned]: tapping it must resolve to
/// [onDismiss] alone and never also fire [onAction] (A4) — Flutter's own
/// gesture-arena/hit-test ordering already guarantees this for two
/// overlapping tap targets, so no manual bubbling guard is needed.
final class SsCoachActionCard extends StatelessWidget {
  const SsCoachActionCard({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.onDismiss,
    this.dismissSemanticLabel,
    this.density = SsCardDensity.expanded,
  }) : assert(
         onDismiss == null || dismissSemanticLabel != null,
         'dismissSemanticLabel is required when onDismiss is set',
       );

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onDismiss;
  final String? dismissSemanticLabel;
  final SsCardDensity density;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final isCompact = density == SsCardDensity.compact;
    final hasDismiss = onDismiss != null;

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? SsSpacing.space3 : SsSpacing.space4,
        isCompact ? SsSpacing.space3 : SsSpacing.space4,
        hasDismiss
            ? SsSemantics.minimumInteractiveDimension
            : (isCompact ? SsSpacing.space3 : SsSpacing.space4),
        isCompact ? SsSpacing.space3 : SsSpacing.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: SsSpacing.space1),
          Text(
            message,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
            maxLines: isCompact ? 2 : 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: SsSpacing.space2),
          Text(
            actionLabel,
            style: typography.labelLarge.copyWith(color: colors.brand),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    final action = SsCardAction(label: actionLabel, onPressed: onAction);

    return SsSurface(
      child: Stack(
        children: [
          SsCardActionRegion(actions: [action], child: content),
          if (hasDismiss)
            Positioned(
              top: SsSpacing.space1,
              right: SsSpacing.space1,
              child: SsIconButton(
                iconName: 'close',
                semanticLabel: dismissSemanticLabel!,
                tooltip: dismissSemanticLabel!,
                onPressed: onDismiss!,
              ),
            ),
        ],
      ),
    );
  }
}
