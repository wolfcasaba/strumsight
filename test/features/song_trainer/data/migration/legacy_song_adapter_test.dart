import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_migration_report.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_song_adapter.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_song_reader.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';

import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';

/// E03-R06 — LegacySongReader + LegacySongAdapter boundary matrix.
///
/// The reader is the pure DTO/decoder boundary (no presentation
/// imports); the adapter turns the DTO into a V2 [SongDocument]. This
/// suite covers the §6 acceptance matrix one row at a time:

/// | Legacy eset               | V2 kötelező eredmény                  |
/// |---------------------------|----------------------------------------|
/// | 4/4 chord+pattern         | measure-enként esemény, beat-0 map     |
/// | 3/4                       | 3 beat measure, parity duration        |
/// | rest                      | nincs kitalált chord                   |
/// | corrupt pattern           | dokumentált repair+warning parity      |
/// | duplicate setlist         | mindkét item, eredeti sorrend          |
/// | missing ID                | unresolved item, nincs crash           |

const _reader = LegacySongReader();
const _adapter = LegacySongAdapter();

final DateTime _fixedTimestamp = DateTime.utc(2026, 1, 1, 12);

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/song_trainer/legacy/$name');
  expect(file.existsSync(), isTrue, reason: 'fixture missing: ${file.path}');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

LegacySongRecord _readSong(Map<String, dynamic> fixture) =>
    _reader.readSong(fixture['song'] as Map<String, dynamic>);

