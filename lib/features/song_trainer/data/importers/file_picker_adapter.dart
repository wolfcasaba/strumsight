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
  Future<ImportSourceFile?> pickSongFile();

  Future<void> dispose();
}

/// Production adapter. Platform picker objects are converted immediately to
/// the reopenable [ImportSourceFile] contract and never reach widget state.
final class PlatformFilePickerAdapter implements FilePickerAdapter {
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

  static const XTypeGroup _songTypeGroup = XTypeGroup(
    label: 'StrumSight song files',
    extensions: supportedExtensions,
  );

  @override
  Future<ImportSourceFile?> pickSongFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_songTypeGroup],
    );
    return file == null ? null : await fromXFile(file, limits: limits);
  }

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
      byteLength: bytes.length,
      mimeType: _extensionOf(file.name),
      // This closure belongs to the data boundary. SongImportState receives
      // only preview metadata, never the source payload or PlatformFile.
      openRead: () => Stream<List<int>>.value(bytes),
    );
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
        mimeType: _extensionOf(file.name),
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

  static String? _extensionOf(String name) {
    final separator = name.lastIndexOf('.');
    if (separator <= 0 || separator == name.length - 1) return null;
    return name.substring(separator + 1);
  }

  @override
  Future<void> dispose() async {}
}
