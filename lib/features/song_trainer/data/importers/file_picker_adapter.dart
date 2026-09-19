import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'import_limits.dart';
import 'importer_registry.dart';
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

/// Platform boundary for choosing a BACKING-AUDIO file.
///
/// Deliberately a separate port from [FilePickerAdapter] (javító sáv
/// 2026-09-06, audit §5.2 "Hang-import folyamat"): the song-import flow must
/// not accept audio — no importer can parse it — and the backing-track
/// attachment must not accept notation. One picker with one accepted-type
/// list can only be right for one of the two, which is why the shipped
/// "Attach backing" button opened a notation-only picker and could never
/// actually import a backing track.
abstract interface class BackingAudioPickerAdapter {
  Future<ImportSourceFile?> pickBackingAudioFile();
}

/// Production adapter. Platform picker objects are converted immediately to
/// the reopenable [ImportSourceFile] contract and never reach widget state.
final class PlatformFilePickerAdapter
    implements FilePickerAdapter, BackingAudioPickerAdapter {
  const PlatformFilePickerAdapter({this.limits = const ImportLimits()});

  /// The source budget this boundary enforces. Injected so the picker and the
  /// [ImporterRegistry] in front of which it sits can share one limit object
  /// instead of each baking in its own default.
  ///
  /// The composition root (`songFilePickerAdapterProvider`) still builds this
  /// adapter with the default budget; passing `songImporterRegistryProvider`'s
  /// `limits` there is a one-line provider change that belongs to the
  /// application layer, which this data-boundary file does not own.
  final ImportLimits limits;

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
    return file == null ? null : await fromXFile(file, limits: limits);
  }

  /// The audio budget. Deliberately NOT [limits]: that 1 MiB ceiling sizes a
  /// NOTATION file, and an audio container is three orders of magnitude
  /// larger, so widening the shared profile would widen the sheet-import
  /// surface for no reason. Same number the audio import controller and the
  /// editor's backing attach enforce downstream
  /// ([maxAudioImportSourceBytes]), declared once.
  static const ImportLimits audioLimits = ImportLimits(
    maxSourceBytes: maxAudioImportSourceBytes,
  );

  @override
  Future<ImportSourceFile?> pickAudioFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[audioTypeGroup],
    );
    return file == null ? null : await fromXFile(file, limits: audioLimits);
  }

  /// [BackingAudioPickerAdapter] — the backing attachment offers exactly the
  /// audio group [pickAudioFile] offers, and enforces the same audio budget.
  /// The two ports stay separate so the NOTATION import can never be handed
  /// an audio container (audit §5.2), but there is only one audio type list.
  @override
  Future<ImportSourceFile?> pickBackingAudioFile() => pickAudioFile();

  /// Converts the plugin value at the data boundary. A readable stream is a
  /// mandatory privacy-preserving contract: paths and plugin objects do not
  /// escape to application or presentation state.
  ///
  /// Ownership note: the payload is buffered with `BytesBuilder(copy: false)`
  /// so an at-limit pick costs a single allocation, and the taken buffer is
  /// handed out only as an unmodifiable view. Every `openRead()` replays the
  /// same bytes, and a consumer cannot corrupt a later reopen by writing into
  /// them — the reopenable-source contract stays enforced, not merely promised.
  static Future<ImportSourceFile> fromXFile(
    XFile file, {
    ImportLimits limits = const ImportLimits(),
  }) async {
    final reportedLength = await file.length();
    if (reportedLength > limits.maxSourceBytes) {
      return _oversize(file, reportedLength);
    }
    final read = await _readStream(file.openRead(), limits.maxSourceBytes);
    final bytes = read.bytes;
    if (bytes == null) {
      // The stream outgrew its own `length()`. `seenBytes` is what the stream
      // actually delivered before the guard tripped: a measured lower bound on
      // the real size, which the shared limit check already rejects.
      return _oversize(file, read.seenBytes);
    }
    return ImportSourceFile(
      displayName: file.name,
      // The buffered payload is the authority, not `length()`: a
      // stream-backed pick can under-report, and every consumer reads what
      // `openRead()` replays.
      byteLength: bytes.length,
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

  /// Describes an oversize pick without holding its payload.
  ///
  /// [byteLength] is measured, never invented: either the length the platform
  /// reported, or the byte count the stream had already delivered when the
  /// guard tripped. Reading is then refused with the registry's own typed
  /// failure, so both consumers of a pick end at the same user-visible
  /// message:
  ///
  ///  * the import path — [ImporterRegistry] rejects the source on
  ///    [byteLength] alone, before anything calls `openRead()`;
  ///  * the song editor's backing attach — `openRead()` fails with
  ///    [ImportRegistryException] carrying
  ///    [ImportLimitFailureCode.sourceBytesExceeded], which
  ///    `SongEditorScreen._attachBacking` catches and reports.
  ///
  /// Yielding zero bytes instead would turn that second path into a silent
  /// no-op, so the refusal is explicit and typed.
  static ImportSourceFile _oversize(XFile file, int byteLength) =>
      ImportSourceFile(
        displayName: file.name,
        byteLength: byteLength,
        mimeType: mimeTypeOf(file.name),
        openRead: () => Stream<List<int>>.error(
          const ImportRegistryException(
            ImportLimitFailureCode.sourceBytesExceeded,
          ),
        ),
      );

  /// Buffers [stream] into a single payload. `bytes` is null as soon as the
  /// running total passes [maxBytes] — `length()` can lie for stream-backed
  /// picks, so the bytes themselves are the authority — and `seenBytes` then
  /// reports how much the stream had already delivered at that point.
  static Future<({Uint8List? bytes, int seenBytes})> _readStream(
    Stream<List<int>> stream,
    int maxBytes,
  ) async {
    final output = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      final total = output.length + chunk.length;
      if (total > maxBytes) return (bytes: null, seenBytes: total);
      output.add(chunk);
    }
    final length = output.length;
    return (bytes: output.takeBytes().asUnmodifiableView(), seenBytes: length);
  }

  @override
  Future<void> dispose() async {}
}
