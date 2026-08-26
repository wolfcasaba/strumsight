import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/song_setlist.dart';

/// Per-item readiness icon for a Setlist V2 entry (§5.4). The mapping is the
/// measured producer from §0.0/B/R20: [SetlistItemAvailability.ready] is
/// fully usable, [SetlistItemAvailability.missingAsset] still opens (only
/// playback is affected), and [SetlistItemAvailability.missingSong] carries
/// the unresolved [songId] in its Semantics label. Every other
/// [SetlistItemAvailability] value falls back to a generic attention-needed
/// indicator.
///
/// Deliberately icon-only — the widget is used inside a `Wrap` (compact
/// setlist card) and a `ListTile.leading` slot (editor sheet), both of which
/// give it a narrow, non-scrolling width; an inline text label of arbitrary
/// song-id length would overflow either host. The visible, non-truncated
/// "named" requirement (§6.1/A6) is satisfied by the caller showing the
/// songId as its own text near the icon.
final class SetlistItemAvailabilityBadge extends StatelessWidget {
  const SetlistItemAvailabilityBadge({
    required this.availability,
    required this.songId,
    super.key,
  });

  final SetlistItemAvailability availability;
  final String songId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (availability) {
      SetlistItemAvailability.ready => Semantics(
        label: l10n.setlistV2ItemReady,
        child: const Icon(
          Icons.check_circle_outline,
          color: Colors.green,
          size: 18,
        ),
      ),
      SetlistItemAvailability.missingAsset => Semantics(
        label: l10n.setlistV2ItemMissingAsset,
        child: const Icon(
          Icons.music_off_outlined,
          color: Colors.orange,
          size: 18,
        ),
      ),
      SetlistItemAvailability.missingSong => Semantics(
        label: l10n.setlistV2ItemMissingSong(songId),
        child: const Icon(Icons.error_outline, color: Colors.red, size: 18),
      ),
      SetlistItemAvailability.unsupportedTrack ||
      SetlistItemAvailability.requiresMigration ||
      SetlistItemAvailability.invalidConfig => Semantics(
        label: l10n.setlistV2ItemAttention,
        child: const Icon(
          Icons.warning_amber_outlined,
          color: Colors.orange,
          size: 18,
        ),
      ),
    };
  }
}
