import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_marker.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';

void main() {
  group('SongDocument construction', () {
    test('rejects a negative schema version', () {
      expect(
        () => _sample(schemaVersion: -1),
        throwsA(isA<SongDocumentValidationException>()),
      );
    });

    test('rejects a negative revision', () {
      expect(
        () => _sample(revision: -1),
        throwsA(isA<SongDocumentValidationException>()),
      );
    });

    test('requires createdAt to be a valid date', () {
      // A custom DateTime with arbitrary fields can be supplied, but the
      // validation must run on every path.
      final document = _sample();
      expect(document.createdAt.isBefore(document.updatedAt), isTrue);
    });

    test('rejects createdAt after updatedAt', () {
      final later = DateTime.utc(2026, 1, 2, 12);
      final earlier = DateTime.utc(2026, 1, 1, 12);
      expect(
        () => _sample(createdAt: later, updatedAt: earlier),
        throwsA(isA<SongDocumentValidationException>()),
      );
    });

    test('rejects negative revisions and out-of-range schema versions', () {
      expect(
        () => _sample(revision: -5),
        throwsA(isA<SongDocumentValidationException>()),
      );
      expect(
        () => _sample(schemaVersion: 0),
        throwsA(isA<SongDocumentValidationException>()),
      );
    });
  });

  group('SongDocument immutability', () {
    test('markers, assets and ids are wrapped as unmodifiable views', () {
      final document = _sample(
        markers: [SongMarker(SongMarkerId('intro'), 'Intro', 0, 'note')],
        assets: [
          SongAssetReference(
            id: SongAssetId('asset-1'),
            sha256: 'a' * 64,
            extension: 'mp3',
            byteLength: 100,
          ),
        ],
      );
      expect(document.markers, isNotNull);
      expect(document.assets, isNotNull);
      expect(
        () => (document.markers as List).add(_sampleMarker()),
        throwsUnsupportedError,
      );
      expect(
        () => (document.assets as List).add(_sampleAsset()),
        throwsUnsupportedError,
      );
    });
  });

  group('SongDocument equality and hashing', () {
    test('value-equal documents compare equal and share a hash', () {
      final a = _sample();
      final b = _sample();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('revision difference breaks equality', () {
      final a = _sample();
      final b = _sample(revision: a.revision + 1);
      expect(a, isNot(equals(b)));
    });

    test('id difference breaks equality', () {
      final a = _sample();
      final b = _sample(id: SongId('different'));
      expect(a, isNot(equals(b)));
    });
  });

  group('SongMetadata validation', () {
    test('rejects empty title', () {
      expect(
        () => SongMetadata(title: ''),
        throwsA(isA<SongMetadataValidationException>()),
      );
    });

    test('trims a whitespace-padded title', () {
      final m = SongMetadata(title: '  Wonderwall  ');
      expect(m.title, 'Wonderwall');
    });

    test('rejects a whitespace-only title', () {
      expect(
        () => SongMetadata(title: '   '),
        throwsA(isA<SongMetadataValidationException>()),
      );
    });

    test('rejects an over-long title', () {
      final title = 'a' * (SongMetadata.maxTitleLength + 1);
      expect(
        () => SongMetadata(title: title),
        throwsA(isA<SongMetadataValidationException>()),
      );
    });

    test('rejects a negative capo fret', () {
      expect(
        () => SongMetadata(title: 't', defaultCapo: -1),
        throwsA(isA<SongMetadataValidationException>()),
      );
    });

    test('rejects a capo fret above the documented maximum', () {
      expect(
        () => SongMetadata(title: 't', defaultCapo: SongMetadata.maxCapo + 1),
        throwsA(isA<SongMetadataValidationException>()),
      );
    });

    test('tags are trimmed, deduplicated and case-normalized', () {
      final m = SongMetadata(title: 't', tags: ['Rock', 'rock', '  pop  ', '']);
      expect(m.tags, ['rock', 'pop']);
    });

    test('tags beyond the documented limit are rejected', () {
      final tags = List<String>.generate(
        SongMetadata.maxTagCount + 1,
        (i) => 'tag-$i',
      );
      expect(
        () => SongMetadata(title: 't', tags: tags),
        throwsA(isA<SongMetadataValidationException>()),
      );
    });

    test('over-long individual tags are rejected', () {
      expect(
        () => SongMetadata(title: 't', tags: ['a' * 100]),
        throwsA(isA<SongMetadataValidationException>()),
      );
    });

    test('metadata collections are exposed as unmodifiable views', () {
      final m = SongMetadata(title: 't', tags: const ['rock', 'pop']);
      expect(() => (m.tags as List).add('extra'), throwsUnsupportedError);
    });
  });

  group('SongSource validation', () {
    test('requires a recognized type code', () {
      expect(
        () => SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: '',
          sha256: 'a' * 64,
          importedAt: DateTime.utc(2026),
          importerVersion: '1.0.0',
        ),
        throwsA(isA<SongSourceValidationException>()),
      );
    });

    test('requires a sha256 of exactly 64 lowercase hex characters', () {
      expect(
        () => SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'song.json',
          sha256: 'short',
          importedAt: DateTime.utc(2026),
          importerVersion: '1.0.0',
        ),
        throwsA(isA<SongSourceValidationException>()),
      );
      expect(
        () => SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'song.json',
          sha256: ('A' * 64),
          importedAt: DateTime.utc(2026),
          importerVersion: '1.0.0',
        ),
        throwsA(isA<SongSourceValidationException>()),
      );
    });

    test('requires a non-empty importer version', () {
      expect(
        () => SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'song.json',
          sha256: 'a' * 64,
          importedAt: DateTime.utc(2026),
          importerVersion: '',
        ),
        throwsA(isA<SongSourceValidationException>()),
      );
    });

    test('round-trips every source type through its stable code', () {
      for (final value in SongSourceType.values) {
        final resolved = songSourceTypeFromCode(value.code);
        expect(resolved, same(value));
      }
    });
  });

  group('SongAssetReference validation', () {
    test('rejects an asset with an empty extension', () {
      expect(
        () => SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'a' * 64,
          extension: '',
          byteLength: 100,
        ),
        throwsA(isA<SongAssetReferenceValidationException>()),
      );
    });

    test('rejects an asset with a negative byte length', () {
      expect(
        () => SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'a' * 64,
          extension: 'mp3',
          byteLength: -1,
        ),
        throwsA(isA<SongAssetReferenceValidationException>()),
      );
    });

    test('rejects an asset with a malformed sha256', () {
      expect(
        () => SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'not-hex',
          extension: 'mp3',
          byteLength: 100,
        ),
        throwsA(isA<SongAssetReferenceValidationException>()),
      );
    });
  });

  group('SongMarker validation', () {
    test('rejects a marker with an empty label', () {
      expect(
        () => SongMarker(SongMarkerId('m1'), '', 0, 'note'),
        throwsA(isA<SongMarkerValidationException>()),
      );
    });

    test('rejects a marker with an unknown kind', () {
      expect(
        () => SongMarker(SongMarkerId('m1'), 'Intro', 0, 'wat'),
        throwsA(isA<SongMarkerValidationException>()),
      );
    });

    test('accepts a fully populated marker', () {
      final m = SongMarker(SongMarkerId('m1'), 'Intro', 16, 'rehearsal');
      expect(m.label, 'Intro');
      expect(m.measureIndex, 16);
      expect(m.kind, 'rehearsal');
    });
  });

  group('Domain purity', () {
    test(
      'song_trainer domain has no framework, storage, or cross-feature imports',
      () {
        final domainDirectory = Directory('lib/features/song_trainer/domain');
        expect(domainDirectory.existsSync(), isTrue);

        final sourceFiles =
            domainDirectory
                .listSync(recursive: true, followLinks: false)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart'))
                .toList()
              ..sort((left, right) => left.path.compareTo(right.path));
        final violations = <String>[];

        for (final file in sourceFiles) {
          violations.addAll(
            _findPurityViolations(file.path, file.readAsStringSync()),
          );
        }

        expect(
          violations,
          isEmpty,
          reason:
              'song_trainer domain purity violations:\n${violations.join('\n')}',
        );
      },
    );

    test('purity scan ignores forbidden spellings in comments and strings', () {
      const source = r'''
/// Documentation may explain why DateTime.now() is forbidden.
const wallClockExample = 'DateTime.now()';
const importExample = "import 'package:flutter/material.dart';";
''';

      expect(_findPurityViolations('memory.dart', source), isEmpty);
    });
  });
  group('Exception toString coverage', () {
    test('SongIdValidationException toString includes a truncated snippet', () {
      try {
        SongId('a' * 200);
      } catch (e) {
        expect(e.toString(), contains('songId.tooLong'));
        expect(e.toString(), contains('value: '));
        return;
      }
      fail('expected SongIdValidationException');
    });

    test('SongIdValidationException toString handles short values', () {
      try {
        SongId('');
      } catch (e) {
        expect(e.toString(), contains('songId.empty'));
        return;
      }
      fail('expected SongIdValidationException');
    });

    test('SongDocumentValidationException toString exposes the code', () {
      try {
        _sample(schemaVersion: 0);
      } catch (e) {
        expect(e.toString(), contains('songDocument.schemaVersion.outOfRange'));
        return;
      }
      fail('expected SongDocumentValidationException');
    });

    test('SongMetadataValidationException toString exposes the code', () {
      try {
        SongMetadata(title: '');
      } catch (e) {
        expect(e.toString(), contains('songMetadata.title.empty'));
        return;
      }
      fail('expected SongMetadataValidationException');
    });

    test('SongSourceValidationException toString exposes the code', () {
      try {
        SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: '',
          sha256: 'a' * 64,
          importedAt: DateTime.utc(2026),
          importerVersion: '1.0.0',
        );
      } catch (e) {
        expect(e.toString(), contains('songSource.originalFileName.empty'));
        return;
      }
      fail('expected SongSourceValidationException');
    });

    test('SongAssetReferenceValidationException toString exposes the code', () {
      try {
        SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'a' * 64,
          extension: '',
          byteLength: 100,
        );
      } catch (e) {
        expect(e.toString(), contains('songAssetReference.extension.empty'));
        return;
      }
      fail('expected SongAssetReferenceValidationException');
    });

    test('SongMarkerValidationException toString exposes the code', () {
      try {
        SongMarker(SongMarkerId('m1'), 'Intro', 0, 'wat');
      } catch (e) {
        expect(e.toString(), contains('songMarker.kind.unknown'));
        return;
      }
      fail('expected SongMarkerValidationException');
    });
  });

  group('Additional validation paths', () {
    test('SongDocument rejects more assets than the documented maximum', () {
      final assets = List<SongAssetReference>.generate(
        maxSongDocumentAssetCount + 1,
        (i) => SongAssetReference(
          id: SongAssetId('asset-$i'),
          sha256: 'a' * 64,
          extension: 'mp3',
          byteLength: 1,
        ),
      );
      expect(
        () => _sample(assets: assets),
        throwsA(isA<SongDocumentValidationException>()),
      );
    });

    test('SongDocument rejects more markers than the documented maximum', () {
      final markers = List<SongMarker>.generate(
        maxSongDocumentMarkerCount + 1,
        (i) => SongMarker(SongMarkerId('m-$i'), 'Marker', i, 'note'),
      );
      expect(
        () => _sample(markers: markers),
        throwsA(isA<SongDocumentValidationException>()),
      );
    });

    test('SongMetadata rejects an over-long copyright string', () {
      expect(
        () => SongMetadata(
          title: 't',
          copyright: 'a' * (SongMetadata.maxTextLength + 1),
        ),
        throwsA(isA<SongMetadataValidationException>()),
      );
    });

    test('SongSource rejects an empty format version', () {
      expect(
        () => SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'song.json',
          sha256: 'a' * 64,
          importedAt: DateTime.utc(2026),
          importerVersion: '1.0.0',
          formatVersion: '   ',
        ),
        throwsA(isA<SongSourceValidationException>()),
      );
    });

    test('SongSource rejects an over-long warning summary', () {
      final warnings = List<String>.generate(
        maxSongSourceWarningCount + 1,
        (i) => 'warning-$i',
      );
      expect(
        () => SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'song.json',
          sha256: 'a' * 64,
          importedAt: DateTime.utc(2026),
          importerVersion: '1.0.0',
          warningSummary: warnings,
        ),
        throwsA(isA<SongSourceValidationException>()),
      );
    });

    test('SongSource rejects an empty warning summary entry', () {
      expect(
        () => SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'song.json',
          sha256: 'a' * 64,
          importedAt: DateTime.utc(2026),
          importerVersion: '1.0.0',
          warningSummary: const [''],
        ),
        throwsA(isA<SongSourceValidationException>()),
      );
    });

    test('SongSource rejects an over-long warning summary entry', () {
      expect(
        () => SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'song.json',
          sha256: 'a' * 64,
          importedAt: DateTime.utc(2026),
          importerVersion: '1.0.0',
          warningSummary: ['a' * (maxSongSourceWarningEntryLength + 1)],
        ),
        throwsA(isA<SongSourceValidationException>()),
      );
    });

    test('SongAssetReference rejects an over-long extension', () {
      expect(
        () => SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'a' * 64,
          extension: 'a' * 17,
          byteLength: 100,
        ),
        throwsA(isA<SongAssetReferenceValidationException>()),
      );
    });

    test('SongAssetReference rejects an extension with invalid characters', () {
      expect(
        () => SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'a' * 64,
          extension: 'MP3',
          byteLength: 100,
        ),
        throwsA(isA<SongAssetReferenceValidationException>()),
      );
    });

    test('SongAssetReference rejects an over-long mime type', () {
      expect(
        () => SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'a' * 64,
          extension: 'mp3',
          byteLength: 100,
          mimeType: 'a' * 129,
        ),
        throwsA(isA<SongAssetReferenceValidationException>()),
      );
    });

    test('SongAssetReference rejects a negative duration', () {
      expect(
        () => SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'a' * 64,
          extension: 'mp3',
          byteLength: 100,
          durationMs: -1,
        ),
        throwsA(isA<SongAssetReferenceValidationException>()),
      );
    });

    test('SongAssetReference rejects an over-large duration', () {
      expect(
        () => SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'a' * 64,
          extension: 'mp3',
          byteLength: 100,
          durationMs: maxSongAssetDurationMs + 1,
        ),
        throwsA(isA<SongAssetReferenceValidationException>()),
      );
    });

    test('SongAssetReference rejects an over-large byte length', () {
      expect(
        () => SongAssetReference(
          id: SongAssetId('asset-1'),
          sha256: 'a' * 64,
          extension: 'mp3',
          byteLength: maxSongAssetByteLength + 1,
        ),
        throwsA(isA<SongAssetReferenceValidationException>()),
      );
    });

    test('SongMarker rejects an over-long label', () {
      expect(
        () => SongMarker(
          SongMarkerId('m1'),
          'a' * (maxSongMarkerLabelLength + 1),
          0,
          'note',
        ),
        throwsA(isA<SongMarkerValidationException>()),
      );
    });

    test('SongMarker rejects a negative measure index', () {
      expect(
        () => SongMarker(SongMarkerId('m1'), 'Intro', -1, 'note'),
        throwsA(isA<SongMarkerValidationException>()),
      );
    });

    test('SongMarker rejects an over-large measure index', () {
      expect(
        () => SongMarker(
          SongMarkerId('m1'),
          'Intro',
          maxSongMarkerMeasureIndex + 1,
          'note',
        ),
        throwsA(isA<SongMarkerValidationException>()),
      );
    });

    test('SongMarker rejects over-long notes', () {
      expect(
        () => SongMarker(
          SongMarkerId('m1'),
          'Intro',
          0,
          'note',
          notes: 'a' * (maxSongMarkerNotesLength + 1),
        ),
        throwsA(isA<SongMarkerValidationException>()),
      );
    });
  });

  group('SongId fallback path', () {
    test('toString exposes the runtime type short name', () {
      final id = SongId('song-001');
      expect(id.toString(), contains('SongId'));
      expect(id.toString(), contains('song-001'));
    });

    test('hashCode combines runtimeType and value', () {
      final id = SongId('song-001');
      final expected = Object.hash(SongId, 'song-001');
      expect(id.hashCode, expected);
    });
  });
}

