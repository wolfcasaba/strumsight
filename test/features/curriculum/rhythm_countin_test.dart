// The count-in before bar 1.
//
// The cells that matter here are the ones where the OBVIOUS implementation is
// pedagogically wrong: a fixed four-beat count-in over a 3/4 exercise, a
// count-in at the subdivision for an eighth-note exercise, a parked hand, and a
// cutoff at exactly zero that deletes the rushed first stroke.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_countin.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_grading.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_grid.dart';

void main() {
  const beat = Duration(milliseconds: 500); // 120 bpm

  group('the metre decides the length, not a constant', () {
    test('4/4 counts four', () {
      final grid = RhythmGrid.pendulum(
        subdivision: RhythmSubdivision.quarter,
        struck: const [true, true, true, true],
      );
      expect(RhythmCountIn.forGrid(grid).beats, 4);
    });

    test('the 3/4 waltz counts THREE — the taught counterexample', () {
      // `D-U-U` in 3/4 is a pattern this course actually teaches. A hard-coded
      // four-beat count-in would have the app present it as 4/4 and then
      // contradict itself at bar 1.
      final waltz = RhythmGrid.authored(
        subdivision: RhythmSubdivision.quarter,
        beatsPerBar: 3,
        strokes: const [
          StrumDirection.down,
          StrumDirection.up,
          StrumDirection.up,
        ],
      );
      expect(RhythmCountIn.forGrid(waltz).beats, 3);
      expect(
        RhythmCountIn.forGrid(waltz).durationAt(beat),
        const Duration(milliseconds: 1500),
      );
    });
  });

  test('an eighth-note exercise still counts in on the BEAT', () {
    // Pedagogy is ordered: count "1 2 3 4" first, then ADD the "and". A count-in
    // at the subdivision would present the eighths as the pulse — the very
    // confusion that makes beginners' eighths uneven.
    final eighths = RhythmGrid.pendulum(
      subdivision: RhythmSubdivision.eighth,
      struck: const [true, true, true, true, true, true, true, true],
    );
    final countIn = RhythmCountIn.forGrid(eighths);
    expect(countIn.beats, 4, reason: 'four numbers, not eight');
    expect(countIn.durationAt(beat), const Duration(milliseconds: 2000));
  });

  group('the numbers spoken', () {
    const countIn = RhythmCountIn(beats: 4);

    test('are one-based, because that is how they are spoken', () {
      expect(countIn.numberAt(position: Duration.zero, beatDuration: beat), 1);
    });

    test('advance once per beat', () {
      for (var i = 0; i < 4; i++) {
        expect(countIn.numberAt(position: beat * i, beatDuration: beat), i + 1);
        // And mid-beat still shows the same number.
        expect(
          countIn.numberAt(
            position: beat * i + const Duration(milliseconds: 200),
            beatDuration: beat,
          ),
          i + 1,
        );
      }
    });

    test('stop exactly at bar 1 beat 1 — the count-in does not overlap it', () {
      expect(countIn.numberAt(position: beat * 4, beatDuration: beat), isNull);
      expect(
        countIn.numberAt(position: beat * 4 + beat, beatDuration: beat),
        isNull,
      );
    });

    test('are absent before playback and without a tempo', () {
      expect(
        countIn.numberAt(
          position: const Duration(seconds: -1),
          beatDuration: beat,
        ),
        isNull,
      );
      expect(
        countIn.numberAt(position: Duration.zero, beatDuration: Duration.zero),
        isNull,
        reason: 'no tempo is a real runtime state, not a programmer error',
      );
    });
  });

  test('the hand swings through the count-in and strikes nothing', () {
    // Our own model: the hand never stops, and a missed stroke is a GHOST the
    // hand still travels through. A parked pendulum would make the learner start
    // their arm from rest on beat 1 — the cold start the count-in prevents.
    const countIn = RhythmCountIn(beats: 3);
    expect(countIn.crossingCount, 6, reason: 'down and up on each of three');
    expect(countIn.ghostCrossings, [false, false, false, false, false, false]);
  });

  group('the exercise timeline starts at bar 1, not at the button', () {
    const countIn = RhythmCountIn(beats: 4);

    test('is negative throughout the count-in', () {
      expect(
        countIn.exercisePosition(position: Duration.zero, beatDuration: beat),
        const Duration(milliseconds: -2000),
      );
    });

    test('is exactly zero at bar 1 beat 1', () {
      expect(
        countIn.exercisePosition(position: beat * 4, beatDuration: beat),
        Duration.zero,
      );
    });
  });

  group('which strokes count toward the attempt', () {
    test('a stroke in the middle of the count-in does not', () {
      // Strumming along while counting is not a mistake, so it is dropped
      // rather than graded as a wrong-direction stroke.
      expect(
        RhythmCountIn.countsTowardAttempt(
          atUs: -800000,
          toleranceUs: rhythmToleranceUs,
        ),
        isFalse,
      );
    });

    test('a stroke just BEFORE beat 1 does — it is beat 1, played early', () {
      // The cell this file exists for. Cutting at zero would delete exactly the
      // rushed first stroke a beginner most often plays, and then report perfect
      // coverage of a bar they actually fluffed.
      expect(
        RhythmCountIn.countsTowardAttempt(
          atUs: -30000,
          toleranceUs: rhythmToleranceUs,
        ),
        isTrue,
      );
    });

    test('the boundary is the tolerance window itself', () {
      expect(
        RhythmCountIn.countsTowardAttempt(
          atUs: -rhythmToleranceUs,
          toleranceUs: rhythmToleranceUs,
        ),
        isTrue,
      );
      expect(
        RhythmCountIn.countsTowardAttempt(
          atUs: -rhythmToleranceUs - 1,
          toleranceUs: rhythmToleranceUs,
        ),
        isFalse,
      );
    });

    test('everything from bar 1 onward counts', () {
      expect(
        RhythmCountIn.countsTowardAttempt(
          atUs: 0,
          toleranceUs: rhythmToleranceUs,
        ),
        isTrue,
      );
      expect(
        RhythmCountIn.countsTowardAttempt(
          atUs: 5000000,
          toleranceUs: rhythmToleranceUs,
        ),
        isTrue,
      );
    });
  });

  test('a count-in of no beats is refused', () {
    expect(() => RhythmCountIn(beats: 0), throwsA(isA<AssertionError>()));
  });
}
