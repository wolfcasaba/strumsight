import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/importers/export_filename_sanitizer.dart';
import 'package:strumsight/features/song_trainer/data/importers/native_json_exporter.dart';
import 'package:strumsight/features/song_trainer/data/importers/native_json_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';

void main() {
  const exporter = NativeJsonExporter();

  test(
    'exports deterministic envelope bytes with a value-identical asset manifest',
    () {
      final document = _document();

      final first = exporter.export(document);
      final second = exporter.export(document);
      final root = jsonDecode(utf8.decode(first.bytes)) as Map<String, dynamic>;
      final documentJson = root['document'] as Map<String, dynamic>;

      expect(first.bytes, second.bytes);
      expect(root['format'], nativeJsonFormat);
      expect(root['formatVersion'], nativeJsonFormatVersion);
      expect(root['assetManifest'], documentJson['assets']);
    },
  );

  test(
    'scrubs path-like provenance from both the exchange bytes and export filename',
    () {
      final document = _document(
        originalFileName: r'C:\private\temp\my:unsafe?.json',
      );

      final exported = exporter.export(document);
      final text = utf8.decode(exported.bytes);

      expect(text, isNot(contains(r'C:\private')));
      expect(exported.filename, 'my-unsafe.strumsight-song.json');
      expect(exported.filename, isNot(contains(RegExp(r'[<>:"/\\|?*]'))));
      expect(document.id.value, 'fixture-song');
    },
  );

  test(
    'round-trips a native export without changing document identity',
    () async {
      final original = _document();
      final exported = exporter.export(original);
      final result = await const NativeJsonImporter().import(
        ImportSourceFile(
          displayName: exported.filename,
          byteLength: exported.bytes.length,
          openRead: () => Stream<List<int>>.value(exported.bytes),
        ),
        const SongImportOptions(),
        const NeverCancelledToken(),
      );

      expect(result.valueOrNull?.document, original);
    },
  );

  test(
    'normalizes cross-platform unsafe names without changing the song id',
    () {
      expect(
        sanitizeNativeExportFilename(r'..\CON<>:"/a|b?*.json'),
        'a-b.strumsight-song.json',
      );
    },
  );
}

SongDocument _document({String originalFileName = 'fixture.json'}) =>
    SongDocument(
      schemaVersion: 1,
      id: SongId('fixture-song'),
      revision: 0,
      metadata: SongMetadata(title: 'Fixture full song'),
      source: SongSource(
        type: SongSourceType.strumSightJson,
        originalFileName: originalFileName,
        sha256: 'a' * 64,
        importedAt: DateTime.utc(2026, 8, 3),
        importerVersion: 'fixture@1',
      ),
      assets: <SongAssetReference>[
        SongAssetReference(
          id: SongAssetId('backing-audio'),
          sha256: 'b' * 64,
          extension: 'mp3',
          byteLength: 1234,
          mimeType: 'audio/mpeg',
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 3),
      updatedAt: DateTime.utc(2026, 8, 3),
    );
