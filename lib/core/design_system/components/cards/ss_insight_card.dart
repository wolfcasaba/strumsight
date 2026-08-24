import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import '../ai/ss_provenance_badge.dart';
import '../surfaces/ss_surface.dart';
import 'ss_content_card.dart';

/// An AI-derived observation about the player's practice (§3). When [provenance]
/// is set — i.e. the insight came from the coach layer, not a plain fact —
/// its [SsProvenanceBadge] renders unconditionally in the card's base state,
/// never behind a detail view (ADR 0278 §1/§5.1, §0.0/D4).
final class SsInsightCard extends StatelessWidget {
  const SsInsightCard({
    super.key,
    required this.l10n,
    required this.title,
    required this.message,
    this.icon = Icons.insights_outlined,
    this.provenance,
    this.action,
    this.density = SsCardDensity.expanded,
  });

  final AppLocalizations l10n;
  final String title;
  final String message;
  final IconData icon;
  final SsProvenanceKind? provenance;
  final SsCardAction? action;
  final SsCardDensity density;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final isCompact = density == SsCardDensity.compact;

    final content = Padding(
      padding: EdgeInsets.all(isCompact ? SsSpacing.space3 : SsSpacing.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.brand, size: 20),
              const SizedBox(width: SsSpacing.space2),
              Expanded(
                child: Text(
                  title,
                  style: typography.titleMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: SsSpacing.space1),
          Text(
            message,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
            maxLines: isCompact ? 2 : 4,
            overflow: TextOverflow.ellipsis,
          ),
          if (provenance != null) ...[
            const SizedBox(height: SsSpacing.space2),
            SsProvenanceBadge(l10n: l10n, kind: provenance!),
          ],
        ],
      ),
    );

    final actions = action == null ? const <SsCardAction>[] : [action!];
    return SsSurface(
      child: SsCardActionRegion(actions: actions, child: content),
    );
  }
}