// Helpers ---------------------------------------------------------------------

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

SongMarker _sampleMarker() =>
    SongMarker(SongMarkerId('m-x'), 'Outro', 32, 'note');

SongAssetReference _sampleAsset() => SongAssetReference(
  id: SongAssetId('asset-x'),
  sha256: 'b' * 64,
  extension: 'wav',
  byteLength: 100,
);

final _forbiddenPatterns = <String, RegExp>{
  'ambient wall clock': RegExp(r'\bDateTime\s*\.\s*now\s*\('),
  'ambient stopwatch': RegExp(r'\bStopwatch\s*\('),
  'ambient randomness': RegExp(r'\bRandom(?:\s*\.\s*secure)?\s*\('),
  'console output': RegExp(r'\bprint\s*\('),
  'framework or storage import': RegExp(
    r'''import\s+['"]package:(?:flutter(?:/|_)|[^/'"]*riverpod[^/'"]*/|dio/|shared_preferences/)''',
  ),
  'localization import': RegExp(r'''import\s+['"][^'"]*l10n(?:/|\.dart)'''),
  'cross-feature import': RegExp(
    r'''import\s+['"]package:strumsight/features/(?:practice|songs|streak|auth|settings|progress|metronome|diagnostics|share|learn|onboarding|library|chords|tuner|analyze|live)/''',
  ),
};

