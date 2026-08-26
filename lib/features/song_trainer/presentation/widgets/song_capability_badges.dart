import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/repositories/song_repository.dart';

/// Compact, truthful capability indicators rendered from index metadata.
final class SongCapabilityBadges extends StatelessWidget {
  const SongCapabilityBadges({required this.summary, super.key});

  final SongSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final capability = summary.capability;
    if (capability == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      children: <Widget>[
        _Badge(
          icon: capability.canTrain
              ? Icons.school_outlined
              : Icons.block_outlined,
          label: capability.canTrain
              ? l10n.songCapabilityTrainerAvailable
              : l10n.songCapabilityTrainerUnavailable,
          color: capability.canTrain ? Colors.green : Colors.orange,
        ),
        _Badge(
          icon: capability.canExport
              ? Icons.ios_share_outlined
              : Icons.block_outlined,
          label: capability.canExport
              ? l10n.songCapabilityExportAvailable
              : l10n.songCapabilityExportUnavailable,
          color: capability.canExport ? Colors.green : Colors.orange,
        ),
        if (!capability.canPersist)
          _Badge(
            key: ValueKey<String>(
              'song-summary-readonly-${summary.documentId.value}',
            ),
            icon: Icons.lock_outline,
            label: l10n.songLibraryReadOnly,
            color: Colors.orange,
          ),
      ],
    );
  }
}

final class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Icon(icon, color: color, size: 18),
  );
}
