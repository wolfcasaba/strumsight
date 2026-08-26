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
    super.key,
  });

  final SongSummary summary;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;
  final VoidCallback onExport;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey<String>('song-summary-${summary.documentId.value}'),
    title: Text(summary.title),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(summary.artist ?? summary.sourceType.code),
        const SizedBox(height: 4),
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
