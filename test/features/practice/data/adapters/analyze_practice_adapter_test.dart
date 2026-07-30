import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/practice/data/adapters/analyze_practice_adapter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';

PracticeDefinition _ok(AppResult<PracticeDefinition> r) =>
    (r as Success<PracticeDefinition>).value;

AppFailure _err(AppResult<PracticeDefinition> r) =>
    (r as Failure<PracticeDefinition>).error;

void main() {
  group('practiceDefinitionFromAnalyze — non-empty clip', () {
    test('three strums with two chord lanes produce deterministic ticks', () {
      // 120 BPM => 0.5 sec/beat; 4/4; t0 is the first strum time.
      // Strums at 0.0, 0.5, 1.0 sec → beats 0, 1, 2 → ticks 0, 480, 960.
      // Chord lanes: [0.0, 1.0) = 'Em', [1.0, 2.0) = 'C'.
      const result = AnalyzeResult(
        durationSec: 2.0,
        bpm: 120.0,
        chords: [
          TimelineChord(label: 'Em', startSec: 0.0, endSec: 1.0),
          TimelineChord(label: 'C', startSec: 1.0, endSec: 2.0),
        ],
        strums: [
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.0,
            confidence: 0.9,
          ),
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.5,
            confidence: 0.9,
          ),
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 1.0,
            confidence: 0.9,
          ),
        ],
      );
      final def = _ok(
        practiceDefinitionFromAnalyze(
          result,
          sourceId: 'clip-1',
          title: 'My Clip',
        ),
      );

      expect(def.events, hasLength(3));
      expect(def.events[0].position.ticks, 0);
      expect(def.events[1].position.ticks, 480);
      expect(def.events[2].position.ticks, 960);
      expect(def.events[0].direction, StrumDirection.down);
      expect(def.events[0].chord, 'Em');
      expect(def.events[1].chord, 'Em');
      expect(def.events[2].chord, 'C');
      expect(def.id, 'analyze.clip-1.v1');
      expect(def.sourceReference, 'analyze:clip-1');
      expect(def.source, PracticeSource.analyze);
      expect(def.displayTitle, 'My Clip');
      expect(def.validate(), isEmpty);
    });

    test('preserves 3/4 meter on the resulting definition', () {
      const result = AnalyzeResult(
        durationSec: 1.0,
        bpm: 90.0,
        chords: [TimelineChord(label: 'C', startSec: 0.0, endSec: 1.0)],
        strums: [
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.0,
            confidence: 0.9,
          ),
        ],
        beatsPerBar: 3,
      );
      final def = _ok(
        practiceDefinitionFromAnalyze(
          result,
          sourceId: 'waltz-1',
          title: 'Waltz',
        ),
      );
      expect(def.meter.beatsPerBar, 3);
    });

    test('unordered strums come out sorted', () {
      const result = AnalyzeResult(
        durationSec: 2.0,
        bpm: 120.0,
        chords: [TimelineChord(label: 'Em', startSec: 0.0, endSec: 2.0)],
        strums: [
          TimelineStrum(
            direction: StrumDirection.up,
            timeSec: 1.0,
            confidence: 0.9,
          ),
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.5,
            confidence: 0.9,
          ),
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.0,
            confidence: 0.9,
          ),
        ],
      );
      final def = _ok(
        practiceDefinitionFromAnalyze(
          result,
          sourceId: 'unordered',
          title: 'x',
        ),
      );
      final times = def.events.map((e) => e.position.ticks).toList();
      final sorted = [...times]..sort();
      expect(times, sorted);
      expect(def.events[0].direction, StrumDirection.down);
      expect(def.events[2].direction, StrumDirection.up);
    });
  });

  group('practiceDefinitionFromAnalyze — BPM fallbacks', () {
    Future<PracticeDefinition> build(double bpm) async {
      const result = AnalyzeResult(
        durationSec: 1.0,
        bpm: 0.0,
        chords: [TimelineChord(label: 'Em', startSec: 0.0, endSec: 1.0)],
        strums: [
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.0,
            confidence: 0.9,
          ),
        ],
      );
      final r = practiceDefinitionFromAnalyze(
        AnalyzeResult(
          durationSec: result.durationSec,
          bpm: bpm,
          chords: result.chords,
          strums: result.strums,
          beatsPerBar: result.beatsPerBar,
          diagnostics: result.diagnostics,
        ),
        sourceId: 'fallback',
        title: 't',
      );
      return _ok(r);
    }

    test('bpm=0 falls back to 90 BPM', () async {
      final def = await build(0.0);
      expect(def.defaultTempo.bpm, 90.0);
    });

    test('bpm=400 falls back to 90 BPM', () async {
      final def = await build(400.0);
      expect(def.defaultTempo.bpm, 90.0);
    });

    test('bpm=NaN falls back to 90 BPM', () async {
      final def = await build(double.nan);
      expect(def.defaultTempo.bpm, 90.0);
    });

    test('bpm=80 is preserved', () async {
      final def = await build(80.0);
      expect(def.defaultTempo.bpm, 80.0);
    });
  });

  group('practiceDefinitionFromAnalyze — tick collision forward-push', () {
    test('two strums 0.0005s apart push the second onto the next tick', () {
      // 480 PPQ at 90 BPM → tick ≈ 1.388... ms; two strums 0.0005s apart will
      // both round to the same tick; the second must be pushed forward by 1.
      const result = AnalyzeResult(
        durationSec: 1.0,
        bpm: 90.0,
        chords: [TimelineChord(label: 'C', startSec: 0.0, endSec: 1.0)],
        strums: [
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.0,
            confidence: 0.9,
          ),
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.0005,
            confidence: 0.9,
          ),
        ],
      );
      final def = _ok(
        practiceDefinitionFromAnalyze(result, sourceId: 'tight', title: 't'),
      );
      expect(def.events, hasLength(2));
      expect(def.events[1].position.ticks, def.events[0].position.ticks + 1);
      expect(def.validate(), isEmpty);
    });
  });

  group('practiceDefinitionFromAnalyze — empty strum list', () {
    test('falls back to freePractice + open scoring + no events', () {
      const result = AnalyzeResult(
        durationSec: 0.0,
        bpm: 90.0,
        chords: [],
        strums: [],
      );
      final def = _ok(
        practiceDefinitionFromAnalyze(
          result,
          sourceId: 'empty-clip',
          title: 't',
        ),
      );
      expect(def.events, isEmpty);
      expect(def.mode, PracticeMode.freePractice);
      expect(def.scoringProfile, ScoringProfile.freePracticeOpen);
      expect(def.validate(), isEmpty);
    });

    test('all-non-finite strums are dropped, triggering empty-branch', () {
      const result = AnalyzeResult(
        durationSec: 0.0,
        bpm: 90.0,
        chords: [],
        strums: [
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: double.nan,
            confidence: 0.9,
          ),
        ],
      );
      final def = _ok(
        practiceDefinitionFromAnalyze(result, sourceId: 'nans', title: 't'),
      );
      expect(def.events, isEmpty);
      expect(def.mode, PracticeMode.freePractice);
    });
  });

  group('practiceDefinitionFromAnalyze — controlled failure modes', () {
    test('blank sourceId is rejected', () {
      const result = AnalyzeResult(
        durationSec: 1.0,
        bpm: 90.0,
        chords: [],
        strums: [],
      );
      final r = practiceDefinitionFromAnalyze(
        result,
        sourceId: '   ',
        title: 't',
      );
      expect(r.isFailure, isTrue);
      expect(_err(r).code, FailureCode.practiceContentUnsupported);
    });

    test('out-of-range beatsPerBar is rejected', () {
      const result = AnalyzeResult(
        durationSec: 1.0,
        bpm: 90.0,
        chords: [],
        strums: [],
        beatsPerBar: 99,
      );
      final r = practiceDefinitionFromAnalyze(
        result,
        sourceId: 'bad-bpb',
        title: 't',
      );
      expect(r.isFailure, isTrue);
      expect(_err(r).code, FailureCode.practiceContentUnsupported);
    });
  });

  group('practiceDefinitionFromAnalyze — in-loop timeline grow', () {
    test('totalBeats grows by one bar when rounding lands on the bound', () {
      // 120 BPM, 4/4; t0 = 0.0. Strum at 1.99995 s →
      // beat = 1.99995 / 0.5 = 3.9999 → tick 1920. Initial bound = 1 bar =
      // 1920 ticks. tick (1920) >= totalBeatsTicks (1920) → in-loop grow →
      // 3840. Both events stay, no drop, validate() empty.
      const result = AnalyzeResult(
        durationSec: 2.0,
        bpm: 120.0,
        chords: [TimelineChord(label: 'Em', startSec: 0.0, endSec: 2.0)],
        strums: [
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.0,
            confidence: 0.9,
          ),
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 1.99995,
            confidence: 0.9,
          ),
        ],
      );
      final def = _ok(
        practiceDefinitionFromAnalyze(
          result,
          sourceId: 'grow-on-bound',
          title: 't',
        ),
      );
      expect(def.events, hasLength(2));
      expect(def.events[0].position.ticks, 0);
      expect(def.events[1].position.ticks, 1920);
      expect(def.totalBeats.ticks, 3840); // 8.0 beats
      expect(def.validate(), isEmpty);
    });
  });

  group('practiceDefinitionFromAnalyze — t0 normalization', () {
    test(
      'non-zero t0 normalizes times, and last tick at bound-1 keeps totalBeats at 4.0',
      () {
        // 120 BPM, 4/4; t0 = 1.7. Four strums:
        //   1.7            → beat 0.0      → tick    0
        //   2.2            → beat 1.0      → tick  480
        //   2.7            → beat 2.0      → tick  960
        //   3.6989583333…  → beat ~3.9979  → tick 1919  (last valid tick before
        //                                            the exclusive 1-bar bound)
        // Initial bound = 1 bar = 1920 ticks. The last tick sits exactly one
        // below the exclusive bound — the post-loop block must NOT grow the
        // timeline; totalBeats stays at 4.0.
        const result = AnalyzeResult(
          durationSec: 4.0,
          bpm: 120.0,
          chords: [TimelineChord(label: 'C', startSec: 1.7, endSec: 4.0)],
          strums: [
            TimelineStrum(
              direction: StrumDirection.down,
              timeSec: 1.7,
              confidence: 0.9,
            ),
            TimelineStrum(
              direction: StrumDirection.down,
              timeSec: 2.2,
              confidence: 0.9,
            ),
            TimelineStrum(
              direction: StrumDirection.down,
              timeSec: 2.7,
              confidence: 0.9,
            ),
            TimelineStrum(
              direction: StrumDirection.down,
              timeSec: 3.6989583333333334,
              confidence: 0.9,
            ),
          ],
        );
        final def = _ok(
          practiceDefinitionFromAnalyze(
            result,
            sourceId: 'late-t0',
            title: 't',
          ),
        );
        expect(def.events, hasLength(4));
        expect(def.events[0].position.ticks, 0);
        expect(def.events[1].position.ticks, 480);
        expect(def.events[2].position.ticks, 960);
        expect(def.events[3].position.ticks, 1919);
        expect(def.totalBeats.ticks, 1920); // 4.0 beats — must NOT be 8.0
        expect(def.validate(), isEmpty);
      },
    );
  });

  group('practiceDefinitionFromAnalyze — definition surface', () {
    test('source, difficulty, keys, tags match ADR contract', () {
      const result = AnalyzeResult(
        durationSec: 1.0,
        bpm: 90.0,
        chords: [TimelineChord(label: 'C', startSec: 0.0, endSec: 1.0)],
        strums: [
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.0,
            confidence: 0.9,
          ),
        ],
      );
      final def = _ok(
        practiceDefinitionFromAnalyze(
          result,
          sourceId: 'surf',
          title: 'Surf Title',
        ),
      );
      expect(def.source, PracticeSource.analyze);
      expect(def.difficulty, PracticeDifficulty.intermediate);
      expect(def.titleKey, 'practiceSourceAnalyzeTitle');
      expect(def.descriptionKey, 'practiceSourceAnalyzeDescription');
      expect(def.skillTags, ['analyzeImport']);
      expect(def.displayTitle, 'Surf Title');
    });
  });
}
