// Crediting strokes to the grid, under the honesty rules.
//
// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md`
// §2 (honesty) and §3 (the rhythm pillar). These cells exist because every one
// of them is a place where the flattering or the punishing choice was available.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

const _d = StrumDirection.down;
const _u = StrumDirection.up;

/// Four down-strokes on the beat, at 120 bpm: 0, 500, 1000, 1500 ms.
RhythmGrid _downQuarters() => RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.quarter,
  struck: List<bool>.filled(4, true),
);

/// Continuous eighths at 120 bpm: every 250 ms.
RhythmGrid _eighths() => RhythmGrid.pendulum(
  subdivision: RhythmSubdivision.eighth,
  struck: List<bool>.filled(8, true),
);

DetectedStroke _stroke(
  int ms,
  StrumDirection direction, {
  bool confirmed = true,
}) => DetectedStroke(
  atUs: ms * 1000,
  direction: direction,
  isConfirmed: confirmed,
);

/// A clean run of [grid]'s notated slots, right on the beat.
List<DetectedStroke> _perfect(
  RhythmGrid grid, {
  double bpm = 120,
  int bars = 1,
  bool confirmed = true,
}) => [
  for (var bar = 0; bar < bars; bar++)
    for (final slot in grid.slots)
      if (slot.isStruck)
        DetectedStroke(
          atUs: grid.onsetUs(bar: bar, slotIndex: slot.index, bpm: bpm),
          direction: slot.direction,
          isConfirmed: confirmed,
        ),
];

