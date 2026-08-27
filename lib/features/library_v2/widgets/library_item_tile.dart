import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/library_item.dart';

/// One row of the unified library list — dispatches on [LibraryItem]'s
/// runtime type so a corrupt source never crashes the tile and never renders
/// another type's content (A1, A2).
final class LibraryItemTile extends StatelessWidget {
  const LibraryItemTile({super.key, required this.item, required this.onTap});

  final LibraryItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = item;
    return switch (current) {
      CorruptLibraryItem(:final id) => ListTile(
        key: ValueKey('library-item-corrupt-$id'),
        leading: const Icon(Icons.error_outline),
        title: Text(l10n.libraryV2CorruptSourceTitle),
        subtitle: Text(l10n.libraryV2CorruptSourceMessage),
        onTap: onTap,
      ),
      AnalysisLibraryItem(:final id, :final title, :final syncStatus) =>
        ListTile(
          key: ValueKey('library-item-$id'),
          leading: const Icon(Icons.graphic_eq),
          title: Text(title),
          subtitle: Text(l10n.libraryV2TypeAnalysis),
          trailing: _syncBadge(context, l10n, syncStatus),
          onTap: onTap,
        ),
      PracticeLibraryItem(:final id, :final title, :final syncStatus) =>
        ListTile(
          key: ValueKey('library-item-$id'),
          leading: const Icon(Icons.fitness_center),
          title: Text(title),
          subtitle: Text(l10n.libraryV2TypePractice),
          trailing: _syncBadge(context, l10n, syncStatus),
          onTap: onTap,
        ),
      SongLibraryItem(
        :final id,
        :final title,
        :final artist,
        :final syncStatus,
      ) =>
        ListTile(
          key: ValueKey('library-item-$id'),
          leading: const Icon(Icons.music_note),
          title: Text(title),
          subtitle: Text(artist ?? l10n.libraryV2TypeSong),
          trailing: _syncBadge(context, l10n, syncStatus),
          onTap: onTap,
        ),
      SetlistLibraryItem(
        :final id,
        :final title,
        :final songCount,
        :final syncStatus,
      ) =>
        ListTile(
          key: ValueKey('library-item-$id'),
          leading: const Icon(Icons.queue_music),
          title: Text(title),
          subtitle: Text(l10n.setlistV2ItemCount(songCount)),
          trailing: _syncBadge(context, l10n, syncStatus),
          onTap: onTap,
        ),
    };
  }

  Widget? _syncBadge(
    BuildContext context,
    AppLocalizations l10n,
    LibrarySyncStatus status,
  ) {
    final badge = switch (status) {
      LibrarySyncStatus.offline => SsStatusBadge(
        l10n: l10n,
        kind: SsStatusBadgeKind.offline,
      ),
      LibrarySyncStatus.pending => SsStatusBadge(
        l10n: l10n,
        kind: SsStatusBadgeKind.syncPending,
      ),
      LibrarySyncStatus.conflict => Icon(
        Icons.warning_amber,
        color: Theme.of(context).colorScheme.error,
        semanticLabel: l10n.libraryV2SyncConflictBadge,
      ),
      LibrarySyncStatus.synced => null,
    };
    // ListTile's trailing slot loosens the tile's own width into the
    // trailing widget's constraints; SsStatusBadge's internal Flexible then
    // reports that whole width back as its own (a well-known Flex/Flexible
    // + intrinsic-sizing interaction), which ListTile rejects as "consumes
    // the entire tile width". A concrete max width avoids the exact-equality
    // trap regardless of the tile's own width.
    return badge == null
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: badge,
          );
  }
}
