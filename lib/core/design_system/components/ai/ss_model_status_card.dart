import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import '../cards/ss_content_card.dart';
import '../feedback/ss_status_badge.dart';
import '../surfaces/ss_surface.dart';
import 'ss_provenance_badge.dart';

/// The detector/coach model's current state (§3): its [provenance] — local
/// or cloud — renders unconditionally alongside any [statusBadges] (offline,
/// sync pending, confidence), never hidden behind a detail view (ADR 0278
/// §1/§5.1).
final class SsModelStatusCard extends StatelessWidget {
  const SsModelStatusCard({
    super.key,
    required this.l10n,
    required this.title,
    required this.provenance,
    this.message,
    this.statusBadges = const [],
    this.action,
    this.density = SsCardDensity.expanded,
  });

  final AppLocalizations l10n;
  final String title;
  final SsProvenanceKind provenance;
  final String? message;
  final List<SsStatusBadgeKind> statusBadges;
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
          Text(
            title,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (message != null) ...[
            const SizedBox(height: SsSpacing.space1),
            Text(
              message!,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
              maxLines: isCompact ? 1 : 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: SsSpacing.space2),
          Wrap(
            spacing: SsSpacing.space3,
            runSpacing: SsSpacing.space1,
            children: [
              SsProvenanceBadge(l10n: l10n, kind: provenance),
              for (final badgeKind in statusBadges)
                SsStatusBadge(l10n: l10n, kind: badgeKind),
            ],
          ),
        ],
      ),
    );

    final actions = action == null ? const <SsCardAction>[] : [action!];
    return SsSurface(
      child: SsCardActionRegion(actions: actions, child: content),
    );
  }
}
