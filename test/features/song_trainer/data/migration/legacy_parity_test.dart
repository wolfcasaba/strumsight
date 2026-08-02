import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_migration_report.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_setlist_adapter.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_song_adapter.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_song_reader.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';

/// E03-R06 — parity check between the legacy `Song` / `Setlist` model and
/// the V2 `SongDocument` produced by [LegacySongAdapter] /
/// [LegacySetlistAdapter].
///
/// The R01 baseline locked the legacy codec against the same set of
/// self-authored fixtures (see `legacy_fixture_parity_test.dart`). This
/// test runs the adapter over the same fixtures and asserts the V2
/// document reproduces the legacy invariants the R01 suite already
/// locked: event count, total beats, direction sequence, meter, and
/// (where relevant) per-chord beat groups.
///
/// The fixture's `expected` block is the source of truth — the test
/// reads it and asks the adapter to match it, so a reviewer can flip any
/// cell and turn the corresponding scenario red.
const _fixturesDir = 'test/fixtures/song_trainer/legacy';

const _reader = LegacySongReader();
const _songAdapter = LegacySongAdapter();
const _setlistAdapter = LegacySetlistAdapter();

/// Deterministic timestamp the parity tests stamp on every adapted
/// document — fixes the `importedAt` / `createdAt` / `updatedAt` field so
/// the codec round-trip is stable.
final DateTime _fixedTimestamp = DateTime.utc(2026, 1, 1, 12);

/// Tolerance for the Duration-derived `durationSec` comparison. The
/// legacy `toAnalyzeResult()` uses `double` arithmetic (so e.g. 76 BPM
/// yields a non-terminating `durationSec`); the V2 boundary stores
/// `Duration` (integer microseconds) per ADR 0116 §Döntés 3, which means
/// a one-microsecond rounding step per BPM at the spb boundary. Ten
/// microseconds is comfortably above the largest realistic drift
/// (event_count × 1 µs at the BPM) while still tight enough to flag a
/// stale rounding point.
const double _durationTolerance = 1e-5;

/// Tolerance for the per-chord beat recovery. Beat numbers are
/// half-integer (`bar * beatsPerBar + slot * 0.5`) and we recover them
/// from `Duration` via the known chord-event layout — the result is
/// exact in theory; 1e-9 absorbs any double conversion noise.
const double _beatTolerance = 1e-9;

