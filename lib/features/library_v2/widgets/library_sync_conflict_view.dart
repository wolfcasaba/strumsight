import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/library_sync_conflict.dart';

/// Presents both versions of a [LibrarySyncConflict] and lets the user pick
/// one — never a silent overwrite (§5.6, L06). Resolving calls [onResolve]
/// exactly once; this widget never touches storage itself (§0.0/B3).
final class LibrarySyncConflictView extends StatelessWidget {
  const LibrarySyncConflictView({
    super.key,
    required this.conflict,
    required this.onResolve,
  });

  final LibrarySyncConflict conflict;
  final ValueChanged<LibrarySyncResolution> onResolve;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsSection(
      title: l10n.libraryV2SyncConflictTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.libraryV2SyncConflictMessage),
          const SizedBox(height: 12),
          Card(
            key: const ValueKey('library-sync-conflict-local'),
            child: ListTile(
              title: Text(l10n.libraryV2SyncConflictLocalLabel),
              subtitle: Text(conflict.localDescription),
              trailing: FilledButton(
                key: const ValueKey('library-sync-conflict-keep-local'),
                onPressed: () => onResolve(LibrarySyncResolution.keepLocal),
                child: Text(l10n.libraryV2SyncConflictKeepThis),
              ),
            ),
          ),
          Card(
            key: const ValueKey('library-sync-conflict-remote'),
            child: ListTile(
              title: Text(l10n.libraryV2SyncConflictRemoteLabel),
              subtitle: Text(conflict.remoteDescription),
              trailing: FilledButton(
                key: const ValueKey('library-sync-conflict-keep-remote'),
                onPressed: () => onResolve(LibrarySyncResolution.keepRemote),
                child: Text(l10n.libraryV2SyncConflictKeepThis),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
