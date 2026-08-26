import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/song_setlist.dart';

/// Per-item readiness indicator for a Setlist V2 entry (§5.4). The mapping
/// is the measured producer from §0.0/B/R20: [SetlistItemAvailability.ready]
/// is fully usable, [SetlistItemAvailability.missingAsset] still opens (only
/// playback is affected), and [SetlistItemAvailability.missingSong] names
/// the unresolved [songId] instead of silently dropping the entry. Every
/// other [SetlistItemAvailability] value falls back to a generic
/// attention-needed indicator.
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 4),
            Text(l10n.setlistV2ItemMissingSong(songId)),
          ],
        ),
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
