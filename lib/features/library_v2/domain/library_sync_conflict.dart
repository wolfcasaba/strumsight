/// Presentational sync-conflict model (§0.0/B3, §5.6, ADR 0277).
///
/// No sync-conflict storage type exists anywhere on the tree today — this is
/// `library_v2`'s own, UI-only model. Resolving a conflict never writes a
/// store from here: the screen only calls the caller-supplied [onResolve]
/// callback (L06 — a silent overwrite is never acceptable).
library;

/// The two choices a user has when a local and cloud copy disagree.
enum LibrarySyncResolution { keepLocal, keepRemote }

/// One item's local/remote disagreement, described so the user can choose
/// without either version silently vanishing.
final class LibrarySyncConflict {
  const LibrarySyncConflict({
    required this.itemId,
    required this.localDescription,
    required this.localUpdatedAt,
    required this.remoteDescription,
    required this.remoteUpdatedAt,
  });

  final String itemId;

  /// Human-readable summary of the local version (caller's l10n).
  final String localDescription;
  final DateTime localUpdatedAt;

  /// Human-readable summary of the remote version (caller's l10n).
  final String remoteDescription;
  final DateTime remoteUpdatedAt;
}
