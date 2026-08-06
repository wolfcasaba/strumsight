import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Entry point for a structure-focused Song Trainer tutor conversation.
class SongTutorEntryCard extends StatelessWidget {
  const SongTutorEntryCard({
    super.key,
    required this.songTitle,
    required this.sectionCount,
    required this.measureCount,
    required this.chordScoringAvailable,
    required this.pitchScoringAvailable,
    this.onOpenTutor,
  });

  final String songTitle;
  final int sectionCount;
  final int measureCount;
  final bool chordScoringAvailable;
  final bool pitchScoringAvailable;
  final VoidCallback? onOpenTutor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const ValueKey('song-tutor-entry-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.aiTutorSongEntryTitle),
            const SizedBox(height: 8),
            Text(
              l10n.aiTutorSongEntryStructure(
                songTitle,
                sectionCount,
                measureCount,
              ),
            ),
            const SizedBox(height: 12),
            if (chordScoringAvailable)
              _CapabilityChip(
                key: const ValueKey('song-tutor-chord-action'),
                label: l10n.aiTutorSongChordAvailable,
              )
            else
              Text(l10n.aiTutorSongChordUnavailable),
            const SizedBox(height: 8),
            if (pitchScoringAvailable)
              _CapabilityChip(
                key: const ValueKey('song-tutor-pitch-action'),
                label: l10n.aiTutorSongPitchAvailable,
              )
            else
              Text(l10n.aiTutorSongPitchUnavailable),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('song-tutor-open'),
              onPressed: onOpenTutor,
              child: Text(l10n.aiTutorSongOpen),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: const Icon(Icons.check_circle_outline, size: 18),
    label: Text(label),
  );
}
