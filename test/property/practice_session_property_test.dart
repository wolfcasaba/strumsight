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
//
// R1 MAJOR-3: the transition check is now edge-by-edge. The reducer
// reports the full status chain in `transition.statusPath`; the gate walks
// every adjacent pair and asserts each pair is a member of the RAW
// `allowedTransitions` table (not its transitive closure — that was
// vacuous and hid R1 MAJOR-2).
//
// R1 MINOR-3: the timelinePosition no longer clamps to totalDuration, so
// the previous upper-bound check is gone. Instead, whenever
// `timelinePosition >= target.totalDuration`, the reducer MUST have moved
// the status out of `running` (into `finishing` or `completed`).
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

/// Asserts that every adjacent pair of [path] is a member of the raw
/// [allowedTransitions] table — not a transitive closure. R1 MAJOR-3.
void _assertStatusPathIsEdgeByEdge(
  List<PracticeSessionStatus> path,
  int trial,
  int step,
  int seed,
) {
  expect(path, isNotEmpty, reason: 'seed=$seed trial=$trial step=$step');
  for (var i = 0; i + 1 < path.length; i++) {
    final from = path[i];
    final to = path[i + 1];
    if (from == to) continue; // no-op edge (e.g. tempo change)
    expect(
      allowedTransitions[from]?.contains(to) ?? false,
      isTrue,
      reason:
          'seed=$seed trial=$trial step=$step: '
          'statusPath edge $from → $to is NOT in the raw '
          'allowedTransitions table',
    );
  }
}

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final rng = math.Random(seed);
  // Always visible in logs so any failure is reproducible.
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

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

  test('property: reducer invariants hold over 200 random sequences '
      '(edge-by-edge statusPath, R1 MAJOR-3)', () {
    for (var trial = 0; trial < 200; trial++) {
      final inputs = randomSequence(30);
      var state = _initialState();

      var prevWall = state.wallElapsed;
      var prevActive = state.activeElapsed;
      var prevPaused = state.pausedElapsed;
      var prevCountIn = state.countInElapsed;
      var prevPlaying = state.playingElapsed;

      for (var step = 0; step < inputs.length; step++) {
        final input = inputs[step];
        final transition = reducePracticeSession(state, input);

        // Invariant 0 — reducer never throws.
        // (The call already succeeded by reaching here.)

        // R1 MAJOR-3: every edge in the statusPath is in the RAW
        // allowedTransitions table — NOT the transitive closure.
        _assertStatusPathIsEdgeByEdge(transition.statusPath, trial, step, seed);

        final next = transition.state;

        // Invariant 1 — rejected steps keep the input state by value and
        // emit no effects; the statusPath is a single-element array of
        // the input status (no edge to assert).
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
          expect(
            transition.statusPath.length,
            1,
            reason:
                'seed=$seed trial=$trial step=$step: rejected step '
                'has multi-element statusPath',
          );
          expect(
            transition.statusPath.single,
            state.status,
            reason:
                'seed=$seed trial=$trial step=$step: rejected step '
                'statusPath is not the input status',
          );
        }

        // Invariant 2 — activeElapsed + pausedElapsed == wallElapsed.
        expect(
          next.activeElapsed + next.pausedElapsed,
          next.wallElapsed,
          reason:
              'seed=$seed trial=$trial step=$step: '
              'wall == active + paused broken '
              '(wall=${next.wallElapsed}, active=${next.activeElapsed}, '
              'paused=${next.pausedElapsed})',
        );

        // Invariant 3 — countInElapsed + playingElapsed <= activeElapsed.
        expect(
          next.countInElapsed + next.playingElapsed <= next.activeElapsed,
          isTrue,
          reason:
              'seed=$seed trial=$trial step=$step: '
              'countIn + playing > active',
        );

        // Invariant 4 — wall/active/paused/countIn/playing are
        // monotonically nondecreasing across non-restart steps.
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

        // R1 MINOR-3 — the getter no longer clamps. The new invariant
        // is: when `timelinePosition >= target.totalDuration`, the
        // status at the end of the tick is no longer `running` (the
        // session has moved to `finishing` or `completed`). Pre-attempt
        // statuses (`ready`, `cancelled`, `failed`, …) are excluded from
        // the check — they happen when the timeline has not yet been
        // consumed by an attempt.
        if (next.target != null &&
            next.timelinePosition >= next.target!.totalDuration) {
          expect(
            next.status != PracticeSessionStatus.running,
            isTrue,
            reason:
                'seed=$seed trial=$trial step=$step: timeline '
                '${next.timelinePosition} >= totalDuration '
                '${next.target!.totalDuration} but status is still '
                'running (must move to finishing / completed)',
          );
        }

        prevWall = next.wallElapsed;
        prevActive = next.activeElapsed;
        prevPaused = next.pausedElapsed;
        prevCountIn = next.countInElapsed;
        prevPlaying = next.playingElapsed;
        state = next;
      }
    }
  });

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
          // ResumePractice and RestartAttempt reset the playhead by
          // definition. After R1 MAJOR-1, `StartPractice` also resets
          // it to zero when called from `ready` (because `activeBase`
          // is set to `state.activeElapsed`, which may be non-zero on a
          // session that went through a CancelPractice → RestartAttempt
          // → StartPractice cycle). That reset is also legitimate.
          expect(
            input is ResumePractice ||
                input is RestartAttempt ||
                input is StartPractice,
            isTrue,
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
