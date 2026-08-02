import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_migration_report.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_setlist_adapter.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_song_adapter.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_song_reader.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';

/// E03-R06 — LegacySetlistAdapter unit matrix.

/// §6 acceptance matrix rows that belong to the setlist adapter:
///   - duplicate setlist: mindkét item, eredeti sorrend
///   - missing ID:        unresolved item, nincs crash
///   - mixed BPM dalhatár: sorrend, sorrend, sorrend (parity at E03-R08)

const _reader = LegacySongReader();
const _songAdapter = LegacySongAdapter();
const _setlistAdapter = LegacySetlistAdapter();

final DateTime _fixedTimestamp = DateTime.utc(2026, 1, 1, 12);

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/song_trainer/legacy/$name');
  expect(file.existsSync(), isTrue, reason: 'fixture missing: ${file.path}');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, SongDocument> _buildSongbook(Map<String, dynamic> fixture) {
  final book = <String, SongDocument>{};
  for (final raw in fixture['songbook'] as List) {
    final song = _reader.readSong(raw as Map<String, dynamic>);
    book[song.id] = _songAdapter
        .adapt(song, importedAt: _fixedTimestamp)
        .document;
  }
  return book;
}

void main() {
  group('LegacySongReader — setlist JSON boundary', () {
    test('parses the duplicate-fixture setlist shape', () {
      final fixture = _loadFixture('setlist_duplicate.json');
      final record = _reader.readSetlist(
        fixture['setlist'] as Map<String, dynamic>,
      );
      expect(record.id, 'set_dup');
      expect(record.name, 'Dup');
      expect(record.songIds, ['song_a', 'song_a']);
    });

    test('rejects missing songs key', () {
      expect(
        () => _reader.readSetlist(<String, dynamic>{
          'id': 'set',
          'name': 'no-songs',
        }),
        throwsA(isA<LegacySongReaderException>()),
      );
    });
  });

  group('LegacySetlistAdapter — §6 acceptance matrix', () {
    test('duplicate setlist preserves both copies in order', () {
      final fixture = _loadFixture('setlist_duplicate.json');
      final songbook = _buildSongbook(fixture);
      final setlist = _reader.readSetlist(
        fixture['setlist'] as Map<String, dynamic>,
      );
      final result = _setlistAdapter.adapt(setlist, songbook);

      expect(result.documents.map((d) => d.id.value).toList(), [
        'song_a',
        'song_a',
      ]);
      expect(
        result.report.warningSummary,
        contains(LegacyMigrationCode.setlistDuplicateRetained),
      );
      expect(result.unresolvedIds, isEmpty);
    });

    test('missing song id is skipped, reported and never crashes', () {
      final fixture = _loadFixture('setlist_missing_song.json');
      final songbook = _buildSongbook(fixture);
      final setlist = _reader.readSetlist(
        fixture['setlist'] as Map<String, dynamic>,
      );

      // No throw — the missing id is skipped.
      final result = _setlistAdapter.adapt(setlist, songbook);

      expect(
        result.documents.map((d) => d.id.value).toList(),
        ['song_a', 'song_a'],
        reason: 'surviving entries keep their original positions',
      );
      expect(result.unresolvedIds, ['ghost']);
      expect(
        result.report.warningSummary,
        contains(LegacyMigrationCode.setlistReferenceUnresolved),
      );
    });

    test('mixed-bpm setlist keeps each song as its own document', () {
      final fixture = _loadFixture('setlist_mixed_bpm.json');
      final songbook = _buildSongbook(fixture);
      final setlist = _reader.readSetlist(
        fixture['setlist'] as Map<String, dynamic>,
      );
      final result = _setlistAdapter.adapt(setlist, songbook);

      final ids = result.documents.map((d) => d.id.value).toList();
      expect(ids, ['song_a', 'song_b']);

      // Each adapted document carries its own tempo — no flatten.
      final tempoById = {
        for (final document in result.documents)
          document.id.value: document.tempoMap.changes.first.bpm.bpm,
      };
      expect(tempoById, {'song_a': 100, 'song_b': 120});

      // A clean setlist yields an empty migration report.
      expect(result.report.isEmpty, isTrue);
    });

    test(
      'empty songbook with non-empty setlist reports every id unresolved',
      () {
        final setlist = _reader.readSetlist(<String, dynamic>{
          'id': 'set_orphan',
          'name': 'Orphan',
          'songs': ['a', 'b', 'c'],
        });
        final result = _setlistAdapter.adapt(setlist, <String, SongDocument>{});

        expect(result.documents, isEmpty);
        expect(result.unresolvedIds, ['a', 'b', 'c']);
        expect(
          result.report.warningSummary,
          contains(LegacyMigrationCode.setlistReferenceUnresolved),
        );
      },
    );

    test('empty setlist yields an empty result and empty report', () {
      final setlist = _reader.readSetlist(<String, dynamic>{
        'id': 'set_empty',
        'name': 'Empty',
        'songs': <String>[],
      });
      final result = _setlistAdapter.adapt(setlist, <String, SongDocument>{});

      expect(result.documents, isEmpty);
      expect(result.unresolvedIds, isEmpty);
      expect(result.report.isEmpty, isTrue);
    });
  });

  group('LegacyMigrationReport', () {
    test('from() dedupes by code and sorts by code asc', () {
      final report = LegacyMigrationReport.from([
        const LegacyMigrationIssue(code: 'z', message: 'z'),
        const LegacyMigrationIssue(code: 'a', message: 'a'),
        const LegacyMigrationIssue(code: 'a', message: 'a'),
      ]);
      expect(report.issues.map((i) => i.code).toList(), ['a', 'z']);
      expect(report.warningSummary, ['a', 'z']);
    });

    test('empty factory yields the empty singleton', () {
      final report = LegacyMigrationReport.from(<LegacyMigrationIssue>[]);
      expect(report.isEmpty, isTrue);
      expect(report.warningSummary, isEmpty);
      expect(report.issues, isEmpty);
    });
  });
}
