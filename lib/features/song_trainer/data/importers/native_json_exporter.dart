import 'dart:convert';

import '../local/song_document_codec.dart';
import '../../domain/models/song_document.dart';
import 'export_filename_sanitizer.dart';

/// Content marker required at the root of every native exchange file.
const String nativeJsonFormat = 'strumsight-song';

/// Version of the exchange envelope, independent from document schema.
const int nativeJsonFormatVersion = 2;

/// Deterministic native exchange artifact kept entirely in memory.
final class NativeJsonExport {
  NativeJsonExport({required List<int> bytes, required this.filename})
    : bytes = List<int>.unmodifiable(bytes);

  final List<int> bytes;
  final String filename;
}

/// Builds the versioned, privacy-scrubbed native JSON exchange envelope.
final class NativeJsonExporter {
  const NativeJsonExporter({this.codec = const SongDocumentCodec()});

  final SongDocumentCodec codec;

  NativeJsonExport export(SongDocument document) {
    final documentJson = codec.encodeToMap(document);
    final source = Map<String, dynamic>.from(
      documentJson['source'] as Map<String, dynamic>,
    );
    source['originalFileName'] = scrubNativeSourceDisplayName(
      document.source.originalFileName,
    );
    documentJson['source'] = source;

    final root = <String, dynamic>{
      'format': nativeJsonFormat,
      'formatVersion': nativeJsonFormatVersion,
      'document': documentJson,
      'assetManifest': documentJson['assets'],
    };
    return NativeJsonExport(
      bytes: utf8.encode(jsonEncode(root)),
      filename: sanitizeNativeExportFilename(document.source.originalFileName),
    );
  }
}
