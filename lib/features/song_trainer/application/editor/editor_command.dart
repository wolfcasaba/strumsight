import '../../domain/models/song_document.dart';

/// A deterministic, reversible draft transition.
///
/// Commands carry immutable document snapshots rather than widget callbacks, so
/// undo and redo cannot observe later UI mutation.
abstract interface class EditorCommand {
  String get label;
  SongDocument get before;
  SongDocument get after;

  SongDocument apply(SongDocument current);
  SongDocument revert(SongDocument current);
}

/// Snapshot command used by the bounded editor history.
final class DocumentEditorCommand implements EditorCommand {
  const DocumentEditorCommand({
    required this.label,
    required this.before,
    required this.after,
  });

  @override
  final String label;
  @override
  final SongDocument before;
  @override
  final SongDocument after;

  @override
  SongDocument apply(SongDocument current) => after;

  @override
  SongDocument revert(SongDocument current) => before;
}
