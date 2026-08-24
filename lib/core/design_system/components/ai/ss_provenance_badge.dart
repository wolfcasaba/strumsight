import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';

/// Where an AI-touched piece of content was produced — the presentation-layer
/// enum ADR 0278 §5 calls for, since no `local`/`cloud` inference-location
/// type exists in the coach/analysis layer yet (§0.0/D4). Reads its icon and
/// colour from the EXISTING [SsColorScheme]/[SsStatusMarkers] tokens rather
/// than defining new ones (ADR 0273 — one token source).
enum SsProvenanceKind { local, cloud }

/// Makes the AI-eredet (origin) of a piece of content visible wherever that
/// content itself is shown — never tucked behind a detail view (ADR 0278 §1,
/// §5.1): whether audio or data left the device is a privacy fact, not a
/// cosmetic detail. Meaning is carried by icon AND text together, never by
/// colour alone (§5.2) — [SsProvenanceKind.local] and [SsProvenanceKind.cloud]
/// resolve to different icons AND different [l10n]-sourced labels.
final class SsProvenanceBadge extends StatelessWidget {
  const SsProvenanceBadge({super.key, required this.l10n, required this.kind});

  final AppLocalizations l10n;
  final SsProvenanceKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;

    final (markerKind, color, label) = switch (kind) {
      SsProvenanceKind.local => (
        SsStatusMarkerKind.localAi,
        colors.localAi,
        l10n.dsProvenanceBadgeLocalLabel,
      ),
      SsProvenanceKind.cloud => (
        SsStatusMarkerKind.cloudAi,
        colors.cloudAi,
        l10n.dsProvenanceBadgeCloudLabel,
      ),
    };

    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            SsStatusMarkers.forKind(markerKind).icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: SsSpacing.space1),
          Text(label, style: typography.labelLarge.copyWith(color: color)),
        ],
      ),
    );
  }
}
