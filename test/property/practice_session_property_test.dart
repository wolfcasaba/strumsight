// Randomized property gate (anti-reward-hacking — HORIZON pattern) for the
// E02-R07 practice-session state machine.
//
// The deterministic unit tests in `practice_session_reducer_test.dart` are
// the visible dev-loop harness; this suite re-checks the reducer's
// INVARIANTS on randomized input sequences so the logic cannot be (even
// accidentally) tuned to the fixed fixtures.
//
// Seed: PROPERTY_SEED env var — CI passes the run id (a fresh gate every
// run); locally absent → fixed 42, so the dev-loop suite stays
// deterministic.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/application/practice_session_clock.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_reducer.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

final CompiledPracticeTarget _target = CompiledPracticeTarget(
  definitionId: 'd',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(120),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 1,
  countInDuration: const Duration(seconds: 2),
  events: const <CompiledTargetEvent>[],
  musicalDuration: const Duration(seconds: 4),
  ringOutDuration: const Duration(seconds: 2),
  totalDuration: const Duration(seconds: 8),
  barBoundaries: const <Duration>[
    Duration.zero,
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 6),
    Duration(seconds: 8),
  ],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const <ExpectedChordSegment>[],
  scoringApplicable: false,
);

const PracticeDefinition _definition = PracticeDefinition(
  id: 'd',
  schemaVersion: 1,
  titleKey: 'd.title',
  descriptionKey: 'd.desc',
  mode: PracticeMode.freePractice,
  source: PracticeSource.builtin,
  meter: Meter(beatsPerBar: 4),
  defaultTempo: Tempo(120),
  totalBeats: BeatPosition(1920),
  events: <PracticeEvent>[],
  scoringProfile: ScoringProfile.freePracticeOpen,
  skillTags: <String>[],
);

PracticeSessionConfig _config() => PracticeSessionConfig(
  definitionId: 'd',
  definitionSnapshotVersion: 1,
  effectiveTempo: const Tempo(120),
  countInBars: 1,
  loopCount: 1,
  metronomeEnabled: true,
  accentEnabled: true,
  backingEnabled: false,
  scoringProfileId: 'free',
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: false,
  sessionTimeout: const Duration(minutes: 10),
  reducedMotion: false,
);

