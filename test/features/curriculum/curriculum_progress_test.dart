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
      subject.recordAttempt(
        mission: rungOne,
        rhythm: _attempt(rungOne, heard: heard, flipDirection: flipDirection),
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
        final written = subject.recordAttempt(
          mission: rungOne,
          rhythm: _attempt(rungOne, heard: 1),
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
        subject.recordAttempt(mission: rungOne, rhythm: attempt, at: _start);
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

  group('MEASURE: can the whole ladder actually be climbed?', () {
    /// One clean run of [mission]: every notated stroke the right way, and the
    /// asked chord confirmed in every bar.
    ({RhythmAttempt rhythm, ChordAttempt? chord}) cleanRun(
      CurriculumMission mission,
    ) {
      final assignment = mission.rhythm!;
      final cycle = missionChordCycle(mission);
      final barUs = (60000000 / assignment.bpm * assignment.grid.beatsPerBar)
          .round();
      return (
        rhythm: gradeRhythm(
          assignment.grid,
          bpm: assignment.bpm,
          bars: assignment.bars,
          strokes: [
            for (var bar = 0; bar < assignment.bars; bar++)
              for (final slot in assignment.grid.slots)
                if (slot.isStruck)
                  DetectedStroke(
                    atUs: assignment.grid.onsetUs(
                      bar: bar,
                      slotIndex: slot.index,
                      bpm: assignment.bpm,
                    ),
                    direction: slot.direction,
                    isConfirmed: true,
                  ),
          ],
        ),
        chord: cycle.isEmpty
            ? null
            : gradeChords(
                cycle: cycle,
                bars: assignment.bars,
                bpm: assignment.bpm,
                beatsPerBar: assignment.grid.beatsPerBar,
                detections: [
                  for (var bar = 0; bar < assignment.bars; bar++)
                    DetectedChord(
                      atUs: bar * barUs + 1000,
                      label: cycle[bar % cycle.length],
                      isConfirmed: true,
                    ),
                ],
              ),
      );
    }

    test('a learner who plays every rung cleanly reaches the top', () {
      // THE measurement this pillar exists for. Until the chord rungs had an
      // exercise, `mission.dDuUdU` and everything above it could not be earned at
      // all, however well anyone played — the ladder was a map of a path that
      // stopped after two steps. This walks it.
      final subject = progress();
      final capabilities = curriculumDeviceCapabilities(
        microphoneListening: true,
      );
      var day = 0;
      var attempts = 0;
      final opened = <String>[];
      final stuck = <String>[];

      for (final mission in course.missionsInOrder) {
        final estimates = subject.estimatesFor(
          course,
          asOf: _start.add(Duration(days: day)),
        );
        final availability = missionAvailability(
          mission,
          estimates: estimates,
          deviceCapabilities: capabilities,
        );
        if (availability != MissionAvailability.available) {
          stuck.add('${mission.missionId} ($availability)');
          continue;
        }
        opened.add(mission.missionId);
        if (mission.rhythm == null) continue;
        // Two clean attempts is what the measured gate needs.
        for (var i = 0; i < 2; i++) {
          day++;
          attempts++;
          final run = cleanRun(mission);
          subject.recordAttempt(
            mission: mission,
            rhythm: run.rhythm,
            chord: run.chord,
            at: _start.add(Duration(days: day)),
          );
        }
      }

      // ignore: avoid_print
      print(
        'LADDER WALK: ${opened.length}/${course.missionsInOrder.length} rungs '
        'opened in $attempts attempts over $day days',
      );
      for (final rung in stuck) {
        // ignore: avoid_print
        print('  STUCK: $rung');
      }

      expect(
        stuck,
        isEmpty,
        reason:
            'a rung nobody can reach however well they play is a promise the '
            'course cannot keep',
      );
      expect(opened, hasLength(course.missionsInOrder.length));
    });

    test('a chord rung opens the next one, on the CHORD measurement', () {
      final subject = progress();
      final eMinor = _mission(course, 'mission.eMinor');
      final aMinor = _mission(course, 'mission.aMinor');

      // The prerequisite first: eMinor is gated on the right-hand rung.
      for (var i = 0; i < 2; i++) {
        final run = cleanRun(rungOne);
        subject.recordAttempt(
          mission: rungOne,
          rhythm: run.rhythm,
          chord: run.chord,
          at: _start.add(Duration(days: i)),
        );
      }
      for (var i = 0; i < 2; i++) {
        final run = cleanRun(eMinor);
        subject.recordAttempt(
          mission: eMinor,
          rhythm: run.rhythm,
          chord: run.chord,
          at: _start.add(Duration(days: 2 + i)),
        );
      }
      final estimates = subject.estimatesFor(
        course,
        asOf: _start.add(const Duration(days: 4)),
      );
      final chordEstimate = estimates['chord.eMinor']!;
      // ignore: avoid_print
      print(
        'chord.eMinor after 2 clean attempts: ${chordEstimate.state.name}, '
        'level ${chordEstimate.level?.toStringAsFixed(3)}',
      );
      expect(aMinor.unlock.isSatisfiedBy(estimates), isTrue);

      // And the direction measurement of the SAME runs did not leak into it: the
      // chord skill's evidence must carry the chord metric, not the rhythm one.
      final records = subject.evidenceRepository.allForSkill('chord.eMinor');
      expect(records, isNotEmpty);
      for (final record in records) {
        expect(record.performance!.metricCode, chordShapeAccuracyMetric);
      }
    });

    test('holding ONE chord through a change rung does not pass it', () {
      // The change rung's whole point. A learner who finds Em and never moves has
      // half the bars right, which is 0.5 — under the course's 0.6 gate.
      final subject = progress();
      final emToAm = _mission(course, 'mission.emToAm');
      final assignment = emToAm.rhythm!;
      final barUs = (60000000 / assignment.bpm * assignment.grid.beatsPerBar)
          .round();
      for (var i = 0; i < 6; i++) {
        subject.recordAttempt(
          mission: emToAm,
          rhythm: cleanRun(emToAm).rhythm,
          chord: gradeChords(
            cycle: missionChordCycle(emToAm),
            bars: assignment.bars,
            bpm: assignment.bpm,
            beatsPerBar: assignment.grid.beatsPerBar,
            detections: [
              for (var bar = 0; bar < assignment.bars; bar++)
                DetectedChord(
                  atUs: bar * barUs + 1000,
                  label: 'Em',
                  isConfirmed: true,
                ),
            ],
          ),
          at: _start.add(Duration(days: i)),
        );
      }
      final estimates = subject.estimatesFor(
        course,
        asOf: _start.add(const Duration(days: 6)),
      );
      final estimate = estimates['chord.emToAm']!;
      // ignore: avoid_print
      print(
        'Em held through an Em/Am change rung, 6 attempts: '
        '${estimate.state.name}, level ${estimate.level?.toStringAsFixed(3)}',
      );
      expect(
        _mission(course, 'mission.dDuUdU').unlock.isSatisfiedBy(estimates),
        isFalse,
        reason:
            'crediting a change nobody made would teach the learner that not '
            'changing is changing',
      );
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
