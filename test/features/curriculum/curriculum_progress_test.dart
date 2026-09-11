// MEASUREMENT: does playing well actually open the next rung, and when?
//
// Every number in here is produced by the shipped parts — the real
// `beginnerCourse`, the real `gradeRhythm`, the real `SkillEstimateReducer` and
// the real `EvidenceWeightPolicy`. None of it is asserted from the design's
// intent; the cells print what the chain does and then pin it.
//
// That matters because "how many good attempts open the next rung" is nowhere
// written down. It EMERGES from three policies that were each set for their own
// reasons — the per-record influence cap, the state thresholds, and the course's
// own `minimumState` / `minimumLevel` gate — and a number nobody has looked at is
// a number nobody can defend to a learner.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/curriculum/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

final DateTime _start = DateTime.utc(2026, 9, 12, 10);

RhythmGrid _gridOf(CurriculumMission mission) => mission.rhythm!.grid;

/// [heard] of the notated slots of one bar played cleanly; the rest silent.
List<DetectedStroke> _strokes(
  CurriculumMission mission, {
  required int heard,
  bool flipDirection = false,
}) {
  final grid = _gridOf(mission);
  final bpm = mission.rhythm!.bpm;
  final bars = mission.rhythm!.bars;
  final slots = <DetectedStroke>[];
  for (var bar = 0; bar < bars; bar++) {
    for (final slot in grid.slots.where((slot) => slot.isStruck)) {
      slots.add(
        DetectedStroke(
          atUs: grid.onsetUs(bar: bar, slotIndex: slot.index, bpm: bpm),
          direction: flipDirection
              ? (slot.direction == StrumDirection.down
                    ? StrumDirection.up
                    : StrumDirection.down)
              : slot.direction,
          isConfirmed: true,
        ),
      );
    }
  }
  return slots.take(heard).toList();
}

RhythmAttempt _attempt(
  CurriculumMission mission, {
  int? heard,
  bool flipDirection = false,
}) {
  final notated =
      _gridOf(mission).slots.where((slot) => slot.isStruck).length *
      mission.rhythm!.bars;
  return gradeRhythm(
    _gridOf(mission),
    bpm: mission.rhythm!.bpm,
    bars: mission.rhythm!.bars,
    strokes: _strokes(
      mission,
      heard: heard ?? notated,
      flipDirection: flipDirection,
    ),
  );
}

CurriculumMission _mission(Course course, String id) =>
    course.missionsInOrder.firstWhere((m) => m.missionId == id);

