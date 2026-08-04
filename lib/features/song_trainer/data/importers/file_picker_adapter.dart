import 'package:file_picker/file_picker.dart';

import 'song_importer.dart';

/// Platform boundary for choosing a reopenable source file.
///
/// Concrete picker plugins are intentionally deferred: this port keeps their
/// platform objects outside the application state and domain contracts.
abstract interface class FilePickerAdapter {
  Future<ImportSourceFile?> pickSongFile();

  Future<void> dispose();
}

/// Production adapter. Platform picker objects are converted immediately to
/// the reopenable [ImportSourceFile] contract and never reach widget state.
final class PlatformFilePickerAdapter implements FilePickerAdapter {
  const PlatformFilePickerAdapter();

  static const List<String> supportedExtensions = <String>[
    'json',
    'musicxml',
    'xml',
    'mxl',
    'mid',
    'midi',
  ];

  @override
  Future<ImportSourceFile?> pickSongFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
      withReadStream: true,
    );
    final file = result?.files.singleOrNull;
    return file == null ? null : await fromPlatformFile(file);
  }

  /// Converts the plugin value at the data boundary. A readable stream is a
  /// mandatory privacy-preserving contract: paths and plugin objects do not
  /// escape to application or presentation state.
  static Future<ImportSourceFile> fromPlatformFile(PlatformFile file) async {
    final bytes = file.bytes == null
        ? await _readStream(file.readStream)
        : List<int>.unmodifiable(file.bytes!);
    if (bytes == null) {
      throw StateError('filePicker.sourceUnavailable');
    }
    return ImportSourceFile(
      displayName: file.name,
      byteLength: file.size,
      mimeType: file.extension,
      // This closure belongs to the data boundary. SongImportState receives
      // only preview metadata, never the source payload or PlatformFile.
      openRead: () => Stream<List<int>>.value(bytes),
    );
  }

  static Future<List<int>?> _readStream(Stream<List<int>>? stream) async {
    if (stream == null) return null;
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return List<int>.unmodifiable(bytes);
  }

  @override
  Future<void> dispose() async {}
}
