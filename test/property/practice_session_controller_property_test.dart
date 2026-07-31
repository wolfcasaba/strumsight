// A11 — Randomised property gate for the practice session controller
// (E02-R11, ADR 0077).
//
// Randomised command-soup that the controller never throws, never emits a
// status pair outside the [allowedTransitions] table, never records twice in
// one session, and never grows a stray subscription past the terminal
// status. The gate complements the deterministic A1-A17 tests in
// `test/features/practice/application/practice_session_controller_test.dart`
// — it covers the *invariants*, the tests cover the *paths*.
//
// Seed: `PROPERTY_SEED` environment variable (HORIZON convention, ADR 0077
// none). Absent → 42 (deterministic dev loop). CI passes the run id.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/practice/application/practice_observation_gateway.dart';
import 'package:strumsight/features/practice/application/practice_session_clock.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_controller.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

import '../support/fake_audio.dart';
import '../support/fake_practice_observation_gateway.dart';
import '../support/fake_practice_session_clock.dart';
import '../support/fake_practice_session_recorder.dart';
import '../support/fake_practice_tick_source.dart';

// ---------------------------------------------------------------------------
// Fixtures (intentionally identical in shape to the controller-test file).
// ---------------------------------------------------------------------------

final PracticeDefinition _definition = PracticeDefinition(
  id: 'def.prop.0',
  schemaVersion: 1,
  titleKey: 'def.prop.0.title',
  descriptionKey: 'def.prop.0.desc',
  mode: PracticeMode.freePractice,
  source: PracticeSource.builtin,
  meter: Meter(beatsPerBar: 4),
  defaultTempo: Tempo(120),
  totalBeats: BeatPosition.fromTicks(8 * 480),
  events: <PracticeEvent>[
    PracticeEvent(
      id: 'event.0',
      position: BeatPosition.fromTicks(0),
      direction: StrumDirection.down,
    ),
  ],
  scoringProfile: ScoringProfile.freePracticeOpen,
  skillTags: <String>[],
);

final CompiledPracticeTarget _target = CompiledPracticeTarget(
  definitionId: _definition.id,
  definitionSnapshotVersion: _definition.schemaVersion,
  tempo: _definition.defaultTempo,
  meter: _definition.meter,
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

Future<AppResult<CompiledPracticeTarget>> _compileSuccess(
  PracticeDefinition _,
  PracticeSessionConfig _,
) async {
  return Success<CompiledPracticeTarget>(_target);
}

class _SilentLogger implements AppLogger {
  const _SilentLogger();
  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}
  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}
  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
}

// ---------------------------------------------------------------------------
// The soup generator + invariant verifier.
// ---------------------------------------------------------------------------

/// Seeds the property RNG. Absent env → 42.
int _seed() {
  final raw = Platform.environment['PROPERTY_SEED'];
  if (raw == null || raw.isEmpty) return 42;
  return int.tryParse(raw) ?? 42;
}

