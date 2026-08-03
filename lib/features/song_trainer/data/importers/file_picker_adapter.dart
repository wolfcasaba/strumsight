import 'song_importer.dart';

/// Platform boundary for choosing a reopenable source file.
///
/// Concrete picker plugins are intentionally deferred: this port keeps their
/// platform objects outside the application state and domain contracts.
abstract interface class FilePickerAdapter {
  Future<ImportSourceFile?> pickSongFile();

  Future<void> dispose();
}