void main() {
  group('a clean attempt', () {
    test('every stroke is credited, accuracy 1.0, coverage 1.0', () {
      final grid = _downQuarters();
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: _perfect(grid),
      );
      expect(attempt.credited, 4);
      expect(attempt.directionAccuracy, 1.0);
      expect(attempt.coverage, 1.0);
      expect(attempt.isReportable, isTrue);
      expect(attempt.extraConfirmedStrokes, 0);
    });

    test('ghost slots are not graded at all', () {
      // The grid asked for no sound there, so there is nothing to miss.
      final grid = RhythmGrid.pendulum(
        subdivision: RhythmSubdivision.eighth,
        struck: const [true, false, true, true, false, true, true, true],
      );
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: _perfect(grid),
      );
      expect(attempt.notatedStrokes, 6);
      expect(attempt.credited, 6);
      expect(attempt.slots.map((slot) => slot.slotIndex), [0, 2, 3, 5, 6, 7]);
    });

    test('several bars are graded, each slot addressed by bar', () {
      final grid = _downQuarters();
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 3,
        strokes: _perfect(grid, bars: 3),
      );
      expect(attempt.credited, 12);
      expect(attempt.slots.last.bar, 2);
      expect(attempt.slots.last.slotIndex, 3);
    });
  });

  group('the window is the MEASURED one', () {
    test('the tolerance is the recogniser`s own 50 ms', () {
      // Not a curriculum-specific guess: `onsetTolerance50Ms` in the release
      // gate, `toleranceUs: 50000` in the real-audio harness.
      expect(rhythmToleranceUs, 50000);
    });

    test('50 ms early or late still counts; 51 does not', () {
      final grid = _downQuarters();
      for (final offset in [-50, -1, 0, 1, 50]) {
        final attempt = gradeRhythm(
          grid,
          bpm: 120,
          bars: 1,
          strokes: [_stroke(500 + offset, _d)],
        );
        expect(attempt.credited, 1, reason: 'offset $offset ms');
      }
      final late = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: [_stroke(551, _d)],
      );
      expect(late.credited, 0);
      expect(late.extraConfirmedStrokes, 1);
    });
  });

  group('a wrong direction is reported, and costs nothing', () {
    test('an upstroke where a downstroke was asked is wrongDirection', () {
      // The headline capability: only this app can tell a learner this.
      final attempt = gradeRhythm(
        _downQuarters(),
        bpm: 120,
        bars: 1,
        strokes: [_stroke(0, _u), _stroke(500, _d)],
      );
      expect(attempt.wrongDirection, 1);
      expect(attempt.credited, 1);
      expect(attempt.slots.first.expected, _d);
      expect(attempt.slots.first.detected, _u);
    });

    test('accuracy never goes below zero, and a wrong stroke is still heard', () {
      // "Costs nothing" means it does not subtract from anything else — it does
      // not mean it is hidden. A wrong stroke IS evidence, so it counts toward
      // coverage while lowering accuracy.
      final grid = _downQuarters();
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: [
          for (final at in [0, 500, 1000, 1500]) _stroke(at, _u),
        ],
      );
      expect(attempt.directionAccuracy, 0.0);
      expect(attempt.coverage, 1.0);
      expect(attempt.isReportable, isTrue);
    });
  });

  group('rule 1 and 2: nothing is claimed without confirmed evidence', () {
    test('an unconfirmed stroke in the window is unclear, not credit', () {
      final attempt = gradeRhythm(
        _downQuarters(),
        bpm: 120,
        bars: 1,
        strokes: [_stroke(0, _d, confirmed: false)],
      );
      expect(attempt.credited, 0);
      expect(attempt.unclear, 1);
      expect(attempt.slots.first.detected, isNull);
    });

    test('an unconfirmed WRONG stroke is never reported as wrong', () {
      // Rule 2: the app never says "you strummed up instead of down" unless the
      // decision was confirmed. An unconfirmed up-stroke is simply unclear.
      final attempt = gradeRhythm(
        _downQuarters(),
        bpm: 120,
        bars: 1,
        strokes: [_stroke(0, _u, confirmed: false)],
      );
      expect(attempt.wrongDirection, 0);
      expect(attempt.unclear, 1);
      expect(attempt.slots.first.detected, isNull);
    });

    test('an unconfirmed twin never displaces the confirmed stroke', () {
      // The engine can surface one physical stroke as two detections. Were the
      // nearest one picked regardless, an unconfirmed twin 5 ms closer would
      // throw away credit the learner earned.
      final attempt = gradeRhythm(
        _downQuarters(),
        bpm: 120,
        bars: 1,
        strokes: [_stroke(495, _d, confirmed: false), _stroke(510, _d)],
      );
      expect(attempt.credited, 1);
      expect(attempt.unclear, 0);
    });

    test('an attempt nobody could hear claims nothing at all', () {
      final attempt = gradeRhythm(
        _downQuarters(),
        bpm: 120,
        bars: 1,
        strokes: const [],
      );
      expect(attempt.directionAccuracy, isNull, reason: 'not 0.0');
      expect(attempt.noEvidence, 4);
      expect(attempt.coverage, 0.0);
      expect(attempt.isReportable, isFalse);
    });
  });

  group('a missed slot subtracts nothing, but cannot look perfect', () {
    test('two clean strokes of eight: accuracy 1.0 but coverage 0.25', () {
      // This pair of numbers is the whole design. Accuracy answers "of what I
      // heard, how much was right"; coverage answers "how much did I hear".
      // Without the second number, playing a quarter of the pattern would read
      // as flawless.
      final grid = _eighths();
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: [_stroke(0, _d), _stroke(250, _u)],
      );
      expect(attempt.directionAccuracy, 1.0);
      expect(attempt.coverage, 0.25);
      expect(attempt.isReportable, isFalse, reason: 'too little to judge on');
      expect(attempt.noEvidence, 6);
    });

    test('the majority rule: half the pattern is enough, less is not', () {
      final grid = _eighths();
      RhythmAttempt withFirst(int count) => gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: _perfect(grid).take(count).toList(),
      );
      expect(withFirst(4).coverage, 0.5);
      expect(withFirst(4).isReportable, isTrue);
      expect(withFirst(3).isReportable, isFalse);
      expect(minimumRhythmCoverage, 0.5);
    });

    test('a missed slot does not lower accuracy', () {
      // Three heard and correct, one silent: the silence is not a wrong stroke.
      final grid = _downQuarters();
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: [_stroke(0, _d), _stroke(500, _d), _stroke(1000, _d)],
      );
      expect(attempt.directionAccuracy, 1.0);
      expect(attempt.coverage, 0.75);
    });
  });

  group('pairing uses time only, never direction', () {
    test('a swapped pair is reported as two wrong strokes, not re-paired', () {
      // Down then up was asked; up then down was played. Re-assigning each
      // stroke to the slot whose direction it matches would hand the learner
      // two correct strokes for a genuinely wrong performance.
      final grid = _eighths();
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: [_stroke(0, _u), _stroke(250, _d)],
      );
      expect(attempt.credited, 0);
      expect(attempt.wrongDirection, 2);
      expect(attempt.slots[0].detected, _u);
      expect(attempt.slots[1].detected, _d);
    });
  });

  group('maximum-cardinality matching, for the learner`s benefit', () {
    test('L269`s shape: both strokes are credited, not one', () {
      // Expected 500 and 540 ms; played 490 and 545. Taking the locally nearest
      // pair first (500↔490, then 540↔545) happens to work here, but the
      // reverse ordering does not — and under-counting would tell the learner
      // they missed a stroke they played. The shared maximum-cardinality helper
      // is what rules that out.
      final grid = RhythmGrid.authored(
        subdivision: RhythmSubdivision.eighth,
        beatsPerBar: 1,
        strokes: const [_d, _u],
      );
      // One beat of eighths at 120 bpm: slots at 0 and 250 ms.
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: [_stroke(40, _d), _stroke(210, _u)],
      );
      expect(attempt.credited, 2);
    });

    test('one stroke cannot satisfy two slots', () {
      // At 240 bpm eighth slots are 125 ms apart, so a single stroke sits
      // inside both windows. It may only be credited once.
      final grid = _eighths();
      final attempt = gradeRhythm(
        grid,
        bpm: 240,
        bars: 1,
        strokes: [_stroke(125, _u)],
      );
      expect(attempt.credited, 1);
      expect(attempt.noEvidence, 7);
    });
  });

  group('extra strokes are reported, never punished', () {
    test('a stroke where the pattern asked for silence is extra', () {
      final grid = RhythmGrid.pendulum(
        subdivision: RhythmSubdivision.eighth,
        struck: const [true, false, true, false, true, false, true, false],
      );
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: [..._perfect(grid), _stroke(250, _u)],
      );
      expect(attempt.credited, 4);
      expect(attempt.extraConfirmedStrokes, 1);
      expect(attempt.directionAccuracy, 1.0, reason: 'extras do not subtract');
      expect(attempt.coverage, 1.0);
    });

    test('an unconfirmed extra is not even counted as extra', () {
      final grid = _downQuarters();
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: [..._perfect(grid), _stroke(2500, _d, confirmed: false)],
      );
      expect(attempt.extraConfirmedStrokes, 0);
    });
  });

  group('inputs', () {
    test('startUs shifts the whole grid', () {
      final grid = _downQuarters();
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        startUs: 3000000,
        strokes: [_stroke(3000, _d), _stroke(3500, _d)],
      );
      expect(attempt.credited, 2);
    });

    test('an attempt needs at least one bar', () {
      expect(
        () =>
            gradeRhythm(_downQuarters(), bpm: 120, bars: 0, strokes: const []),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('strokes need not arrive in time order', () {
      final grid = _downQuarters();
      final attempt = gradeRhythm(
        grid,
        bpm: 120,
        bars: 1,
        strokes: [_stroke(1500, _d), _stroke(0, _d), _stroke(1000, _d)],
      );
      expect(attempt.credited, 3);
    });
  });

  group('the four modes', () {
    test('the teaching order is the declaration order, and is pinned', () {
      expect(RhythmMode.values.map((mode) => mode.step), [1, 2, 3, 4]);
      expect(RhythmMode.values, [
        RhythmMode.mutedStrokes,
        RhythmMode.silentGrid,
        RhythmMode.withChord,
        RhythmMode.listenAndRepeat,
      ]);
    });

    test('only the with-chord mode scores a chord', () {
      // A damped string has no chord to name, so the muted modes cannot score
      // one — claiming otherwise would be scoring a label the engine cannot
      // produce.
      expect(RhythmMode.values.where((mode) => mode.scoresChord), [
        RhythmMode.withChord,
      ]);
      expect(
        RhythmMode.withChord.requiredCapabilities,
        contains(ExerciseCapability.supportsChordScoring),
      );
      expect(
        RhythmMode.mutedStrokes.requiredCapabilities,
        isNot(contains(ExerciseCapability.supportsChordScoring)),
      );
    });

    test('every mode needs a microphone, direction scoring and offline', () {
      for (final mode in RhythmMode.values) {
        expect(
          mode.requiredCapabilities,
          containsAll(const [
            ExerciseCapability.requiresMicrophone,
            ExerciseCapability.supportsDirectionScoring,
            ExerciseCapability.supportsOffline,
          ]),
          reason: mode.code,
        );
      }
    });

    test('listen-and-repeat hides the notation and plays first', () {
      // Otherwise the whole pillar could be passed by reading alone.
      expect(RhythmMode.listenAndRepeat.showsArrowRow, isFalse);
      expect(RhythmMode.listenAndRepeat.demonstratesFirst, isTrue);
      expect(RhythmMode.values.where((mode) => mode.demonstratesFirst), [
        RhythmMode.listenAndRepeat,
      ]);
    });

    test('codes are stable and round-trip; an unknown code is null', () {
      for (final mode in RhythmMode.values) {
        expect(RhythmMode.fromCode(mode.code), mode);
        expect(mode.code, startsWith('rhythm.'));
      }
      expect(
        RhythmMode.fromCode('rhythm.nope'),
        isNull,
        reason: 'resolving to a default would silently change the exercise',
      );
    });
  });
  _timingGroup();
}

void _timingGroup() {
  // Down-quarters at 120 bpm: notated onsets at 0, 500, 1000, 1500 ms.
  RhythmGrid grid() => RhythmGrid.pendulum(
    subdivision: RhythmSubdivision.quarter,
    struck: const [true, true, true, true],
  );

  List<DetectedStroke> strokesAt(List<int> msList) => [
    for (final ms in msList)
      DetectedStroke(
        atUs: ms * 1000,
        direction: StrumDirection.down,
        isConfirmed: true,
      ),
  ];

  group('timing is reported ONLY when the device is calibrated', () {
    test('uncalibrated: every slot error is null and no timing is claimed', () {
      final attempt = gradeRhythm(
        grid(),
        bpm: 120,
        bars: 1,
        strokes: strokesAt([10, 510, 1010, 1510]),
      );
      expect(attempt.credited, 4, reason: 'direction still graded');
      expect(attempt.timingErrorsUs, isEmpty);
      expect(attempt.meanAbsTimingErrorUs, isNull);
      expect(attempt.timingBiasUs, isNull);
      expect(attempt.hasTimingReport, isFalse);
      // An uncalibrated error figure would be the device's skew as much as the
      // learner's playing — a claim with no evidence behind it.
      expect(attempt.slots.every((slot) => slot.errorUs == null), isTrue);
    });

    test('calibrated: the signed error of each heard slot is reported', () {
      final attempt = gradeRhythm(
        grid(),
        bpm: 120,
        bars: 1,
        strokes: strokesAt([10, 510, 1010, 1510]),
        timingCalibrationUs: 0,
      );
      expect(attempt.timingErrorsUs, [10000, 10000, 10000, 10000]);
      expect(attempt.meanAbsTimingErrorUs, 10000);
      expect(attempt.timingBiasUs, 10000, reason: 'consistently 10 ms late');
      expect(attempt.hasTimingReport, isTrue);
    });

    test('a calibration of zero is NOT the same as no calibration', () {
      // The distinction the API has to keep: 0 means "measured, and it is zero",
      // null means "never measured". Collapsing them would let an uncalibrated
      // device publish a timing score.
      final uncalibrated = gradeRhythm(
        grid(),
        bpm: 120,
        bars: 1,
        strokes: strokesAt([0, 500, 1000, 1500]),
      );
      final calibratedAtZero = gradeRhythm(
        grid(),
        bpm: 120,
        bars: 1,
        strokes: strokesAt([0, 500, 1000, 1500]),
        timingCalibrationUs: 0,
      );
      expect(uncalibrated.hasTimingReport, isFalse);
      expect(calibratedAtZero.hasTimingReport, isTrue);
      expect(calibratedAtZero.meanAbsTimingErrorUs, 0);
    });
  });

  test('the calibration rescues an attempt a skew would have thrown away', () {
    // THE cell this feature exists for. A device whose display↔microphone skew
    // is 80 ms puts every stroke outside the 50 ms window, so NOTHING pairs:
    // coverage collapses and the screen tells a learner who played the pattern
    // correctly that it could not hear enough of it.
    final late80 = strokesAt([80, 580, 1080, 1580]);

    final uncorrected = gradeRhythm(grid(), bpm: 120, bars: 1, strokes: late80);
    expect(uncorrected.heard, 0);
    expect(uncorrected.coverage, 0);
    expect(
      uncorrected.isReportable,
      isFalse,
      reason: 'correct playing, declared unhearable — the bug being fixed',
    );

    final corrected = gradeRhythm(
      grid(),
      bpm: 120,
      bars: 1,
      strokes: late80,
      timingCalibrationUs: 80000,
    );
    expect(corrected.credited, 4);
    expect(corrected.coverage, 1.0);
    expect(corrected.meanAbsTimingErrorUs, 0);
    expect(
      corrected.timingBiasUs,
      0,
      reason: 'what the learner FELT as together now reads as together',
    );
  });

  test('bias and spread are separated, because they mean different things', () {
    // Scattered by ±30 ms with no systematic lag: mean absolute error 30 ms,
    // bias ~0. A learner here is UNSTEADY. A single number would be
    // indistinguishable from someone steadily 30 ms late, whose fix is the
    // opposite kind of practice.
    final attempt = gradeRhythm(
      grid(),
      bpm: 120,
      bars: 1,
      strokes: strokesAt([30, 470, 1030, 1470]),
      timingCalibrationUs: 0,
    );
    expect(attempt.meanAbsTimingErrorUs, 30000);
    expect(attempt.timingBiasUs, 0);
  });

  test('a thin attempt claims no timing even when calibrated', () {
    // Coverage floor outranks the calibration: one clean stroke of four is not
    // grounds for a verdict about someone's timing.
    final attempt = gradeRhythm(
      grid(),
      bpm: 120,
      bars: 1,
      strokes: strokesAt([0]),
      timingCalibrationUs: 0,
    );
    expect(attempt.timingErrorsUs, hasLength(1));
    expect(attempt.isReportable, isFalse);
    expect(attempt.hasTimingReport, isFalse);
  });
}