void main() {
  group('LegacySongReader — JSON boundary', () {
    test('parses a 4/4 song record', () {
      final fixture = _loadFixture('song_44.json');
      final record = _reader.readSong(fixture['song'] as Map<String, dynamic>);
      expect(record.id, 'song_44');
      expect(record.name, 'Baseline 4/4');
      expect(record.beatsPerBar, 4);
      expect(record.bpm, 96);
      expect(record.chords, ['C', 'G']);
      expect(record.pattern, hasLength(8));
      expect(record.pattern, [
        StrumDirection.down,
        null,
        StrumDirection.down,
        StrumDirection.up,
        null,
        StrumDirection.up,
        StrumDirection.down,
        null,
      ]);
    });

    test('defaults `bpb` to 4 when the key is missing (legacy pre-R116)', () {
      final record = _reader.readSong(<String, dynamic>{
        'id': 'legacy',
        'name': 'No bpb',
        'chords': ['C'],
        'pat': 'd-d-d-d-',
        'bpm': 100,
      });
      expect(record.beatsPerBar, 4);
    });

    test('rejects missing id', () {
      expect(
        () => _reader.readSong(<String, dynamic>{
          'name': 'x',
          'chords': ['C'],
          'pat': 'd',
          'bpm': 100,
        }),
        throwsA(isA<LegacySongReaderException>()),
      );
    });

    test('rejects empty chord entry', () {
      expect(
        () => _reader.readSong(<String, dynamic>{
          'id': 'a',
          'name': 'x',
          'chords': ['C', ''],
          'pat': 'd-d-d-d-',
          'bpm': 100,
        }),
        throwsA(isA<LegacySongReaderException>()),
      );
    });

    test('rejects an invalid pattern slot', () {
      expect(
        () => _reader.readSong(<String, dynamic>{
          'id': 'a',
          'name': 'x',
          'chords': ['C'],
          'pat': 'dx',
          'bpm': 100,
        }),
        throwsA(isA<LegacySongReaderException>()),
      );
    });

    test('rejects bpm outside the documented 1..400 range', () {
      expect(
        () => _reader.readSong(<String, dynamic>{
          'id': 'a',
          'name': 'x',
          'chords': ['C'],
          'pat': 'd',
          'bpm': 0,
        }),
        throwsA(isA<LegacySongReaderException>()),
      );
      expect(
        () => _reader.readSong(<String, dynamic>{
          'id': 'a',
          'name': 'x',
          'chords': ['C'],
          'pat': 'd',
          'bpm': 401,
        }),
        throwsA(isA<LegacySongReaderException>()),
      );
    });

    test('canonical SHA-256 is stable across two equal reads', () {
      final fixture = _loadFixture('song_44.json');
      final json = fixture['song'] as Map<String, dynamic>;
      final first = _reader.readSong(json);
      final second = _reader.readSong(json);
      expect(first.canonicalSha256, second.canonicalSha256);
      expect(first.canonicalSha256.length, 64);
      // Lower-case hex only.
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(first.canonicalSha256), isTrue);
    });
  });

  group('LegacySongAdapter — §6 acceptance matrix', () {
    test('4/4 chord+pattern → measure-enként esemény, beat-0 tempo map', () {
      final record = _readSong(_loadFixture('song_44.json'));
      final result = _adapter.adapt(record, importedAt: _fixedTimestamp);

      // Chord events: one per measure, 2 measures.
      final chordTrack = result.document.tracks.whereType<ChordTrack>().single;
      expect(chordTrack.events, hasLength(2));
      expect(chordTrack.events.first.symbol, const Chord('C'));
      expect(chordTrack.events.last.symbol, const Chord('G'));
      expect(
        chordTrack.events.first.start,
        Duration.zero,
        reason: 'first measure starts at beat 0',
      );

      // Tempo map first boundary is at BeatPosition.zero.
      expect(result.document.tempoMap.changes.first.at, BeatPosition.zero);
      expect(result.document.tempoMap.changes.first.bpm.bpm, 96);

      // Meter is beatsPerBar/4 with no fake denominator (ADR 0116 §Döntés 2).
      final meter = result.document.meterMap.changes.first.meter;
      expect(meter.numerator, 4);
      expect(meter.denominator, 4);

      // No fidelity note for a clean in-bounds record.
      expect(result.report.isEmpty, isTrue);
    });

    test('3/4 → 3-beat measure, parity duration', () {
      final record = _readSong(_loadFixture('song_34.json'));
      final result = _adapter.adapt(record, importedAt: _fixedTimestamp);

      // Meter is 3/4, every measure carries a 3-beat duration.
      final meter = result.document.meterMap.changes.first.meter;
      expect(meter.numerator, 3);
      expect(meter.denominator, 4);

      // Legacy `Song.toAnalyzeResult()` multiplies the complete beat
      // position by `60 / bpm`. Round that final wall-clock value once;
      // rounding seconds-per-beat before multiplying would drift here.
      final chordTrack = result.document.tracks.whereType<ChordTrack>().single;
      final totalMicros = chordTrack.events
          .map((e) => e.duration.inMicroseconds)
          .reduce((a, b) => a + b);
      expect(
        totalMicros,
        4736842,
        reason:
            '3/4: direct legacy timing rounded only at the Duration boundary',
      );

      // No fidelity note — the record was clean.
      expect(result.report.isEmpty, isTrue);
    });

    test('rest → no invented strum event', () {
      final record = _readSong(_loadFixture('song_rests.json'));
      final result = _adapter.adapt(record, importedAt: _fixedTimestamp);

      final strumTrack = result.document.tracks.whereType<StrumTrack>().single;
      // The pattern has 2 strokes per measure × 2 measures = 4 events,
      // not 16 (the legacy fixture locks this exact value).
      expect(strumTrack.events, hasLength(4));
      // Every direction is non-null — the adapter did NOT invent strokes
      // for the rest slots.
      expect(strumTrack.events.every((e) => e.direction != null), isTrue);
      // No chord event was invented either — exactly one per measure.
      final chordTrack = result.document.tracks.whereType<ChordTrack>().single;
      expect(chordTrack.events, hasLength(2));
      expect(
        chordTrack.events.map((event) => event.duration.inMicroseconds),
        [2666667, 2666666],
        reason:
            'each chord duration is its direct-rounded legacy end minus start',
      );
      expect(
        chordTrack.events.first.start + chordTrack.events.first.duration,
        chordTrack.events.last.start,
        reason: 'direct-rounded adjacent measures remain contiguous',
      );
    });

    test('corrupt pattern → repair + warning parity', () {
      // Pattern length 10 for a 4-beat bar (must be 8) — the legacy
      // reader preserves the raw pattern; the adapter fits and reports.
      final record = _reader.readSong(<String, dynamic>{
        'id': 'corrupt',
        'name': 'Corrupt',
        'chords': ['C'],
        // 6-slot pattern (all downstrokes); the adapter must pad it to
        // exactly 8 slots with two trailing rests (beatsPerBar * 2).
        'pat': 'dddddd',
        'bpm': 100,
      });
      final result = _adapter.adapt(record, importedAt: _fixedTimestamp);

      // Adapter fitted the pattern to exactly 8 slots.
      final strumTrack = result.document.tracks.whereType<StrumTrack>().single;
      // Six slots were strokes, two trailing rests produced no events —
      // the surviving 6 strokes are the events we expect.
      expect(strumTrack.events, hasLength(6));

      // Adapter surfaced a fidelity note on both the typed report and
      // the SongSource.warningSummary list (codec round-trip).
      expect(result.report.warningSummary, [
        LegacyMigrationCode.patternLengthFitted,
      ]);
      expect(result.document.source.warningSummary, [
        LegacyMigrationCode.patternLengthFitted,
      ]);
    });

    test('bpm above 400 is clamped with a fidelity note', () {
      // Reader rejects bpm > 400; we cannot exercise the adapter's clamp
      // path through the reader. The clamp path lives in the adapter
      // for the SongDocumentCodec's loose records — exercise it with a
      // reader-built record by lowering the read bound temporarily.
      // The reader already rejects out-of-range values, so the clamp is
      // defensive only; we still verify the report code is wired by
      // hand-crafting a record.
      final handRecord = LegacySongRecord(
        id: 'clamp',
        name: 'Clamp',
        chords: const ['C'],
        pattern: const [
          StrumDirection.down,
          null,
          StrumDirection.down,
          null,
          StrumDirection.down,
          null,
          StrumDirection.down,
          null,
        ],
        bpm: 500, // deliberately out of range
        beatsPerBar: 4,
        canonicalSha256: 'a' * 64,
      );
      final result = _adapter.adapt(handRecord, importedAt: _fixedTimestamp);
      // Clamped into the [1, 400] range — the legacy max.
      expect(result.document.tempoMap.changes.first.bpm.bpm, 400);
      expect(result.report.warningSummary, [LegacyMigrationCode.bpmClamped]);
    });
  });

  group('LegacySongAdapter — provenance + structure invariants', () {
    test('source.type is legacyLocal', () {
      final record = _readSong(_loadFixture('song_44.json'));
      final result = _adapter.adapt(record, importedAt: _fixedTimestamp);
      expect(result.document.source.type, SongSourceType.legacyLocal);
    });

    test('full-song section uses kind=custom with name "Full Song"', () {
      final record = _readSong(_loadFixture('song_multiple_chords.json'));
      final result = _adapter.adapt(record, importedAt: _fixedTimestamp);
      expect(result.document.sections, hasLength(1));
      final section = result.document.sections.first;
      expect(section.kind, SongSectionKind.custom);
      expect(section.name, 'Full Song');
      expect(section.startMeasure, 0);
      expect(section.endMeasureExclusive, record.chords.length);
    });

    test('idempotency: two calls produce identical documents', () {
      final record = _readSong(_loadFixture('song_44.json'));
      final a = _adapter.adapt(record, importedAt: _fixedTimestamp);
      final b = _adapter.adapt(record, importedAt: _fixedTimestamp);
      expect(a.document, equals(b.document));
      expect(a.report, equals(b.report));
    });

    test('document id, schemaVersion and revision are stable', () {
      final record = _readSong(_loadFixture('song_34.json'));
      final result = _adapter.adapt(
        record,
        importedAt: _fixedTimestamp,
        revision: 7,
      );
      expect(result.document.schemaVersion, songDocumentSchemaVersion);
      expect(result.document.id.value, 'song_34');
      expect(result.document.revision, 7);
    });
  });
}