PracticeSessionState _initialState() => PracticeSessionState.initial;

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final rng = math.Random(seed);
  // Always visible in logs so any failure is reproducible.
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  // Compute the transitive closure of `allowedTransitions` from `start`.
  Set<PracticeSessionStatus> reachableStatuses(PracticeSessionStatus start) {
    final seen = <PracticeSessionStatus>{start};
    final stack = <PracticeSessionStatus>[start];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      for (final next in allowedTransitions[current] ?? const {}) {
        if (seen.add(next)) stack.add(next);
      }
    }
    return seen;
  }

  // Build a randomized sequence of inputs starting from `idle`. Mixes
  // commands and ClockAdvanced with random active-time advances. Always
  // starts with PreparePractice + PreparationSucceeded so a target is
  // available for the rest of the run.
  List<PracticeSessionInput> randomSequence(int length) {
    var state = _initialState();
    final inputs = <PracticeSessionInput>[];

    // Bring the session to ready with a target so commands have somewhere
    // to operate.
    final prepare = PreparePractice(definition: _definition, config: _config());
    state = reducePracticeSession(state, prepare).state;
    inputs.add(prepare);
    final succeeded = PreparationSucceeded(_target);
    state = reducePracticeSession(state, succeeded).state;
    inputs.add(succeeded);

    // Optional StartPractice to reach countIn.
    if (rng.nextBool()) {
      final start = const StartPractice();
      state = reducePracticeSession(state, start).state;
      inputs.add(start);
    }

    for (var i = 0; i < length; i++) {
      final r = rng.nextDouble();
      if (r < 0.55) {
        // Tick the clock — random active advance in [0, 5] seconds.
        final deltaMs = rng.nextInt(5000);
        final newSnapshot = PracticeClockSnapshot(
          wall: state.wallElapsed + Duration(milliseconds: deltaMs),
          active: state.activeElapsed + Duration(milliseconds: deltaMs),
          paused: state.pausedElapsed,
          attempt: state.attemptElapsed,
        );
        final input = ClockAdvanced(newSnapshot);
        state = reducePracticeSession(state, input).state;
        inputs.add(input);
      } else if (r < 0.65) {
        final input = const PausePractice(cause: PauseCause.user);
        state = reducePracticeSession(state, input).state;
        inputs.add(input);
      } else if (r < 0.75) {
        final input = const ResumePractice();
        state = reducePracticeSession(state, input).state;
        inputs.add(input);
      } else if (r < 0.82) {
        final input = const CancelPractice();
        state = reducePracticeSession(state, input).state;
        inputs.add(input);
      } else if (r < 0.90) {
        final input = const FinishPractice();
        state = reducePracticeSession(state, input).state;
        inputs.add(input);
      } else {
        final input = const StartPractice();
        state = reducePracticeSession(state, input).state;
        inputs.add(input);
      }
    }
    return inputs;
  }

  test('property: reducer invariants hold over 200 random sequences', () {
    for (var trial = 0; trial < 200; trial++) {
      final inputs = randomSequence(30);
      var state = _initialState();

      var prevStatus = state.status;
      var prevWall = state.wallElapsed;
      var prevActive = state.activeElapsed;
      var prevPaused = state.pausedElapsed;
      var prevCountIn = state.countInElapsed;
      var prevPlaying = state.playingElapsed;

      for (var step = 0; step < inputs.length; step++) {
        final input = inputs[step];
        final transition = reducePracticeSession(state, input);

        // Invariant: reducer never throws.
        // (The call already succeeded by reaching here.)

        // Snapshot the post-state invariants.
        final next = transition.state;

        // Invariant 1 — accepted steps move to a status that is reachable
        // from `prevStatus` via zero or more `allowedTransitions` edges.
        // The reducer may chain multiple transitions in one tick (e.g.
        // countIn → running → finishing when a single ClockAdvanced spans
        // both the count-in end and the timeline end), so we cannot
        // require a single edge — but the destination must still be a
        // member of the same closure.
        if (transition.isAccepted && next.status != prevStatus) {
          final reachable = reachableStatuses(prevStatus);
          expect(
            reachable.contains(next.status),
            isTrue,
            reason:
                'seed=$seed trial=$trial step=$step: '
                'transition $prevStatus → ${next.status} is not reachable '
                'through allowedTransitions',
          );
        }

        // Invariant 2 — rejected steps keep the input state by value and
        // emit no effects.
        if (transition.isRejected) {
          expect(
            next,
            equals(state),
            reason:
                'seed=$seed trial=$trial step=$step: rejected step '
                'mutated state',
          );
          expect(
            transition.effects,
            isEmpty,
            reason:
                'seed=$seed trial=$trial step=$step: rejected step '
                'emitted effects',
          );
        }

        // Invariant 3 — activeElapsed + pausedElapsed == wallElapsed.
        // (countIn and playing are subsets of activeElapsed, so the
        // identity is preserved when previousStatus is countIn or
        // running. While paused, pausedElapsed grows and activeElapsed
        // stays put — the identity still holds.)
        expect(
          next.activeElapsed + next.pausedElapsed,
          next.wallElapsed,
          reason:
              'seed=$seed trial=$trial step=$step: '
              'wall == active + paused broken '
              '(wall=${next.wallElapsed}, active=${next.activeElapsed}, '
              'paused=${next.pausedElapsed})',
        );

        // Invariant 4 — countInElapsed + playingElapsed <= activeElapsed.
        // (Some active time is spent in neither countIn nor running — e.g.
        // while paused or in preparing/ready.)
        expect(
          next.countInElapsed + next.playingElapsed <= next.activeElapsed,
          isTrue,
          reason:
              'seed=$seed trial=$trial step=$step: '
              'countIn + playing > active',
        );

        // Invariant 5 — wall/active/paused/countIn/playing are monotonically
        // nondecreasing (only RestartAttempt can zero countIn + playing;
        // we treat it as resetting both — see below).
        final isRestart = input is RestartAttempt;
        if (!isRestart) {
          expect(
            next.wallElapsed >= prevWall,
            isTrue,
            reason: 'seed=$seed trial=$trial step=$step: wall decreased',
          );
          expect(
            next.activeElapsed >= prevActive,
            isTrue,
            reason: 'seed=$seed trial=$trial step=$step: active decreased',
          );
          expect(
            next.pausedElapsed >= prevPaused,
            isTrue,
            reason: 'seed=$seed trial=$trial step=$step: paused decreased',
          );
          expect(
            next.countInElapsed >= prevCountIn,
            isTrue,
            reason: 'seed=$seed trial=$trial step=$step: countIn decreased',
          );
          expect(
            next.playingElapsed >= prevPlaying,
            isTrue,
            reason: 'seed=$seed trial=$trial step=$step: playing decreased',
          );
        }

        // Invariant 6 — timelinePosition never exceeds target.totalDuration
        // (§6.5: getter clamps at totalDuration).
        if (next.target != null) {
          expect(
            next.timelinePosition <= next.target!.totalDuration,
            isTrue,
            reason:
                'seed=$seed trial=$trial step=$step: timeline position '
                '${next.timelinePosition} > totalDuration '
                '${next.target!.totalDuration}',
          );
        }

        prevStatus = next.status;
        prevWall = next.wallElapsed;
        prevActive = next.activeElapsed;
        prevPaused = next.pausedElapsed;
        prevCountIn = next.countInElapsed;
        prevPlaying = next.playingElapsed;
        state = next;
      }
    }
  });

  // (reachable-status helper is at top of main())

  test('property: timelinePosition can only decrease after ResumePractice', () {
    // A more focused property: across many random sequences, count the
    // number of times timelinePosition decreased and assert each decrease
    // happens immediately after a ResumePractice call.
    for (var trial = 0; trial < 100; trial++) {
      final inputs = randomSequence(20);
      var state = _initialState();
      var previousPosition = state.timelinePosition;

      for (var step = 0; step < inputs.length; step++) {
        final input = inputs[step];
        final transition = reducePracticeSession(state, input);
        final next = transition.state;
        final newPosition = next.timelinePosition;

        if (newPosition < previousPosition) {
          // The only input that may legitimately decrease the playhead is
          // ResumePractice.
          expect(
            input,
            isA<ResumePractice>(),
            reason:
                'seed=$seed trial=$trial step=$step: '
                'timelinePosition decreased on $input',
          );
        }
        previousPosition = newPosition;
        state = next;
      }
    }
  });
}