List<String> _findPurityViolations(String path, String source) {
  final codeMask = _sourceCodeMask(source);
  final violations = <String>[];
  for (final entry in _forbiddenPatterns.entries) {
    for (final match in entry.value.allMatches(source)) {
      if (!codeMask[match.start]) continue;
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      violations.add('$path:$line: ${entry.key}');
    }
  }
  return violations;
}

List<bool> _sourceCodeMask(String source) {
  final codeMask = List<bool>.filled(source.length, true);
  var index = 0;
  while (index < source.length) {
    final lineCommentEnd = _lineCommentEnd(source, index);
    if (lineCommentEnd != null) {
      _maskRange(codeMask, index, lineCommentEnd);
      index = lineCommentEnd;
      continue;
    }
    final blockCommentEnd = _blockCommentEnd(source, index);
    if (blockCommentEnd != null) {
      _maskRange(codeMask, index, blockCommentEnd);
      index = blockCommentEnd;
      continue;
    }

    final stringLiteral = _scanStringLiteral(source, index);
    if (stringLiteral != null) {
      _maskRange(codeMask, index, stringLiteral.end);
      for (final interpolation in stringLiteral.interpolations) {
        final interpolationMask = _sourceCodeMask(
          source.substring(interpolation.start, interpolation.end),
        );
        for (var offset = 0; offset < interpolationMask.length; offset++) {
          codeMask[interpolation.start + offset] = interpolationMask[offset];
        }
      }
      index = stringLiteral.end;
      continue;
    }

    index++;
  }
  return codeMask;
}

