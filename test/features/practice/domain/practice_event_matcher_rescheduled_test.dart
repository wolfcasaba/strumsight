// R13 (audit §5.2): the matcher half of a mid-session tempo change.
//
// When the judged timeline is re-timed under a live session the matcher has
// to follow it — but only for what is still open. These are the measured
// guarantees:
//
// M1 — an already resolved target keeps its record verbatim (the compiled
//      event it was judged against, its sequence, its timing offset), so no
//      verdict earned before the change can move.
// M2 — an open target is matched against the RE-TIMED placement; the same
//      strum is an extra on the old timeline.
// M3 — the matcher's counters continue rather than restart, and a resolved
//      target is not re-opened by the change.
// M4 — a target that does not carry the same compiled events is refused.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';

const List<Duration> _oldTimes = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 3),
];

const List<Duration> _newTimes = <Duration>[
  Duration(milliseconds: 500),
  Duration(milliseconds: 2500),
  Duration(seconds: 4),
];

void main() {
  group('PracticeEventMatcher.rescheduled', () {
    test('M1 — a resolved target keeps its record verbatim', () {
      final previous = _matcher(_oldTimes);
      final matched = previous.registerStrum(
        _observation(at: const Duration(milliseconds: 1050)),
      );
      expect(matched?.targetIndex, 0);

      final next = PracticeEventMatcher.rescheduled(
        previous: previous,
        target: _target(_newTimes),
      );

      expect(next.results[0], previous.results[0]);
      expect(next.results[0].target.time, const Duration(seconds: 1));
      expect(next.results[0].timingOffset, const Duration(milliseconds: 50));
      expect(next.results[0].resolution, PracticeTargetResolution.matched);
      expect(next.results[1].target.time, const Duration(milliseconds: 2500));
      expect(next.results[2].target.time, const Duration(seconds: 4));
      expect(next.results[1].resolution, PracticeTargetResolution.open);
      expect(next.results[2].resolution, PracticeTargetResolution.open);
    });

    test('M2 — an open target follows the re-timed placement', () {
      final control = _matcher(_oldTimes);
      expect(control.registerStrum(_observation(at: _at4s)), isNull);
      expect(control.extraStrumCount, 1);

      final previous = _matcher(_oldTimes);
      final next = PracticeEventMatcher.rescheduled(
        previous: previous,
        target: _target(_newTimes),
      );

      final matched = next.registerStrum(_observation(at: _at4s));
      expect(matched?.targetIndex, 2);
      expect(matched?.timingOffset, Duration.zero);
      expect(next.extraStrumCount, 0);
    });

    test('M3 — counters continue and a resolved target stays resolved', () {
      final previous = _matcher(_oldTimes);
      previous.registerStrum(_observation(at: const Duration(seconds: 1)));
      previous.registerStrum(
        _observation(at: const Duration(seconds: 30), sequence: 1),
      );
      expect(previous.resolvedTargetCount, 1);
      expect(previous.extraStrumCount, 1);

      final next = PracticeEventMatcher.rescheduled(
        previous: previous,
        target: _target(_newTimes),
      );

      expect(next.resolvedTargetCount, 1);
      expect(next.extraStrumCount, 1);
      // The re-timed placement of target 0 (0.5 s) is NOT a second chance:
      // the target is resolved, so the strum lands as an extra.
      final again = next.registerStrum(
        _observation(at: const Duration(milliseconds: 500), sequence: 2),
      );
      expect(again, isNull);
      expect(next.results[0].matchedObservationSequence, 0);
      expect(next.resolvedTargetCount, 1);
      expect(next.extraStrumCount, 2);
    });

    test('M4 — a target with a different event count is refused', () {
      final previous = _matcher(_oldTimes);

      expect(
        () => PracticeEventMatcher.rescheduled(
          previous: previous,
          target: _target(const <Duration>[Duration(seconds: 1)]),
        ),
        throwsArgumentError,
      );
    });
  });
}

const Duration _at4s = Duration(seconds: 4);

PracticeEventMatcher _matcher(List<Duration> times) => PracticeEventMatcher(
  target: _target(times),
  scoringProfile: ScoringProfile.legacyLearnParity,
  inputLatency: Duration.zero,
);

CompiledPracticeTarget _target(List<Duration> times) => CompiledPracticeTarget(
  definitionId: 'rescheduled-test',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(120),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 0,
  countInDuration: Duration.zero,
  events: <CompiledTargetEvent>[
    for (var index = 0; index < times.length; index++)
      CompiledTargetEvent(
        sourceEventId: 'event-$index',
        loopIndex: 0,
        position: BeatPosition.fromTicks(index * 480),
        time: times[index],
        barIndex: 0,
        chord: null,
        direction: StrumDirection.down,
        accent: false,
        optional: false,
      ),
  ],
  musicalDuration: const Duration(seconds: 10),
  ringOutDuration: Duration.zero,
  totalDuration: const Duration(seconds: 10),
  barBoundaries: const <Duration>[],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const <ExpectedChordSegment>[],
  scoringApplicable: true,
);

StrumObservation _observation({required Duration at, int sequence = 0}) =>
    StrumObservation(
      at: at,
      sequence: sequence,
      direction: StrumDirection.down,
      confidence: 1,
    );
