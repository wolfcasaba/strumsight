import 'package:file_selector/file_selector.dart';

import 'song_importer.dart';

/// Platform boundary for choosing a reopenable source file.
///
/// Concrete picker plugins are intentionally deferred: this port keeps their
/// platform objects outside the application state and domain contracts.
abstract interface class FilePickerAdapter {
  /// Picks a notation source (native JSON, MusicXML, MXL, MIDI) for the
  /// import flow.
  Future<ImportSourceFile?> pickSongFile();

  /// Picks a backing-audio container for the editor's attach flow. A
  /// separate method — not a widened [pickSongFile] — so the import sheet's
  /// accepted type set stays exactly the notation set.
  Future<ImportSourceFile?> pickAudioFile();

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

  /// Backing-audio containers the editor may attach. Every entry is played
  /// by the on-device player's Android backend; `supportedBackingAudioFormats`
  /// is the playback-side mirror of this list and documents the iOS caveat.
  static const List<String> supportedAudioExtensions = <String>[
    'mp3',
    'm4a',
    'mp4',
    'aac',
    'ogg',
    'flac',
    'wav',
  ];

  /// Extension → stored MIME type.
  ///
  /// `m4a` and `mp4` both map to `audio/mp4`: the audio picker ALSO offers
  /// `video/mp4` (Android SAF frequently reports that type for an MPEG-4
  /// container carrying only audio), but the app never plays a video
  /// stream, so the stored asset documents the audio type for both.
  static const Map<String, String> mimeTypesByExtension = <String, String>{
    'json': 'application/json',
    'musicxml': 'application/vnd.recordare.musicxml+xml',
    'xml': 'application/xml',
    'mxl': 'application/vnd.recordare.musicxml',
    'mid': 'audio/midi',
    'midi': 'audio/midi',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'mp4': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'flac': 'audio/flac',
    'wav': 'audio/wav',
  };

  static const XTypeGroup _songTypeGroup = XTypeGroup(
    label: 'StrumSight song files',
    extensions: supportedExtensions,
  );

  /// The audio group lists MIME types next to the extensions because the
  /// Android document picker filters on the MIME type it resolved for the
  /// file, not on its name — an `.m4a` frequently arrives as `video/mp4`.
  static const XTypeGroup audioTypeGroup = XTypeGroup(
    label: 'StrumSight backing audio',
    extensions: supportedAudioExtensions,
    mimeTypes: <String>[
      'audio/mpeg',
      'audio/mp4',
      'video/mp4',
      'audio/aac',
      'audio/ogg',
      'audio/flac',
      'audio/wav',
      'audio/x-wav',
    ],
  );

  @override
  Future<ImportSourceFile?> pickSongFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_songTypeGroup],
    );
    return file == null ? null : await fromXFile(file);
  }

  @override
  Future<ImportSourceFile?> pickAudioFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[audioTypeGroup],
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
      mimeType: mimeTypeOf(file.name, reported: file.mimeType),
      // This closure belongs to the data boundary. SongImportState receives
      // only preview metadata, never the source payload or PlatformFile.
      openRead: () => Stream<List<int>>.value(bytes),
    );
  }

  /// Resolves the MIME type stored for [name].
  ///
  /// The extension wins over [reported]: the platform value is unreliable
  /// (SAF reports `video/mp4` for audio-only MPEG-4 containers, and
  /// `application/octet-stream` for anything it fails to sniff), while the
  /// extension is exactly what the picker filtered on. `mimeType` carries a
  /// REAL media type — it used to carry the bare extension, which no
  /// decoder could consume. Callers needing the extension itself derive it
  /// from `displayName`, so [ImportSourceFile] gains no second field.
  static String? mimeTypeOf(String name, {String? reported}) {
    final extension = extensionOf(name);
    final mapped = extension == null ? null : mimeTypesByExtension[extension];
    if (mapped != null) return mapped;
    return reported == null || reported.isEmpty ? null : reported;
  }

  /// Lower-case extension of [name] without the dot; `null` when the name
  /// carries none.
  static String? extensionOf(String name) {
    final separator = name.lastIndexOf('.');
    if (separator <= 0 || separator == name.length - 1) return null;
    return name.substring(separator + 1).toLowerCase();
  }

  static Future<List<int>> _readStream(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return List<int>.unmodifiable(bytes);
  }

  @override
  Future<void> dispose() async {}
}
