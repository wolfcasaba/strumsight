import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/services/note_track_analyzer.dart';

const _analyzer = NoteTrackAnalyzer();

void main() {
  const analyzer = _analyzer;

  group('NoteTrackAnalyzer — empty / single-note baseline', () {
    test('empty track yields a trivially monophonic, empty report', () {
      final report = analyzer.analyze(const <SongNoteEvent>[]);
      expect(report.isMonophonic, isTrue);
      expect(report.overlapCount, 0);
      expect(report.tieCandidateCount, 0);
      expect(report.noteCount, 0);
      expect(report.lowestPitch, isNull);
      expect(report.highestPitch, isNull);
      expect(report.warnings, isEmpty);
    });

    test('single note yields a monophonic report with one counted note', () {
      final report = analyzer.analyze(<SongNoteEvent>[
        _note(id: 'n-1', startMs: 0, durationMs: 500, pitch: 60),
      ]);
      expect(report.isMonophonic, isTrue);
      expect(report.overlapCount, 0);
      expect(report.tieCandidateCount, 0);
      expect(report.noteCount, 1);
      expect(report.lowestPitch, 60);
      expect(report.highestPitch, 60);
      expect(report.warnings, isEmpty);
    });
  });

  group('NoteTrackAnalyzer — §6 required matrix', () {
    test('egymás után, gap-pel → monophonic (no overlaps, no tie)', () {
      final report = analyzer.analyze(<SongNoteEvent>[
        _note(id: 'n-1', startMs: 0, durationMs: 500, pitch: 60),
        _note(id: 'n-2', startMs: 1000, durationMs: 500, pitch: 62),
      ]);
      expect(report.isMonophonic, isTrue);
      expect(report.overlapCount, 0);
      expect(report.tieCandidateCount, 0);
      expect(report.warnings, isEmpty);
    });

    test('end == next start → monophonic boundary (no overlap, no tie)', () {
      final report = analyzer.analyze(<SongNoteEvent>[
        _note(id: 'n-1', startMs: 0, durationMs: 500, pitch: 60),
        _note(id: 'n-2', startMs: 500, durationMs: 500, pitch: 62),
      ]);
      expect(report.isMonophonic, isTrue);
      expect(report.overlapCount, 0);
      expect(report.tieCandidateCount, 0);
      expect(report.warnings, isEmpty);
    });

    test('end > next start, different pitch → polyphonic overlap', () {
      final report = analyzer.analyze(<SongNoteEvent>[
        _note(id: 'n-1', startMs: 0, durationMs: 1000, pitch: 60),
        _note(id: 'n-2', startMs: 500, durationMs: 500, pitch: 62),
      ]);
      expect(report.isMonophonic, isFalse);
      expect(report.overlapCount, 1);
      expect(report.tieCandidateCount, 0);
      expect(report.warnings, isEmpty);
    });

    test(
      'three-note polyphonic passage counts every different-pitch overlap',
      () {
        final report = analyzer.analyze(<SongNoteEvent>[
          _note(id: 'n-1', startMs: 0, durationMs: 1000, pitch: 60),
          _note(id: 'n-2', startMs: 500, durationMs: 1000, pitch: 62),
          _note(id: 'n-3', startMs: 1000, durationMs: 1000, pitch: 64),
        ]);
        expect(report.isMonophonic, isFalse);
        expect(report.overlapCount, 2);
      },
    );

    test(
      'long note remains active past an intervening same-pitch tie candidate',
      () {
        final report = analyzer.analyze(<SongNoteEvent>[
          _note(id: 'a', startMs: 0, durationMs: 10000, pitch: 60),
          _note(id: 'b', startMs: 100, durationMs: 100, pitch: 60),
          _note(id: 'c', startMs: 5000, durationMs: 100, pitch: 62),
        ]);

        expect(report.isMonophonic, isFalse);
        expect(report.overlapCount, 1);
        expect(report.tieCandidateCount, 1);
      },
    );

    test('azonos pitch overlap → merge-candidate, monophonic overall', () {
      final report = analyzer.analyze(<SongNoteEvent>[
        _note(id: 'n-1', startMs: 0, durationMs: 1000, pitch: 60),
        _note(id: 'n-2', startMs: 500, durationMs: 500, pitch: 60),
      ]);
      expect(report.isMonophonic, isTrue);
      expect(report.overlapCount, 0);
      expect(report.tieCandidateCount, 1);
      expect(report.warnings, isEmpty);
    });

    test('eltérő pitch azonos tieGroupId → invalid tie warning', () {
      final report = analyzer.analyze(<SongNoteEvent>[
        _note(
          id: 'n-1',
          startMs: 0,
          durationMs: 500,
          pitch: 60,
          tieGroupId: 'g1',
        ),
        _note(
          id: 'n-2',
          startMs: 500,
          durationMs: 500,
          pitch: 62,
          tieGroupId: 'g1',
        ),
      ]);
      expect(report.warnings, isNotEmpty);
      expect(
        report.warnings.any(
          (w) => w.code == NoteTrackAnalysisWarningCode.tieGroupPitchMismatch,
        ),
        isTrue,
      );
    });

    test('same pitch with same tieGroupId is a clean merge candidate', () {
      final report = analyzer.analyze(<SongNoteEvent>[
        _note(
          id: 'n-1',
          startMs: 0,
          durationMs: 500,
          pitch: 60,
          tieGroupId: 'g1',
        ),
        _note(
          id: 'n-2',
          startMs: 500,
          durationMs: 500,
          pitch: 60,
          tieGroupId: 'g1',
        ),
      ]);
      expect(report.isMonophonic, isTrue);
      expect(report.tieCandidateCount, 0);
      expect(report.warnings, isEmpty);
    });
  });

  group('NoteTrackAnalyzer — invariants', () {
    test('highestPitch / lowestPitch cover all notes in canonical order', () {
      final report = analyzer.analyze(<SongNoteEvent>[
        _note(id: 'n-1', startMs: 0, durationMs: 100, pitch: 72),
        _note(id: 'n-2', startMs: 100, durationMs: 100, pitch: 48),
        _note(id: 'n-3', startMs: 200, durationMs: 100, pitch: 60),
      ]);
      expect(report.lowestPitch, 48);
      expect(report.highestPitch, 72);
      expect(report.noteCount, 3);
    });

    test('same input → same report (deterministic)', () {
      final events = <SongNoteEvent>[
        _note(id: 'n-1', startMs: 0, durationMs: 700, pitch: 60),
        _note(id: 'n-2', startMs: 500, durationMs: 700, pitch: 62),
        _note(id: 'n-3', startMs: 1200, durationMs: 500, pitch: 64),
      ];
      final first = analyzer.analyze(events);
      final second = analyzer.analyze(events);
      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });

    test('does not mutate the input collection', () {
      final events = <SongNoteEvent>[
        _note(id: 'n-2', startMs: 500, durationMs: 500, pitch: 62),
        _note(id: 'n-1', startMs: 0, durationMs: 500, pitch: 60),
      ];
      final idsBefore = events.map((e) => e.id.value).toList();
      analyzer.analyze(events);
      final idsAfter = events.map((e) => e.id.value).toList();
      expect(idsAfter, idsBefore);
      expect(events, hasLength(2));
    });

    test('canonical ordering is start asc → event id', () {
      // Two notes share start == 1000ms; analyser sorts by event id so the
      // earlier id is treated as the "first" note and the boundary check is
      // stable regardless of caller order. The pitches differ but no
      // pair overlap (n-m 0..500, n-a 1000..1500, n-z 1500..2000), so the
      // report is monophonic and identical for any input order.
      final report = analyzer.analyze(<SongNoteEvent>[
        _note(id: 'n-z', startMs: 1500, durationMs: 500, pitch: 64),
        _note(id: 'n-a', startMs: 1000, durationMs: 500, pitch: 62),
        _note(id: 'n-m', startMs: 0, durationMs: 500, pitch: 60),
      ]);
      expect(report.isMonophonic, isTrue);
      expect(report.overlapCount, 0);
      expect(report.noteCount, 3);
      // Same report whether the caller hands them in any permutation.
      final reordered = analyzer.analyze(<SongNoteEvent>[
        _note(id: 'n-a', startMs: 1000, durationMs: 500, pitch: 62),
        _note(id: 'n-m', startMs: 0, durationMs: 500, pitch: 60),
        _note(id: 'n-z', startMs: 1500, durationMs: 500, pitch: 64),
      ]);
      expect(reordered, equals(report));
    });

    test('analyzer.analyzeTrack produces same report as analyze(events)', () {
      final events = <SongNoteEvent>[
        _note(id: 'n-1', startMs: 0, durationMs: 1000, pitch: 60),
        _note(id: 'n-2', startMs: 500, durationMs: 1000, pitch: 62),
      ];
      final track = NoteTrack(
        id: SongTrackId('t-1'),
        name: 'Lead',
        instrument: SongInstrument(name: 'Guitar'),
        events: events,
      );
      final fromEvents = analyzer.analyze(events);
      final fromTrack = analyzer.analyzeTrack(track);
      expect(fromTrack, equals(fromEvents));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SongNoteEvent _note({
  required String id,
  required int startMs,
  required int durationMs,
  required int pitch,
  String? tieGroupId,
}) {
  return SongNoteEvent(
    id: SongEventId(id),
    start: Duration(milliseconds: startMs),
    duration: Duration(milliseconds: durationMs),
    midiPitch: pitch,
    tieGroupId: tieGroupId,
  );
}
