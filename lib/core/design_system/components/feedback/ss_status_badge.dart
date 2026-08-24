import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';

/// The offline/sync/confidence states a card or surface can carry (§3). Each
/// resolves to its own icon and [l10n]-sourced label — never colour alone
/// (§5.2). [SsStatusBadgeKind.confidenceHigh]/[confidenceMedium]/[confidenceLow]
/// share the confidence glyph but never share a label: the level itself is
/// the READABLE fact, not just a colour (Ch13 §13.1 — R03's rule that low
/// confidence is a distinct state, not `danger`).
enum SsStatusBadgeKind {
  offline,
  syncPending,
  confidenceHigh,
  confidenceMedium,
  confidenceLow,
}

/// A small icon+text status marker (§5.2). The icon and label paint from
/// [SsColorScheme.textPrimary] — a readable text token, not the per-kind
/// status token (fix1/F1, fix1/F2): [SsColorScheme.syncPending] is itself a
/// SURFACE token (`palette.track`, reused as [SsColorScheme.surfaceSunken]),
/// so painting it as foreground text made the sync-pending badge blend into
/// its own card background, and the other status tokens fall below the
/// project's 4.5:1 text-contrast floor in at least one theme. The status
/// token is not used for text painting at all any more; distinctness between
/// kinds is carried by icon+label alone (§5.2, A2).
final class SsStatusBadge extends StatelessWidget {
  const SsStatusBadge({super.key, required this.l10n, required this.kind});

  final AppLocalizations l10n;
  final SsStatusBadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;

    final (icon, label) = switch (kind) {
      SsStatusBadgeKind.offline => (
        SsStatusMarkers.forKind(SsStatusMarkerKind.offline).icon,
        l10n.dsStatusBadgeOffline,
      ),
      SsStatusBadgeKind.syncPending => (
        Icons.sync_outlined,
        l10n.dsStatusBadgeSyncPending,
      ),
      SsStatusBadgeKind.confidenceHigh => (
        SsStatusMarkers.forKind(SsStatusMarkerKind.confidence).icon,
        l10n.dsStatusBadgeConfidenceHigh,
      ),
      SsStatusBadgeKind.confidenceMedium => (
        SsStatusMarkers.forKind(SsStatusMarkerKind.confidence).icon,
        l10n.dsStatusBadgeConfidenceMedium,
      ),
      SsStatusBadgeKind.confidenceLow => (
        SsStatusMarkers.forKind(SsStatusMarkerKind.confidence).icon,
        l10n.dsStatusBadgeConfidenceLow,
      ),
    };

    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.textPrimary),
          const SizedBox(width: SsSpacing.space1),
          Flexible(
            child: Text(
              label,
              style: typography.labelLarge.copyWith(color: colors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
