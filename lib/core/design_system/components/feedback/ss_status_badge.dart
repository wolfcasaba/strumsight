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

/// A small icon+text status marker (§5.2), reading its colour from the
/// EXISTING [SsColorScheme] tokens (ADR 0273) — [SsStatusBadgeKind.syncPending]
/// has no [SsStatusMarkerKind] of its own (§0.0/D4), so its icon is defined
/// here while its colour still comes from [SsColorScheme.syncPending].
final class SsStatusBadge extends StatelessWidget {
  const SsStatusBadge({super.key, required this.l10n, required this.kind});

  final AppLocalizations l10n;
  final SsStatusBadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;

    final (icon, color, label) = switch (kind) {
      SsStatusBadgeKind.offline => (
        SsStatusMarkers.forKind(SsStatusMarkerKind.offline).icon,
        colors.offline,
        l10n.dsStatusBadgeOffline,
      ),
      SsStatusBadgeKind.syncPending => (
        Icons.sync_outlined,
        colors.syncPending,
        l10n.dsStatusBadgeSyncPending,
      ),
      SsStatusBadgeKind.confidenceHigh => (
        SsStatusMarkers.forKind(SsStatusMarkerKind.confidence).icon,
        colors.confidenceHigh,
        l10n.dsStatusBadgeConfidenceHigh,
      ),
      SsStatusBadgeKind.confidenceMedium => (
        SsStatusMarkers.forKind(SsStatusMarkerKind.confidence).icon,
        colors.confidenceMedium,
        l10n.dsStatusBadgeConfidenceMedium,
      ),
      SsStatusBadgeKind.confidenceLow => (
        SsStatusMarkers.forKind(SsStatusMarkerKind.confidence).icon,
        colors.confidenceLow,
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
          Icon(icon, size: 16, color: color),
          const SizedBox(width: SsSpacing.space1),
          Text(label, style: typography.labelLarge.copyWith(color: color)),
        ],
      ),
    );
  }
}