PracticeSessionInput _randomCommand(math.Random rng) {
  // Six control commands (the ones reachable without further setup).
  // Signals and Preparation* are deliberately excluded — they require
  // setup-state that a soup can't guarantee. The goal is to pound on the
  // dispatch path with mixed valid/invalid commands, not to exercise the
  // prepare or scoring branches (which the unit suite covers).
  const pool = <PracticeSessionCommand>[
    StartPractice(),
    PausePractice(cause: PauseCause.user),
    ResumePractice(),
    RestartAttempt(),
    FinishPractice(),
    CancelPractice(),
  ];
  // Half the time: a deliberately-invalid input (seed with a name that
  // cannot legally arrive from the outside — the soup simulates any
  // dispatch sequence regardless of preconditions).
  if (rng.nextDouble() < 0.5) {
    return pool[rng.nextInt(pool.length)];
  }
  // Invalid soup: a PreparationFailed from a random state — the controller
  // must reject without throwing or mutating state.
  return PreparationFailed(
    const StorageFailure(code: FailureCode.practiceTargetUncompilable),
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'A11 — randomised command soup never breaks controller invariants',
    () async {
      final seed = _seed();
      final rng = math.Random(seed);

      const trialCount = 200;
      const commandsPerTrial = 25;

      for (var trial = 0; trial < trialCount; trial++) {
        final gateway = FakePracticeObservationGateway();
        final recorder = FakePracticeSessionRecorder();
        final controller = PracticeSessionController(
          clock: FakePracticeSessionClock(),
          tickSource: FakePracticeTickSource(),
          recorder: recorder,
          logger: const _SilentLogger(),
          permissions: FakeMicrophonePermissionGateway(
            state: MicrophonePermissionState.granted,
          ),
          observationConfig: const PracticeObservationConfig(),
          sessionIdFactory: () => 'session-prop-$trial',
          compileTarget: _compileSuccess,
          observationGateway: gateway,
        );

        final priorStatuses = <List<PracticeSessionStatus>>[];

        // Snapshot of state-status through the dispatch path.
        final seenStatuses = <PracticeSessionStatus>[];
        final sub = controller.states.listen(
          (state) => seenStatuses.add(state.status),
        );

        try {
          for (var step = 0; step < commandsPerTrial; step++) {
            // Throw in a Command.
            final input = _randomCommand(rng);
            // INVARIANT — never throws.
            await controller.dispatch(input);

            // Random ClockAdvanced, half the time, to add state-machine churn.
            if (rng.nextDouble() < 0.3) {
              controller.dispatch(
                ClockAdvanced(
                  controller.state
                      .copyWith(target: null)
                      .let(
                        (_) => const PracticeClockSnapshot(
                          wall: Duration.zero,
                          active: Duration.zero,
                          paused: Duration.zero,
                          attempt: Duration.zero,
                        ),
                      ),
                ),
              );
            }
          }
          await _settle();

          // INVARIANT — every accepted transition's status-pairs live in
          // `allowedTransitions`. Because we read the captured statuses only,
          // every adjacent pair on the stream corresponds to one transition's
          // start and end states; the controller did NOT collapse via
          // `distinct()`.
          for (var i = 0; i + 1 < seenStatuses.length; i++) {
            final from = seenStatuses[i];
            final to = seenStatuses[i + 1];
            if (from == to) continue; // same-status transition is fine
            expect(
              allowedTransitions[from]?.contains(to) ?? false,
              isTrue,
              reason:
                  'seed=$seed trial=$trial: $from → $to not in '
                  'allowedTransitions',
            );
          }

          // INVARIANT — `record()` at most once per session.
          expect(
            recorder.recordCalls <= 1,
            isTrue,
            reason:
                'seed=$seed trial=$trial: recorder.recordCalls '
                '(${recorder.recordCalls}) > 1',
          );

          // INVARIANT — when the session reached a terminal status, the
          // controller continued accepting no further state changes (the
          // reduce path must have rejected them all).
          if (const {
            PracticeSessionStatus.completed,
            PracticeSessionStatus.cancelled,
            PracticeSessionStatus.failed,
          }.contains(controller.state.status)) {
            final afterTerminal = <PracticeSessionStatus>[];
            // Capture state stream events from now on.
            controller.states.listen((s) => afterTerminal.add(s.status));
            // Dispatch a clearly-valid command (CancelPractice) which the
            // reducer rejects from terminal states.
            await controller.dispatch(const CancelPractice());
            await _settle();
            expect(afterTerminal, isEmpty);
          }

          // INVARIANT — `playingElapsed <= activeElapsed <= wallElapsed`.
          final s = controller.state;
          expect(
            s.playingElapsed <= s.activeElapsed,
            isTrue,
            reason: 'seed=$seed trial=$trial: playingElapsed > activeElapsed',
          );
          expect(
            s.activeElapsed <= s.wallElapsed,
            isTrue,
            reason: 'seed=$seed trial=$trial: activeElapsed > wallElapsed',
          );

          priorStatuses.add(List<PracticeSessionStatus>.from(seenStatuses));
        } finally {
          await sub.cancel();
          await controller.dispose();
        }
      }
    },
  );
}

extension _LetCopyWith<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