int? _lineCommentEnd(String source, int start) {
  if (!source.startsWith('//', start)) return null;
  var index = start + 2;
  while (index < source.length && source[index] != '\n') {
    index++;
  }
  return index;
}

int? _blockCommentEnd(String source, int start) {
  if (!source.startsWith('/*', start)) return null;
  var depth = 1;
  var index = start + 2;
  while (index < source.length && depth > 0) {
    if (source.startsWith('/*', index)) {
      depth++;
      index += 2;
    } else if (source.startsWith('*/', index)) {
      depth--;
      index += 2;
    } else {
      index++;
    }
  }
  return index;
}

_StringLiteralScan? _scanStringLiteral(String source, int start) {
  var quoteIndex = start;
  var raw = false;
  if (source[start] == 'r' &&
      start + 1 < source.length &&
      (source[start + 1] == "'" || source[start + 1] == '"')) {
    raw = true;
    quoteIndex++;
  }
  if (source[quoteIndex] != "'" && source[quoteIndex] != '"') return null;

  final quote = source[quoteIndex];
  final triple = source.startsWith('$quote$quote$quote', quoteIndex);
  final delimiter = triple ? '$quote$quote$quote' : quote;
  final interpolations = <_SourceRange>[];
  var index = quoteIndex + delimiter.length;
  while (index < source.length) {
    if (source.startsWith(delimiter, index)) {
      return _StringLiteralScan(index + delimiter.length, interpolations);
    }
    if (!raw && source[index] == r'\' && index + 1 < source.length) {
      index += 2;
      continue;
    }
    if (!raw && source.startsWith(r'${', index)) {
      final expressionStart = index + 2;
      final expressionEnd = _interpolationEnd(source, expressionStart);
      interpolations.add(_SourceRange(expressionStart, expressionEnd));
      index = expressionEnd < source.length ? expressionEnd + 1 : source.length;
      continue;
    }
    index++;
  }
  return _StringLiteralScan(source.length, interpolations);
}

int _interpolationEnd(String source, int start) {
  var depth = 1;
  var index = start;
  while (index < source.length) {
    final lineCommentEnd = _lineCommentEnd(source, index);
    if (lineCommentEnd != null) {
      index = lineCommentEnd;
      continue;
    }
    final blockCommentEnd = _blockCommentEnd(source, index);
    if (blockCommentEnd != null) {
      index = blockCommentEnd;
      continue;
    }
    final stringLiteral = _scanStringLiteral(source, index);
    if (stringLiteral != null) {
      index = stringLiteral.end;
      continue;
    }
    if (source[index] == '{') {
      depth++;
    } else if (source[index] == '}') {
      depth--;
      if (depth == 0) return index;
    }
    index++;
  }
  return source.length;
}

void _maskRange(List<bool> mask, int start, int end) {
  for (var index = start; index < end; index++) {
    mask[index] = false;
  }
}

final class _SourceRange {
  const _SourceRange(this.start, this.end);

  final int start;
  final int end;
}

final class _StringLiteralScan {
  const _StringLiteralScan(this.end, this.interpolations);

  final int end;
  final List<_SourceRange> interpolations;
}