Map<String, dynamic> _loadFixture(String name) {
  final file = File('$_fixturesDir/$name');
  expect(file.existsSync(), isTrue, reason: 'fixture missing: ${file.path}');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

String _directionToken(StrumDirection? d) => switch (d) {
  StrumDirection.down => 'd',
  StrumDirection.up => 'u',
  null => '-',
};

LegacySongAdaptation _adaptSong(Map<String, dynamic> fixture) {
  final song = _reader.readSong(fixture['song'] as Map<String, dynamic>);
  return _songAdapter.adapt(song, importedAt: _fixedTimestamp);
}

void main() {
  group('E03-R06 legacy Song adapter — parity', () {
    for (final name in const [
      'song_44.json',
      'song_34.json',
      'song_rests.json',
      'song_multiple_chords.json',
    ]) {
      test(name, () {
        final fixture = _loadFixture(name);
        final expected = fixture['expected'] as Map<String, dynamic>;
        final fixtureName = fixture['fixture'] as String;
        final result = _adaptSong(fixture);

        // -------- Discrete V2 invariants --------
        final document = result.document;
        final chordTrack = document.tracks.whereType<ChordTrack>().single;
        final strumTrack = document.tracks.whereType<StrumTrack>().single;

        expect(
          chordTrack.events.length,
          expected['chordSequence'].length,
          reason: '$fixtureName: one chord event per measure',
        );
        expect(
          strumTrack.events.length,
          expected['events'],
          reason: '$fixtureName: one strum event per non-rest slot',
        );
        expect(
          strumTrack.events
              .where((e) => e.direction == StrumDirection.down)
              .length,
          expected['downCount'],
          reason: '$fixtureName: down count',
        );
        expect(
          strumTrack.events
              .where((e) => e.direction == StrumDirection.up)
              .length,
          expected['upCount'],
          reason: '$fixtureName: up count',
        );

        // Direction sequence matches the R01 directionSequence exactly.
        expect(
          strumTrack.events.map((e) => _directionToken(e.direction)).toList(),
          expected['directionSequence'],
          reason: '$fixtureName: direction sequence',
        );

        // Chord symbols match the R01 chordSequence exactly.
        expect(
          chordTrack.events.map((e) => e.symbol.label).toList(),
          expected['chordSequence'],
          reason: '$fixtureName: chord symbol sequence',
        );

        // -------- Timing parity --------
        // SongDocument events are Duration-anchored; the legacy
        // `totalBeats` is computed against `bpm * beatsPerBar` —
        // recovering beats from Duration requires the seconds-per-beat
        // ratio that the adapter derived.
        final beatsPerBar = document.meterMap.changes.first.meter.numerator;
        final totalBeats = (document.measures.length * beatsPerBar).toDouble();
        expect(
          totalBeats,
          closeTo((expected['totalBeats'] as num).toDouble(), _beatTolerance),
          reason: '$fixtureName: totalBeats (Duration-derived)',
        );

        // Total Duration in seconds matches the legacy `durationSec`
        // to within integer-micros precision (one rounding point at the
        // BPM boundary, then exact rational arithmetic — ADR 0116
        // §Döntés 3).
        final lastChord = chordTrack.events.last;
        final totalMicros =
            (lastChord.start.inMicroseconds +
                lastChord.duration.inMicroseconds) -
            chordTrack.events.first.start.inMicroseconds;
        final expectedSeconds = (expected['durationSec'] as num).toDouble();
        final actualSeconds = totalMicros / 1000000.0;
        expect(
          actualSeconds,
          closeTo(expectedSeconds, _durationTolerance),
          reason: '$fixtureName: durationSec (micros)',
        );

        // Per-chord beat groups (rests + multi-chord fixtures only).
        final perChord = expected['perChordBeats'];
        if (perChord is Map) {
          final actual = _perChordBeats(
            chordTrack,
            strumTrack,
            beatsPerBar,
            document.tempoMap.changes.first.bpm.bpm,
          );
          final expectedBeats = <String, List<double>>{
            for (final entry in perChord.entries)
              entry.key as String: (entry.value as List)
                  .map((b) => (b as num).toDouble())
                  .toList(),
          };
          expect(
            actual,
            expectedBeats,
            reason: '$fixtureName: per-chord beats',
          );
        }

        // -------- Provenance invariants --------
        expect(
          document.source.type.name,
          'legacyLocal',
          reason: '$fixtureName: source.type',
        );
        expect(
          document.source.importerVersion,
          'legacySongAdapter@1',
          reason: '$fixtureName: importer version',
        );
        expect(
          document.source.sha256.length,
          64,
          reason: '$fixtureName: SHA-256 is 64 lowercase hex',
        );

        // A clean (in-bounds) record yields an empty migration report.
        expect(
          result.report.isEmpty,
          isTrue,
          reason: '$fixtureName: clean legacy record → empty report',
        );
      });
    }
  });

  group('E03-R06 legacy Setlist adapter — parity', () {
    test('duplicate setlist preserves both copies in order', () {
      final fixture = _loadFixture('setlist_duplicate.json');
      final expected = fixture['expected'] as Map<String, dynamic>;

      // Adapt every song in the songbook, then map by id.
      final songbook = <String, SongDocument>{};
      for (final raw in fixture['songbook'] as List) {
        final song = _reader.readSong(raw as Map<String, dynamic>);
        final adaptation = _songAdapter.adapt(
          song,
          importedAt: _fixedTimestamp,
        );
        songbook[song.id] = adaptation.document;
      }

      final setlist = _reader.readSetlist(
        fixture['setlist'] as Map<String, dynamic>,
      );
      final adaptation = _setlistAdapter.adapt(setlist, songbook);

      // Resolve order matches the legacy resolvedOrder — both copies of
      // song_a survive in order, no dedup.
      final resolvedIds = adaptation.documents.map((d) => d.id.value).toList();
      expect(
        resolvedIds,
        expected['resolvedOrder'],
        reason: 'duplicate: order + count preserved',
      );
      expect(
        adaptation.report.warningSummary,
        contains(LegacyMigrationCode.setlistDuplicateRetained),
        reason: 'duplicate: fidelity note emitted',
      );
      expect(
        adaptation.unresolvedIds,
        isEmpty,
        reason: 'duplicate: no unresolved ids',
      );
    });

    test('missing song id is skipped, not crashed, and reported', () {
      final fixture = _loadFixture('setlist_missing_song.json');
      final expected = fixture['expected'] as Map<String, dynamic>;

      final songbook = <String, SongDocument>{};
      for (final raw in fixture['songbook'] as List) {
        final song = _reader.readSong(raw as Map<String, dynamic>);
        final adaptation = _songAdapter.adapt(
          song,
          importedAt: _fixedTimestamp,
        );
        songbook[song.id] = adaptation.document;
      }
      final setlist = _reader.readSetlist(
        fixture['setlist'] as Map<String, dynamic>,
      );
      final adaptation = _setlistAdapter.adapt(setlist, songbook);

      expect(
        adaptation.documents.map((d) => d.id.value).toList(),
        expected['resolvedOrder'],
        reason: 'missing: surviving entries keep their positions',
      );
      expect(
        adaptation.unresolvedIds,
        expected['unresolvedIds'],
        reason: 'missing: ghost id is surfaced, no crash',
      );
      expect(
        adaptation.report.warningSummary,
        contains(LegacyMigrationCode.setlistReferenceUnresolved),
        reason: 'missing: fidelity note emitted',
      );
    });

    test('mixed-bpm setlist: each song keeps its own tempo and document', () {
      final fixture = _loadFixture('setlist_mixed_bpm.json');
      final expected = fixture['expected'] as Map<String, dynamic>;

      final songbook = <String, SongDocument>{};
      for (final raw in fixture['songbook'] as List) {
        final song = _reader.readSong(raw as Map<String, dynamic>);
        final adaptation = _songAdapter.adapt(
          song,
          importedAt: _fixedTimestamp,
        );
        songbook[song.id] = adaptation.document;
      }
      final setlist = _reader.readSetlist(
        fixture['setlist'] as Map<String, dynamic>,
      );
      final adaptation = _setlistAdapter.adapt(setlist, songbook);

      final ids = adaptation.documents.map((d) => d.id.value).toList();
      expect(
        ids,
        expected['resolvedOrder'],
        reason: 'mixed-bpm: resolve order preserved',
      );

      // Per-song durations in real seconds — the V2 boundary stores
      // Duration (wall-clock), the legacy durationSec was the same.
      final perDuration = expected['perSongDurationSec'] as Map;
      for (final document in adaptation.documents) {
        final chordTrack = document.tracks.whereType<ChordTrack>().single;
        final lastChord = chordTrack.events.last;
        final totalMicros =
            (lastChord.start.inMicroseconds +
                lastChord.duration.inMicroseconds) -
            chordTrack.events.first.start.inMicroseconds;
        final expectedDur = (perDuration[document.id.value] as num).toDouble();
        expect(
          totalMicros / 1000000.0,
          closeTo(expectedDur, _durationTolerance),
          reason: 'mixed-bpm: per-song duration ${document.id.value}',
        );
      }

      // Each adapted document carries its own tempo — the reference-tempo
      // warp that the legacy combine() does is NOT in scope here (that
      // belongs to a future setlist combine() V2 round, E03-R08+).
      final tempoById = {
        for (final document in adaptation.documents)
          document.id.value: document.tempoMap.changes.first.bpm.bpm,
      };
      expect(tempoById, {
        'song_a': 100,
        'song_b': 120,
      }, reason: 'mixed-bpm: each song keeps its own tempo');

      // A clean setlist (no duplicates, no missing) yields an empty
      // migration report.
      expect(
        adaptation.report.isEmpty,
        isTrue,
        reason: 'mixed-bpm: clean setlist → empty report',
      );
    });
  });

  group('E03-R06 determinism', () {
    test('the adapter produces identical bytes for identical inputs', () {
      final fixture = _loadFixture('song_44.json');
      final first = _adaptSong(fixture);
      final second = _adaptSong(fixture);
      expect(second.document, equals(first.document));
      expect(second.report, equals(first.report));
      expect(
        first.document.source.sha256,
        second.document.source.sha256,
        reason: 'SHA-256 is stable across calls',
      );
    });
  });
}

/// Recover the per-chord beat groups from the V2 events.
///
/// Beat numbers are always `(measureIndex * beatsPerBar + slotIndex * 0.5)`
/// — exact half-integer values. We recover them from the direct legacy
/// wall-clock timebase, then group them by their chord measure.
Map<String, List<double>> _perChordBeats(
  ChordTrack chordTrack,
  StrumTrack strumTrack,
  int beatsPerBar,
  int bpm,
) {
  final actual = <String, List<double>>{};
  for (final strum in strumTrack.events) {
    final measureIndex = _measureIndexOf(chordTrack, strum);
    final slotIndex = _slotIndexOf(strum, bpm) % (beatsPerBar * 2);
    final beat = measureIndex * beatsPerBar + slotIndex * 0.5;
    final chordSymbol = chordTrack.events[measureIndex].symbol.label;
    actual.putIfAbsent(chordSymbol, () => <double>[]).add(beat);
  }
  return actual;
}

int _measureIndexOf(ChordTrack chordTrack, SongStrumEvent strum) {
  for (var i = 0; i < chordTrack.events.length; i++) {
    final chord = chordTrack.events[i];
    final end = chord.start + chord.duration;
    if (strum.at >= chord.start && strum.at < end) return i;
  }
  return chordTrack.events.length - 1;
}

int _slotIndexOf(SongStrumEvent strum, int bpm) =>
    (strum.at.inMicroseconds * 2 * bpm / 60000000).round();
