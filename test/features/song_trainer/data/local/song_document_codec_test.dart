import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/local/song_document_codec.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_marker.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';

const _codec = SongDocumentCodec();

void main() {
  const codec = _codec;

  group('Round-trip identity', () {
    test('encodes a minimal document and decodes it back to value-equal', () {
      final original = _sample();
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded);
      expect(decoded, equals(original));
      expect(decoded, isA<SongDocument>());
    });

    test('preserves revision, schemaVersion, timestamps and identity', () {
      final original = _sample(revision: 7, schemaVersion: 1);
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded);
      expect(decoded.revision, original.revision);
      expect(decoded.schemaVersion, original.schemaVersion);
      expect(decoded.id, original.id);
      expect(
        decoded.createdAt.toUtc().toIso8601String(),
        original.createdAt.toUtc().toIso8601String(),
      );
      expect(
        decoded.updatedAt.toUtc().toIso8601String(),
        original.updatedAt.toUtc().toIso8601String(),
      );
    });

    test('preserves populated assets and markers in order', () {
      final original = _sample(
        assets: [
          SongAssetReference(
            id: SongAssetId('asset-1'),
            sha256: 'a' * 64,
            extension: 'mp3',
            byteLength: 1024,
            mimeType: 'audio/mpeg',
            durationMs: 200000,
          ),
        ],
        markers: [
          SongMarker(SongMarkerId('m-1'), 'Intro', 0, 'rehearsal'),
          SongMarker(SongMarkerId('m-2'), 'Verse 2', 16, 'note'),
        ],
      );
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded);
      expect(decoded.assets, equals(original.assets));
      expect(decoded.markers, equals(original.markers));
    });
  });

  group('Deterministic byte ordering', () {
    test('two consecutive encodes of the same document are byte-identical', () {
      final document = _sample();
      final a = codec.encode(document);
      final b = codec.encode(document);
      expect(utf8.decode(a), utf8.decode(b));
      expect(a, equals(b));
    });

    test(
      'two codec instances produce the same bytes for the same document',
      () {
        const codecB = SongDocumentCodec();
        final document = _sample();
        expect(codec.encode(document), equals(codecB.encode(document)));
      },
    );
  });

  group('UTC normalization', () {
    test('a non-UTC timestamp survives round-trip as the same instant', () {
      final local = DateTime.utc(2026, 1, 1, 12).toLocal();
      final original = _sample(
        createdAt: local,
        updatedAt: local.add(const Duration(hours: 1)),
      );
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded);
      expect(decoded.createdAt.toUtc(), original.createdAt.toUtc());
      expect(decoded.updatedAt.toUtc(), original.updatedAt.toUtc());
      // The decoded values must themselves be flagged as UTC.
      expect(decoded.createdAt.isUtc, isTrue);
      expect(decoded.updatedAt.isUtc, isTrue);
    });
  });

  group('Failure cases', () {
    test('decode fails fast on an unknown source type with a stable error', () {
      final raw = _encodeRawJson(_sample());
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final source = json['source'] as Map<String, dynamic>;
      source['type'] = 'not-a-source-type';
      final bytes = utf8.encode(jsonEncode(json));
      expect(
        () => codec.decode(bytes),
        throwsA(isA<SongDocumentCodecException>()),
      );
    });

    test('decode rejects an out-of-range schema version', () {
      final raw = _encodeRawJson(_sample());
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      json['schemaVersion'] = 0;
      final bytes = utf8.encode(jsonEncode(json));
      expect(
        () => codec.decode(bytes),
        throwsA(isA<SongDocumentCodecException>()),
      );
    });

    test('decode rejects an unknown schema version higher than supported', () {
      final raw = _encodeRawJson(_sample());
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      json['schemaVersion'] = SongDocumentCodec.supportedSchemaVersion + 1;
      final bytes = utf8.encode(jsonEncode(json));
      expect(
        () => codec.decode(bytes),
        throwsA(isA<SongDocumentCodecException>()),
      );
    });

    test('decode rejects a missing required top-level field', () {
      final raw = _encodeRawJson(_sample());
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      json.remove('id');
      final bytes = utf8.encode(jsonEncode(json));
      expect(
        () => codec.decode(bytes),
        throwsA(isA<SongDocumentCodecException>()),
      );
    });
  });

  group('Source provenance integrity', () {
    test('preserves all source fields across the codec boundary', () {
      final original = _sample(
        source: SongSource(
          type: SongSourceType.musicXml,
          originalFileName: 'Score.musicxml',
          sha256: 'f' * 64,
          importedAt: DateTime.utc(2026, 5, 1, 9),
          importerVersion: '0.4.2',
          formatVersion: '3.1',
          warningSummary: const ['unknown_element'],
          originalAssetId: SongAssetId('asset-original'),
        ),
      );
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded);
      expect(decoded.source, equals(original.source));
      expect(decoded.source.type, SongSourceType.musicXml);
      expect(decoded.source.originalFileName, 'Score.musicxml');
      expect(decoded.source.formatVersion, '3.1');
      expect(decoded.source.warningSummary, const ['unknown_element']);
      expect(decoded.source.originalAssetId, SongAssetId('asset-original'));
    });
  });
}

SongDocument _sample({
  int schemaVersion = 1,
  SongId? id,
  int revision = 1,
  SongMetadata? metadata,
  SongSource? source,
  List<SongAssetReference>? assets,
  List<SongMarker>? markers,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 1, 1, 12);
  final updated = updatedAt ?? DateTime.utc(2026, 1, 2, 12);
  return SongDocument(
    schemaVersion: schemaVersion,
    id: id ?? SongId('song-001'),
    revision: revision,
    metadata: metadata ?? SongMetadata(title: 'Wonderwall'),
    source: source ?? _sampleSource(),
    assets: assets ?? const <SongAssetReference>[],
    markers: markers ?? const <SongMarker>[],
    createdAt: created,
    updatedAt: updated,
  );
}

SongSource _sampleSource() => SongSource(
  type: SongSourceType.legacyLocal,
  originalFileName: 'song.json',
  sha256: 'a' * 64,
  importedAt: DateTime.utc(2026, 1, 1, 12),
  importerVersion: '1.0.0',
);

List<int> _encodeRawJson(SongDocument document) => _codec.encode(document);
