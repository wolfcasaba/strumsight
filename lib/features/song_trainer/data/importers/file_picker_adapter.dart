import 'package:file_selector/file_selector.dart';

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

  static const XTypeGroup _songTypeGroup = XTypeGroup(
    label: 'StrumSight song files',
    extensions: supportedExtensions,
  );

  @override
  Future<ImportSourceFile?> pickSongFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_songTypeGroup],
    );
    return file == null ? null : await fromXFile(file);
  }

  /// Converts the plugin value at the data boundary. A readable stream is a
  /// mandatory privacy-preserving contract: paths and plugin objects do not
  /// escape to application or presentation state.
  static Future<ImportSourceFile> fromXFile(XFile file) async {
    final bytes = await _readStream(file.openRead());
    return ImportSourceFile(
      displayName: file.name,
      byteLength: await file.length(),
      mimeType: _extensionOf(file.name),
      // This closure belongs to the data boundary. SongImportState receives
      // only preview metadata, never the source payload or PlatformFile.
      openRead: () => Stream<List<int>>.value(bytes),
    );
  }

  static Future<List<int>> _readStream(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return List<int>.unmodifiable(bytes);
  }

  static String? _extensionOf(String name) {
    final separator = name.lastIndexOf('.');
    if (separator <= 0 || separator == name.length - 1) return null;
    return name.substring(separator + 1);
  }

  @override
  Future<void> dispose() async {}
}