void main() {
  final course = beginnerCourse();
  // The one chain that works end to end today: the always-open first rhythm rung
  // trains the skill the second rhythm rung is gated on.
  final rungOne = _mission(course, 'mission.downQuarters');
  final rungTwo = _mission(course, 'mission.downUpEighths');

  CurriculumProgress progress() => CurriculumProgress(
    evidenceRepository: InMemoryPracticeEvidenceRepository(),
  );

  /// Plays [count] clean attempts a day apart and returns the estimates.
  Map<String, SkillEstimate> playClean(
    CurriculumProgress subject, {
    required int count,
    int? heard,
    bool flipDirection = false,
    DateTime? asOf,
  }) {
    for (var i = 0; i < count; i++) {
      subject.recordRhythmAttempt(
        mission: rungOne,
        attempt: _attempt(rungOne, heard: heard, flipDirection: flipDirection),
        // A day apart, because the reducer buckets evidence by `measuredAt`:
        // identical instants would land in one bucket and read as a conflict
        // rather than as a series. Real attempts are never simultaneous.
        at: _start.add(Duration(days: i)),
      );
    }
    return subject.estimatesFor(
      course,
      asOf: asOf ?? _start.add(Duration(days: count)),
    );
  }

  group('MEASURE: how many clean attempts open the next rung', () {
    test(
      'the gate opens at a measured number of attempts, not an assumed one',
      () {
        int? opensAt;
        for (var attempts = 1; attempts <= 6; attempts++) {
          final estimates = playClean(progress(), count: attempts);
          final estimate = estimates[rungOne.trainedSkillIds.single]!;
          final open = rungTwo.unlock.isSatisfiedBy(estimates);
          // ignore: avoid_print
          print(
            '$attempts clean attempt(s): state ${estimate.state.name}, '
            'level ${estimate.level?.toStringAsFixed(3)}, '
            'uncertainty ${estimate.uncertainty.toStringAsFixed(3)} '
            '-> rung two ${open ? "OPEN" : "not yet"}',
          );
          if (open && opensAt == null) opensAt = attempts;
        }
        expect(
          opensAt,
          isNotNull,
          reason:
              'if no number of clean attempts opened the rung, the ladder would '
              'be a map of a path nobody can walk',
        );
        // Pinned so a policy change that moves it has to be a deliberate act.
        // TWO is also defensible as pedagogy: one good run can be luck, and
        // `UnlockRule`'s own doc says the gate is confidence rather than a hit
        // count — `initial` (exactly one observation) is deliberately below
        // `emerging`, which is what makes a second attempt necessary.
        expect(opensAt, 2);
      },
    );

    test(
      'one attempt is not enough, and the reason is stated in the state',
      () {
        final estimates = playClean(progress(), count: 1);
        final estimate = estimates[rungOne.trainedSkillIds.single]!;
        expect(estimate.state, SkillEstimateState.initial);
        expect(rungTwo.unlock.isSatisfiedBy(estimates), isFalse);
      },
    );
  });

  group('MEASURE: the per-record influence cap binds, so confidence currently '
      'changes nothing', () {
    test('a 50%-coverage run and a perfect one produce the SAME level', () {
      final notated =
          _gridOf(rungOne).slots.where((slot) => slot.isStruck).length *
          rungOne.rhythm!.bars;
      final full = playClean(progress(), count: 2);
      final half = playClean(progress(), count: 2, heard: notated ~/ 2);

      final fullLevel = full[rungOne.trainedSkillIds.single]!.level;
      final halfLevel = half[rungOne.trainedSkillIds.single]!.level;
      // ignore: avoid_print
      print(
        'coverage 1.0 -> level ${fullLevel?.toStringAsFixed(4)}; '
        'coverage 0.5 -> level ${halfLevel?.toStringAsFixed(4)}',
      );
      expect(
        halfLevel,
        fullLevel,
        reason:
            'the 0.25 per-record cap binds for every attempt that clears the '
            'coverage floor, so the confidence field is recorded truthfully but '
            'does not tune the estimate — written down here so nobody later '
            'believes it is doing work it is not',
      );
    });
  });

  group('MEASURE: a rung never opens on the wrong evidence', () {
    test(
      'strokes heard travelling the WRONG way do not open it, however many',
      () {
        final estimates = playClean(progress(), count: 6, flipDirection: true);
        final estimate = estimates[rungOne.trainedSkillIds.single]!;
        // ignore: avoid_print
        print(
          '6 wrong-direction attempts: state ${estimate.state.name}, '
          'level ${estimate.level?.toStringAsFixed(3)}',
        );
        expect(rungTwo.unlock.isSatisfiedBy(estimates), isFalse);
      },
    );

    test('attempts below the coverage floor write nothing, so the skill stays '
        'unknown and the rung stays shut', () {
      final subject = progress();
      for (var i = 0; i < 6; i++) {
        final written = subject.recordRhythmAttempt(
          mission: rungOne,
          attempt: _attempt(rungOne, heard: 1),
          at: _start.add(Duration(days: i)),
        );
        expect(written, isEmpty);
      }
      final estimates = subject.estimatesFor(
        course,
        asOf: _start.add(const Duration(days: 6)),
      );
      final estimate = estimates[rungOne.trainedSkillIds.single]!;
      expect(
        estimate.isUnknown,
        isTrue,
        reason:
            'six runs the app could not hear must leave the learner UNMEASURED, '
            'not measured as poor',
      );
      expect(estimate.level, isNull);
      expect(rungTwo.unlock.isSatisfiedBy(estimates), isFalse);
    });
  });

  group('MEASURE: how long an opened rung stays open', () {
    test('the fade is gradual, and the date it closes is measured rather than '
        'chosen', () {
      final subject = progress();
      playClean(subject, count: 2);
      int? closesAfterDays;
      for (final days in [0, 30, 60, 90, 120, 150, 180]) {
        final estimates = subject.estimatesFor(
          course,
          asOf: _start.add(Duration(days: days)),
        );
        final estimate = estimates[rungOne.trainedSkillIds.single]!;
        final open = rungTwo.unlock.isSatisfiedBy(estimates);
        // ignore: avoid_print
        print(
          '+$days days: state ${estimate.state.name}, '
          'level ${estimate.level?.toStringAsFixed(3)} '
          '-> rung two ${open ? "OPEN" : "not yet"}',
        );
        if (!open && closesAfterDays == null && days > 0) {
          closesAfterDays = days;
        }
      }
      // No hard expiry is written on the record, so nothing slams shut on a
      // date: the level decays continuously through the policy's measured
      // 30-day recency half-life. It does eventually fall back under the
      // course's 0.6 gate, which is the honest outcome — months of not playing
      // is months of no evidence — and the neutral "not yet reached" wording is
      // what stops that reading as a punishment.
      expect(
        closesAfterDays,
        isNotNull,
        reason:
            'evidence that never faded would let a single good week stand in '
            'for a skill indefinitely',
      );
      expect(
        closesAfterDays,
        greaterThanOrEqualTo(90),
        reason:
            'a rung closing again within a month of practice would punish a '
            'normal break',
      );
      expect(
        subject
            .estimatesFor(
              course,
              asOf: _start.add(const Duration(days: 180)),
            )[rungOne.trainedSkillIds.single]!
            .state,
        isNot(SkillEstimateState.stale),
        reason:
            'no record carries a validUntil, so evidence ages rather than '
            'expiring — stale would mean the data went invalid, which it did not',
      );
    });
  });

  group('writing the same attempt twice', () {
    test('counts once: the outcome id is derived from the attempt, not a '
        'counter', () {
      final subject = progress();
      final attempt = _attempt(rungOne);
      for (var i = 0; i < 3; i++) {
        subject.recordRhythmAttempt(
          mission: rungOne,
          attempt: attempt,
          at: _start,
        );
      }
      final estimate = subject.estimatesFor(
        course,
        asOf: _start,
      )[rungOne.trainedSkillIds.single]!;
      expect(
        estimate.evidenceIds,
        hasLength(1),
        reason:
            'a widget can rebuild for reasons that have nothing to do with the '
            'learner; a rebuild must not earn them a rung',
      );
      expect(estimate.state, SkillEstimateState.initial);
    });
  });

  group('the estimate map', () {
    test(
      'names every skill the course trains, including the unmeasured ones',
      () {
        final trained = <String>{
          for (final mission in course.missionsInOrder)
            ...mission.trainedSkillIds,
        };
        final estimates = progress().estimatesFor(course, asOf: _start);
        expect(estimates.keys.toSet(), trained);
        expect(
          estimates.values.every((estimate) => estimate.isUnknown),
          isTrue,
          reason: 'a learner who has played nothing is unmeasured, not poor',
        );
      },
    );

    test(
      'a skill measured on one rung does not leak into another rung gate',
      () {
        final estimates = playClean(progress(), count: 3);
        expect(estimates[rungOne.trainedSkillIds.single]!.isUnknown, isFalse);
        // Rung two trains its own skill, which nothing has measured yet.
        expect(estimates[rungTwo.trainedSkillIds.single]!.isUnknown, isTrue);
        // And the chord rungs are untouched by rhythm evidence entirely.
        expect(estimates['chord.eMinor']!.isUnknown, isTrue);
      },
    );
  });
}
