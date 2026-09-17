import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/repositories/song_repository.dart';
import 'song_capability_badges.dart';
import 'song_source_badge.dart';

/// Card backed only by [SongSummary], never a decoded SongDocument.
final class SongSummaryTile extends StatelessWidget {
  const SongSummaryTile({
    required this.summary,
    required this.onDelete,
    required this.onFavorite,
    required this.onExport,
    required this.isFavorite,
    this.onPlay,
    super.key,
  });

  final SongSummary summary;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;
  final VoidCallback onExport;
  final bool isFavorite;

  /// Opens the trainer setup for this song (E16-R01/A2).
  ///
  /// The row's own tap keeps its measured meaning — it opens the editor for
  /// an editable song and the read-only overview otherwise
  /// (`song_library_test.dart` pins both) — so practising needed an
  /// affordance of its own. It sits in `leading`, not in the already-crowded
  /// trailing action row, so the 200% text-scale layout keeps its headroom.
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey<String>('song-summary-${summary.documentId.value}'),
    leading: IconButton(
      key: ValueKey<String>('song-play-${summary.documentId.value}'),
      icon: const Icon(Icons.play_arrow),
      onPressed: onPlay,
      tooltip: AppLocalizations.of(context).trainerSetupStart,
    ),
    title: Text(summary.title),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (summary.artist != null) ...<Widget>[
          Text(summary.artist!),
          const SizedBox(height: 4),
        ],
        SongSourceBadge(
          key: ValueKey<String>(
            'song-source-badge-${summary.documentId.value}',
          ),
          sourceType: summary.sourceType,
        ),
      ],
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          icon: Icon(isFavorite ? Icons.star : Icons.star_border),
          onPressed: onFavorite,
          tooltip: AppLocalizations.of(context).songFavorite,
        ),
        IconButton(
          icon: const Icon(Icons.ios_share_outlined),
          onPressed: onExport,
          tooltip: AppLocalizations.of(context).songLibraryExport,
        ),
        SongCapabilityBadges(summary: summary),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
          tooltip: AppLocalizations.of(context).songMoveToTrash,
        ),
      ],
    ),
  );
}
