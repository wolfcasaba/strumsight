import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

final class _SchemaSnapshot {
  const _SchemaSnapshot({
    required this.path,
    required this.startMarker,
    required this.sha256,
  });

  final String path;
  final String startMarker;
  final String sha256;
}

const _snapshots = <_SchemaSnapshot>[
  _SchemaSnapshot(
    path: 'lib/features/song_trainer/data/local/song_document_codec.dart',
    startMarker: 'class SongDocumentCodec {',
    sha256: '9395dc1a63c401eb751b5324b4715b7dc306e47d22e1be093cd5c7e158f92ae6',
  ),
  _SchemaSnapshot(
    path: 'lib/features/song_trainer/data/local/song_index_codec.dart',
    startMarker: 'class SongIndexCodec {',
    sha256: '5efea1974a8e483957c839e3a1a6920e889cd43cddd7557939d4546249196cc7',
  ),
  _SchemaSnapshot(
    path: 'lib/features/song_trainer/data/importers/native_json_exporter.dart',
    startMarker: 'final class NativeJsonExporter {',
    sha256: 'c276bcb322dde9d8fec2e8329b903fbeb254a2d5daee5506ce1b302db36fc08b',
  ),
  _SchemaSnapshot(
    path: 'lib/features/song_trainer/data/importers/native_json_importer.dart',
    startMarker: 'final class NativeJsonImporter implements SongImporter {',
    sha256: '00851e5ed8f0e2cf9a3d3171ea2db0a339f10b7f016ad4083394f1d1abb54b29',
  ),
  _SchemaSnapshot(
    path: 'lib/features/song_trainer/data/local/file_setlist_repository.dart',
    startMarker: 'List<SongSetlist> _decodeSetlists',
    sha256: '2c45fa6212e0708e4d76883487ae38a9d437c9915e4022be423b153678bf1a82',
  ),
  _SchemaSnapshot(
    path:
        'lib/features/song_trainer/data/local/file_song_progress_repository.dart',
    startMarker: 'List<SongPracticeRecord> _decodeRecords',
    sha256: 'f9e7d4c7fafbebc40e5875bd0e79a6a1883ad8477094aec5c9052b33b4917c35',
  ),
];

Future<List<String>> _schemaDrift(Directory root) async {
  final drift = <String>[];
  for (final snapshot in _snapshots) {
    final file = File('${root.path}${Platform.pathSeparator}${snapshot.path}');
    if (!await file.exists()) {
      drift.add('${snapshot.path}: missing schema source');
      continue;
    }
    final actual = sha256
        .convert(
          utf8.encode(
            _schemaSlice(await file.readAsString(), snapshot.startMarker),
          ),
        )
        .toString();
    if (actual != snapshot.sha256) {
      drift.add('${snapshot.path}: schema snapshot differs');
    }
  }
  return drift;
}

String _schemaSlice(String source, String startMarker) {
  final start = source.indexOf(startMarker);
  if (start < 0) {
    throw FormatException('Schema start marker is missing: $startMarker');
  }
  return source.substring(start);
}

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/ci/check_song_schema.dart');
    exitCode = 64;
    return;
  }
  final drift = await _schemaDrift(Directory.current);
  if (drift.isEmpty) {
    stdout.writeln(
      'Song schema snapshot OK (${_snapshots.length} persisted schema sources).',
    );
    return;
  }
  stderr
    ..writeln('Song schema snapshot failed.')
    ..writeAll(drift.map((entry) => '- $entry\n'));
  exitCode = 1;
}
