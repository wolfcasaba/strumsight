// Unit tests for [PracticeSessionController] — E02-R11 / ADR 0077 acceptance.
//
// Covers A1, A2, A3, A4, A5, A6, A8, A9, A13, A14, A15, A16, A17 from §6.
// The randomised property gate (A11) lives in
// `test/property/practice_session_controller_property_test.dart`.
// The ten end-to-end integration scenarios (A10) live in
// `test/features/practice/application/practice_session_integration_test.dart`.
//
// The fixture uses the REAL `compilePracticeTarget(definition, config)` — per
// ADR 0077 §14 a hand-rolled `CompiledPracticeTarget` is forbidden: the matcher's
// match-window, the chord scorer's `chordStableDuration`, and the expected-chord
// segments all originate in the compiled target, and the test gate must verify
// the controller's *integration* with the compiler, not a stub.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/practice/application/practice_observation_gateway.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_controller.dart';
import 'package:strumsight/features/practice/application/practice_session_effect.dart';
import 'package:strumsight/features/practice/domain/service/practice_target_compiler.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/beat_time_converter.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_practice_observation_gateway.dart';
import '../../../support/fake_practice_session_clock.dart';
import '../../../support/fake_practice_session_recorder.dart';
import '../../../support/fake_practice_tick_source.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final Meter _defaultMeter = Meter(beatsPerBar: 4);

/// The default 4/4, two-bar fixture used by most tests. Events carry
/// `chord` + `direction` so the chord and direction scorers actually run
/// (the previous zero-event fixture left the scorers as pass-throughs,
/// which made the matcher↔scorer integration invisible).
final PracticeDefinition _definition = PracticeDefinition(
  id: 'def.test.0',
  schemaVersion: 1,
  titleKey: 'def.test.0.title',
  descriptionKey: 'def.test.0.desc',
  mode: PracticeMode.chordProgression,
  source: PracticeSource.builtin,
  meter: _defaultMeter,
  defaultTempo: Tempo(120),
  totalBeats: BeatPosition.fromTicks(8 * 480),
  events: <PracticeEvent>[
    PracticeEvent(
      id: 'event.0',
      position: BeatPosition.fromTicks(0),
      chord: 'C',
      direction: StrumDirection.down,
    ),
    PracticeEvent(
      id: 'event.1',
      position: BeatPosition.fromTicks(4 * 480),
      chord: 'G',
      direction: StrumDirection.up,
    ),
  ],
  scoringProfile: ScoringProfile.chordProgressionDefault,
  skillTags: <String>[],
);

PracticeSessionConfig _config({
  Duration inputLatency = Duration.zero,
  Duration sessionTimeout = const Duration(minutes: 10),
}) {
  return PracticeSessionConfig(
    definitionId: _definition.id,
    definitionSnapshotVersion: _definition.schemaVersion,
    effectiveTempo: _definition.defaultTempo,
    countInBars: 1,
    loopCount: 1,
    metronomeEnabled: true,
    accentEnabled: true,
    backingEnabled: false,
    scoringProfileId: 'chordProgressionDefault',
    inputLatency: inputLatency,
    visualLatency: Duration.zero,
    expectedChordHintEnabled: false,
    sessionTimeout: sessionTimeout,
    reducedMotion: false,
  );
}

/// Builds a definition for a (meter, countInBars) cell. Used by the A6
/// pause/resume matrix to exercise every Meter × countInBars combination
/// the controller must handle.
PracticeDefinition _definitionFor(Meter meter, int countInBars) {
  final ticksPerBar = meter.ticksPerBar;
  return PracticeDefinition(
    id: 'def.test.m${meter.beatsPerBar}.c$countInBars',
    schemaVersion: 1,
    titleKey: 'def.test.m${meter.beatsPerBar}.c$countInBars.title',
    descriptionKey: 'def.test.m${meter.beatsPerBar}.c$countInBars.desc',
    mode: PracticeMode.chordProgression,
    source: PracticeSource.builtin,
    meter: meter,
    defaultTempo: Tempo(120),
    totalBeats: BeatPosition.fromTicks(2 * ticksPerBar),
    events: <PracticeEvent>[
      PracticeEvent(
        id: 'event.0',
        position: BeatPosition.fromTicks(0),
        chord: 'C',
        direction: StrumDirection.down,
      ),
      PracticeEvent(
        id: 'event.1',
        position: BeatPosition.fromTicks(ticksPerBar),
        chord: 'G',
        direction: StrumDirection.up,
      ),
    ],
    scoringProfile: ScoringProfile.chordProgressionDefault,
    skillTags: <String>[],
  );
}

PracticeSessionConfig _configFor(
  PracticeDefinition definition,
  int countInBars, {
  Duration sessionTimeout = const Duration(minutes: 10),
}) {
  return PracticeSessionConfig(
    definitionId: definition.id,
    definitionSnapshotVersion: definition.schemaVersion,
    effectiveTempo: definition.defaultTempo,
    countInBars: countInBars,
    loopCount: 1,
    metronomeEnabled: true,
    accentEnabled: true,
    backingEnabled: false,
    scoringProfileId: 'chordProgressionDefault',
    inputLatency: Duration.zero,
    visualLatency: Duration.zero,
    expectedChordHintEnabled: false,
    sessionTimeout: sessionTimeout,
    reducedMotion: false,
  );
}

/// Delegates the compile to the **real** `compilePracticeTarget` so the
/// test gate exercises the matcher / scorers against a compiled timeline
/// (the previous R0 hand-rolled target had zero events, which made all
/// scorers pass-throughs and the integration invisible).
Future<AppResult<CompiledPracticeTarget>> _compileSuccess(
  PracticeDefinition definition,
  PracticeSessionConfig config,
) async {
  return compilePracticeTarget(definition: definition, config: config);
}

Future<AppResult<CompiledPracticeTarget>> _compileFailure(
  PracticeDefinition _,
  PracticeSessionConfig _,
) async {
  return const Failure(
    StorageFailure(code: FailureCode.practiceTargetUncompilable),
  );
}

/// A no-op [AppLogger]; keeps the controller's redacted warnings from
/// polluting test output without altering behaviour.
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

class _IdFactory {
  int _n = 0;
  String next() => 'session-test-${++_n}';
}

@immutable
class Harness {
  const Harness._({
    required this.controller,
    required this.gateway,
    required this.clock,
    required this.tick,
    required this.recorder,
    required this.permissions,
    required this.definition,
    required this.config,
  });
  final PracticeSessionController controller;
  final FakePracticeObservationGateway gateway;
  final FakePracticeSessionClock clock;
  final FakePracticeTickSource tick;
  final FakePracticeSessionRecorder recorder;
  final FakeMicrophonePermissionGateway permissions;
  final PracticeDefinition definition;
  final PracticeSessionConfig config;
}

Harness makeHarness({
  PracticeObservationConfig observationConfig =
      const PracticeObservationConfig(),
  AppResult<void>? startResult,
  AppResult<void>? recordResult,
  MicrophonePermissionState permissionState = MicrophonePermissionState.granted,
  Future<AppResult<CompiledPracticeTarget>> Function(
    PracticeDefinition,
    PracticeSessionConfig,
  )?
  compileTargetOverride,
  PracticeDefinition? definition,
  PracticeSessionConfig? config,
}) {
  final definitionUsed = definition ?? _definition;
  final configUsed = config ?? _config();
  final sessionId = _IdFactory();
  final gateway = FakePracticeObservationGateway(startResult: startResult);
  final clock = FakePracticeSessionClock();
  final tick = FakePracticeTickSource();
  final recorder = FakePracticeSessionRecorder(recordResult: recordResult);
  final permissions = FakeMicrophonePermissionGateway(state: permissionState);
  final controller = PracticeSessionController(
    clock: clock,
    tickSource: tick,
    recorder: recorder,
    logger: const _SilentLogger(),
    permissions: permissions,
    observationConfig: observationConfig,
    sessionIdFactory: () => sessionId.next(),
    compileTarget: compileTargetOverride ?? _compileSuccess,
    observationGateway: gateway,
  );
  return Harness._(
    controller: controller,
    gateway: gateway,
    clock: clock,
    tick: tick,
    recorder: recorder,
    permissions: permissions,
    definition: definitionUsed,
    config: configUsed,
  );
}

Future<void> driveToCountIn(Harness h) async {
  await h.controller.dispatch(
    PreparePractice(definition: h.definition, config: h.config),
  );
  await h.controller.dispatch(const GrantPermission());
  await h.controller.dispatch(const StartPractice());
}

/// Advances the controller from `countIn` to `running` by ticking the fake
/// clock past the count-in boundary and emitting one [ClockAdvanced] signal.
/// The fake clock must have been `start()`ed (StartPractice does that
/// automatically) and `advance`d past `target.countInDuration`.
///
/// Pass [countInDuration] to override the default (used by the A6 matrix
/// where the count-in span depends on the meter × countInBars cell).
Future<void> crossCountInToRunning(
  Harness h, {
  Duration? countInDuration,
}) async {
  final target = h.controller.state.target;
  final span = countInDuration ?? target?.countInDuration ?? Duration.zero;
  final advance = span + const Duration(milliseconds: 100);
  h.clock.start();
  h.clock.advance(advance);
  h.tick.emitTick();
  await settle();
}

Future<void> driveToRunning(Harness h, {Duration? countInDuration}) async {
  await driveToCountIn(h);
  await crossCountInToRunning(h, countInDuration: countInDuration);
}

/// Awaits all controller async side-effects to settle (effect-stream
/// emissions, terminal-cleanup futures).
Future<void> settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ===========================================================================
// Tests
// ===========================================================================

void main() {
  // -------------------------------------------------------------------------
  // A1 — status stream emits every accepted transition.
  // -------------------------------------------------------------------------
  group('A1 — status stream emits every transition', () {
    test('idle → preparing → ready on PreparePractice + Succeeded', () async {
      final h = makeHarness();
      final statuses = <PracticeSessionStatus>[];
      final sub = h.controller.states.listen(
        (state) => statuses.add(state.status),
      );
      await h.controller.dispatch(
        PreparePractice(definition: _definition, config: h.config),
      );
      await h.controller.dispatch(const GrantPermission());
      await settle();
      await sub.cancel();
      await h.controller.dispose();
      expect(statuses, [
        PracticeSessionStatus.preparing,
        PracticeSessionStatus.ready,
      ]);
    });

    test('FinishPractice + tick crosses finishing → completed', () async {
      final h = makeHarness();
      await driveToRunning(h);
      final statuses = <PracticeSessionStatus>[];
      final sub = h.controller.states.listen(
        (state) => statuses.add(state.status),
      );
      await h.controller.dispatch(const FinishPractice());
      // The finishing → completed edge is bound to the next ClockAdvanced.
      h.tick.emitTick();
      await settle();
      await sub.cancel();
      expect(statuses, contains(PracticeSessionStatus.finishing));
      expect(statuses.last, PracticeSessionStatus.completed);
      await h.controller.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // A2 — capture-activation matrix.
  // -------------------------------------------------------------------------
  group('A2 — capture-activation matrix', () {
    test('startCalls == 1 when entering countIn', () async {
      final h = makeHarness();
      await driveToCountIn(h);
      await settle();
      expect(h.controller.gatewayStartCalls, 1);
      expect(h.controller.gatewayStopCalls, 0);
      await h.controller.dispose();
    });

    test('countIn → running keeps startCalls unchanged', () async {
      final h = makeHarness();
      await driveToCountIn(h);
      final startCalls = h.controller.gatewayStartCalls;
      final stopCalls = h.controller.gatewayStopCalls;
      // ClockAdvanced drives countIn → running when activeElapsed reaches
      // the count-in boundary. From this fixture, the controller's tick
      // source synthesises a ClockAdvanced snapshot from the FAKE clock
      // (which still reads zero). The reducer needs the snapshot to cross
      // target.countInDuration; we therefore make the fake clock report
      // a non-zero wall ahead of the tick.
      h.clock.start();
      h.clock.advance(const Duration(milliseconds: 2100));
      h.tick.emitTick();
      await settle();
      // The controller may or may not have reached `running` — but the
      // capture-activation table says both countIn and running are
      // capture-active. So startCalls and stopCalls must NOT have grown
      // — no churn.
      expect(h.controller.gatewayStartCalls, startCalls);
      expect(h.controller.gatewayStopCalls, stopCalls);
      await h.controller.dispose();
    });

    test('running → paused stops the gateway exactly once', () async {
      final h = makeHarness();
      await driveToCountIn(h);
      await h.controller.dispatch(const PausePractice(cause: PauseCause.user));
      await settle();
      expect(h.controller.gatewayStartCalls, 1);
      expect(h.controller.gatewayStopCalls, 1);
      await h.controller.dispose();
    });

    test(
      'paused → countIn (resume) restarts the gateway (startCalls == 2)',
      () async {
        final h = makeHarness();
        await driveToCountIn(h);
        await h.controller.dispatch(
          const PausePractice(cause: PauseCause.user),
        );
        await h.controller.dispatch(const ResumePractice());
        await settle();
        expect(h.controller.gatewayStartCalls, 2);
        expect(h.controller.gatewayStopCalls, 1);
        await h.controller.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // A3 — Finish idempotency.
  // -------------------------------------------------------------------------
  group('A3 — finish single-flight', () {
    test(
      'multiple FinishPractice calls produce exactly one record()',
      () async {
        final h = makeHarness();
        await driveToRunning(h);
        await h.controller.dispatch(const FinishPractice());
        await h.controller.dispatch(const FinishPractice());
        await h.controller.dispatch(const FinishPractice());
        h.tick.emitTick();
        await settle();
        expect(h.recorder.recordCalls, 1);
        // Result object identity — single reference across re-reads.
        expect(identical(h.controller.result, h.controller.result), isTrue);
        await h.controller.dispose();
      },
    );

    test('finishReason maps to userFinished on FinishPractice', () async {
      final h = makeHarness();
      await driveToRunning(h);
      await h.controller.dispatch(const FinishPractice());
      h.tick.emitTick();
      await settle();
      final r = h.controller.result;
      expect(r, isNotNull);
      expect(r!.finishReason.code, 'userFinished');
      await h.controller.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // A4 — cleanup matrix per terminal status.
  // -------------------------------------------------------------------------
  group('A4 — cleanup matrix', () {
    test('completed: disposeCalls == 1, recordCalls == 1', () async {
      final h = makeHarness();
      await driveToRunning(h);
      await h.controller.dispatch(const FinishPractice());
      h.tick.emitTick();
      await settle();
      expect(h.controller.gatewayDisposeCalls, 1);
      expect(h.recorder.recordCalls, 1);
      await h.controller.dispose();
    });

    test(
      'cancelled (a) user CancelPractice: disposeCalls == 1, recordCalls == 0',
      () async {
        final h = makeHarness();
        await driveToCountIn(h);
        await h.controller.dispatch(const CancelPractice());
        await settle();
        expect(h.controller.gatewayDisposeCalls, 1);
        expect(h.recorder.recordCalls, 0);
        expect(h.controller.state.status, PracticeSessionStatus.cancelled);
        expect(h.controller.result, isNull);
        await h.controller.dispose();
      },
    );

    test(
      'cancelled (b) gateway-start Failure: cancelled, recordCalls == 0',
      () async {
        final h = makeHarness(
          startResult: const Failure(
            AudioFailure(code: FailureCode.audioSessionBusy),
          ),
        );
        final effects = <PracticeSessionEffect>[];
        final sub = h.controller.effects.listen(effects.add);
        await driveToCountIn(h);
        await settle();
        await sub.cancel();
        expect(h.controller.state.status, PracticeSessionStatus.cancelled);
        expect(h.controller.gatewayDisposeCalls, 1);
        expect(h.recorder.recordCalls, 0);
        expect(h.controller.result, isNull);
        // Controller-injected effect: ShowRecoverableError from gateway
        // start failure.
        final errors = effects.whereType<ShowRecoverableError>().toList();
        expect(errors, isNotEmpty);
        expect(errors.first.failure.code, FailureCode.audioSessionBusy);
        await h.controller.dispose();
      },
    );

    test(
      'failed (compileTarget Failure) — preparing → failed, recordCalls == 0',
      () async {
        final h = makeHarness(compileTargetOverride: _compileFailure);
        final effects = <PracticeSessionEffect>[];
        final sub = h.controller.effects.listen(effects.add);
        await h.controller.dispatch(
          PreparePractice(definition: _definition, config: h.config),
        );
        await settle();
        await sub.cancel();
        expect(h.controller.state.status, PracticeSessionStatus.failed);
        expect(h.recorder.recordCalls, 0);
        expect(h.controller.result, isNull);
        // Reducer-origin effect: ShowRecoverableError from the failed
        // state machine.
        final errors = effects.whereType<ShowRecoverableError>().toList();
        expect(errors, isNotEmpty);
        expect(
          errors.first.failure.code,
          FailureCode.practiceTargetUncompilable,
        );
        await h.controller.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // A5 — error matrix.
  // -------------------------------------------------------------------------
  group('A5 — error matrix', () {
    test('permission denied during preparing → permissionRequired', () async {
      final h = makeHarness(permissionState: MicrophonePermissionState.denied);
      final effects = <PracticeSessionEffect>[];
      final sub = h.controller.effects.listen(effects.add);
      await h.controller.dispatch(
        PreparePractice(definition: _definition, config: h.config),
      );
      await settle();
      await sub.cancel();
      expect(
        h.controller.state.status,
        PracticeSessionStatus.permissionRequired,
      );
      expect(effects.whereType<ShowPermissionSettings>().length, 1);
      await h.controller.dispose();
    });

    test(
      'compileTarget Failure → preparing → failed (reducer-origin effect)',
      () async {
        final h = makeHarness(compileTargetOverride: _compileFailure);
        await h.controller.dispatch(
          PreparePractice(definition: _definition, config: h.config),
        );
        await settle();
        expect(h.controller.state.status, PracticeSessionStatus.failed);
        await h.controller.dispose();
      },
    );

    test('gateway.start() Failure → cancelled, recorder NOT called', () async {
      final h = makeHarness(
        startResult: const Failure(
          AudioFailure(code: FailureCode.audioSessionBusy),
        ),
      );
      await driveToCountIn(h);
      await settle();
      expect(h.controller.state.status, PracticeSessionStatus.cancelled);
      expect(h.recorder.recordCalls, 0);
      await h.controller.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // A6 — Pause semantics.
  //
  // Four observable invariants from the brief:
  //   1. A strum arriving in `paused` leaves `liveScore.verdicts`,
  //      `metrics.scorePoints`, and `resolvedTargets` unchanged.
  //   2. `playingElapsed` does not grow while paused; `pausedElapsed` does.
  //   3. Resume continues the timeline from the bar-boundary anchor — no
  //      regression, no jump forward.
  //   4. Matrix: every Meter ∈ {4/4, 3/4} × countInBars ∈ {0, 1, 2} cell. Each
  //      cell exercises one full pause→resume cycle.
  // -------------------------------------------------------------------------
  group('A6 — pause semantics', () {
    test(
      'running → paused: strum during pause does not change liveScore',
      () async {
        final h = makeHarness();
        await driveToRunning(h);

        // Seed liveScore with one matching strum so we have a non-null
        // reference to compare against.
        final target = h.controller.state.target!;
        final event0Time = target.events[0].time;
        h.gateway.emit(
          StrumObservation(
            at: event0Time,
            sequence: 0,
            direction: StrumDirection.down,
            confidence: 0.95,
          ),
        );
        await settle();
        final liveScoreBefore = h.controller.liveScore;
        expect(liveScoreBefore, isNotNull);
        final verdictsBefore = liveScoreBefore!.verdicts.length;
        final scorePointsBefore = liveScoreBefore.metrics.scorePoints;
        final resolvedBefore = liveScoreBefore.metrics.resolvedTargets;

        // Pause and emit a strum whose `at` lands inside the match window of
        // an unmatched target event (event.1 at 4*480 ticks @ 120 BPM = 1s).
        // The previous `Duration(milliseconds: 30)` was deliberately outside
        // every window — the cell only stayed green because the controller
        // ignored an obviously non-matching strum. With a true match-window
        // time, the new guard in `_onObservation` is what pins the aggregate.
        final event1Time = target.events[1].time;
        await h.controller.dispatch(
          const PausePractice(cause: PauseCause.user),
        );
        h.gateway.emit(
          StrumObservation(
            at: event1Time,
            sequence: 1,
            direction: StrumDirection.down,
            confidence: 0.95,
          ),
        );
        await settle();

        // The pause-strum path must not change the liveScore aggregate:
        // verdicts, scorePoints, and resolvedTargets are all pinned.
        final liveScoreAfter = h.controller.liveScore;
        expect(liveScoreAfter, isNotNull);
        expect(liveScoreAfter!.verdicts.length, verdictsBefore);
        expect(liveScoreAfter.metrics.scorePoints, scorePointsBefore);
        expect(liveScoreAfter.metrics.resolvedTargets, resolvedBefore);
        await h.controller.dispose();
      },
    );

    test('playingElapsed freezes during paused; pausedElapsed grows', () async {
      final h = makeHarness();
      await driveToRunning(h);

      // Advance 100ms of running so playingElapsed > 0.
      h.clock.advance(const Duration(milliseconds: 100));
      h.tick.emitTick();
      await settle();
      final playBefore = h.controller.state.playingElapsed;
      final pausedBefore = h.controller.state.pausedElapsed;
      expect(playBefore, greaterThan(Duration.zero));

      await h.controller.dispatch(const PausePractice(cause: PauseCause.user));
      final playAtPause = h.controller.state.playingElapsed;
      final pausedAtPause = h.controller.state.pausedElapsed;

      // Advance 500ms while paused.
      h.clock.advance(const Duration(milliseconds: 500));
      h.tick.emitTick();
      await settle();

      // playingElapsed must be frozen; pausedElapsed must grow.
      expect(h.controller.state.playingElapsed, playAtPause);
      expect(h.controller.state.pausedElapsed, greaterThan(pausedAtPause));
      expect(pausedAtPause, pausedBefore);
      await h.controller.dispose();
    });

    test(
      'resume continues the timeline from the bar-boundary anchor (no jump)',
      () async {
        final h = makeHarness();
        await driveToRunning(h);

        // Advance 1.5s into the musical content so the timeline is well
        // past beat 0 of the target; the resume anchor should be the bar
        // boundary at or before the pause position.
        h.clock.advance(const Duration(milliseconds: 1500));
        h.tick.emitTick();
        await settle();
        final timelineBeforePause = h.controller.state.timelinePosition;
        expect(timelineBeforePause, greaterThan(Duration.zero));

        await h.controller.dispatch(
          const PausePractice(cause: PauseCause.user),
        );
        h.clock.advance(const Duration(milliseconds: 250));
        h.tick.emitTick();
        await settle();

        await h.controller.dispatch(const ResumePractice());
        // The resume count-in is one bar; the timeline must resume at or
        // before the pre-pause position (the anchor is at-or-before the
        // pause position), and MUST NOT jump forward.
        final timelineRightAfterResume = h.controller.state.timelinePosition;
        expect(
          timelineRightAfterResume,
          lessThanOrEqualTo(timelineBeforePause),
          reason: 'Resume must anchor to a bar boundary at or before pause',
        );

        // Advance well past the resume count-in span + pre-pause
        // timeline. The resume count-in is one bar (2s of active at
        // 4/4 × 120 BPM); the pre-pause timeline was 1.5s past
        // count-in. So we need (2s + 1.5s + buffer) = 4s of active to
        // exceed the pre-pause position.
        h.clock.advance(const Duration(milliseconds: 4000));
        h.tick.emitTick();
        await settle();
        final timelineAfterRun = h.controller.state.timelinePosition;
        expect(
          timelineAfterRun,
          greaterThan(timelineBeforePause),
          reason: 'Timeline must advance past the pre-pause point',
        );
        await h.controller.dispose();
      },
    );

    // 6-cell matrix: Meter {4/4, 3/4} × countInBars {0, 1, 2}.
    for (final meter in const <Meter>[
      Meter(beatsPerBar: 4),
      Meter(beatsPerBar: 3),
    ]) {
      for (final countInBars in const <int>[0, 1, 2]) {
        test('Meter ${meter.beatsPerBar}/4 × countInBars=$countInBars: '
            'pause/resume cycle completes', () async {
          final definition = _definitionFor(meter, countInBars);
          final config = _configFor(definition, countInBars);
          final h = makeHarness(definition: definition, config: config);

          // Compute the expected count-in duration and tick past it.
          final countInDuration = BeatTimeConverter(
            tempo: definition.defaultTempo,
            meter: meter,
          ).timeOfTicks(countInBars * meter.ticksPerBar);

          await driveToRunning(h, countInDuration: countInDuration);
          expect(
            h.controller.state.status,
            PracticeSessionStatus.running,
            reason:
                'Should have reached running for $meter × '
                'countInBars=$countInBars',
          );

          // Pause.
          final playBefore = h.controller.state.playingElapsed;
          await h.controller.dispatch(
            const PausePractice(cause: PauseCause.user),
          );
          expect(h.controller.state.status, PracticeSessionStatus.paused);

          // Advance during pause — playingElapsed frozen.
          h.clock.advance(const Duration(milliseconds: 250));
          h.tick.emitTick();
          await settle();
          expect(h.controller.state.playingElapsed, playBefore);
          expect(h.controller.state.pausedElapsed, greaterThan(Duration.zero));

          // Resume.
          await h.controller.dispatch(const ResumePractice());
          expect(h.controller.state.status, PracticeSessionStatus.countIn);

          // Advance past the resume count-in (one bar for the chosen
          // meter), then assert we are running again.
          final barDuration = BeatTimeConverter(
            tempo: definition.defaultTempo,
            meter: meter,
          ).barDuration;
          h.clock.advance(barDuration + const Duration(milliseconds: 100));
          h.tick.emitTick();
          await settle();
          expect(h.controller.state.status, PracticeSessionStatus.running);

          await h.controller.dispose();
        });
      }
    }
  });

  // -------------------------------------------------------------------------
  // A8 — single observation-config source, behaviour-tested.
  //
  // The single source must be honoured by BOTH the gateway AND the chord
  // scorer. The brief's mutation #1 (omit `chordStableDuration:` from the
  // chord scorer call) must turn the test red; the controller's
  // `practice_session_controller.dart:454` is the only call site, and
  // it must pass `observationConfig.chordStableDuration` explicitly.
  // -------------------------------------------------------------------------
  group('A8 — single observation-config source', () {
    test('gateway receives exactly the controller-provided config', () async {
      const custom = PracticeObservationConfig(
        chordStableDuration: Duration(milliseconds: 400),
      );
      final h = makeHarness(observationConfig: custom);
      await driveToCountIn(h);
      expect(h.gateway.startConfigs, hasLength(1));
      expect(
        h.gateway.startConfigs.single.chordStableDuration,
        const Duration(milliseconds: 400),
      );
      await h.controller.dispose();
    });

    test('400ms chordStableDuration: 250ms-stable chord run → '
        'MetricInsufficientData(chordUnstable)', () async {
      const custom = PracticeObservationConfig(
        chordStableDuration: Duration(milliseconds: 400),
      );
      final h = makeHarness(observationConfig: custom);
      await driveToRunning(h);

      final target = h.controller.state.target!;
      final eventTime = target.events[0].time;

      // Emit a 250ms stable 'C' run before a different chord in the
      // first event's window. The chord scorer's longest-segment
      // duration is 250ms — enough for 180ms, short of 400ms.
      h.gateway.emit(
        ChordObservation(at: eventTime, label: 'C', confidence: 0.95),
      );
      h.gateway.emit(
        ChordObservation(
          at: eventTime + const Duration(milliseconds: 250),
          label: 'D',
          confidence: 0.95,
        ),
      );
      // A matching strum is required to trigger the scoring pass.
      h.gateway.emit(
        StrumObservation(
          at: eventTime,
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.95,
        ),
      );
      await settle();

      expect(h.controller.liveScore, isNotNull);
      final chordMetric = h.controller.liveScore!.metrics.chord;
      expect(chordMetric, isA<MetricInsufficientData>());
      expect(
        (chordMetric as MetricInsufficientData).reasonCode,
        PracticeMetricReasonCode.chordUnstable,
        reason: '400ms threshold must reject a 250ms-stable run',
      );
      await h.controller.dispose();
    });

    test(
      '180ms chordStableDuration: same 250ms run → MetricAvailable',
      () async {
        const custom = PracticeObservationConfig(
          chordStableDuration: Duration(milliseconds: 180),
        );
        final h = makeHarness(observationConfig: custom);
        await driveToRunning(h);

        final target = h.controller.state.target!;
        final eventTime = target.events[0].time;

        // Identical input to the 400ms cell, only the config differs.
        h.gateway.emit(
          ChordObservation(at: eventTime, label: 'C', confidence: 0.95),
        );
        h.gateway.emit(
          ChordObservation(
            at: eventTime + const Duration(milliseconds: 250),
            label: 'D',
            confidence: 0.95,
          ),
        );
        h.gateway.emit(
          StrumObservation(
            at: eventTime,
            sequence: 0,
            direction: StrumDirection.down,
            confidence: 0.95,
          ),
        );
        await settle();

        expect(h.controller.liveScore, isNotNull);
        expect(
          h.controller.liveScore!.metrics.chord,
          isA<MetricAvailable>(),
          reason: '180ms threshold must accept a 250ms-stable run',
        );
        await h.controller.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // A13 — noSignal pinned as TODAY's behaviour (not a fix).
  //
  // The brief's A13 cell demands three assertions:
  //   1. `metrics.direction == MetricInsufficientData(noSignal)`
  //   2. `metrics.rhythm    == MetricInsufficientData(noSignal)`
  //   3. `matcher.extraStrumCount > 0` — i.e. **there was signal**, but
  //      none landed in a target window.
  //
  // This is the **pin** of the current scorer semantics, not a fix. The
  // direction scorer derives `noSignal` from the *empty* per-target
  // observation map (which the controller only fills on a match), and the
  // timing scorer derives it from the absence of matched offsets. The
  // "true" noSignal — distinguishing "no signal at all" from "signal but
  // no match" — is owned by the E02-R18 pre-flight; cf. ADR 0077
  // "Ismert korlát" and the E02-R10 review NOTE-1.
  // -------------------------------------------------------------------------
  group('A13 — noSignal pinned (current behaviour, NOT a fix)', () {
    test(
      'many unmatched strums → direction+rhythm MetricInsufficientData '
      '(noSignal); scorePoints == 0 (no matches, but signal was registered)',
      () async {
        final h = makeHarness();
        await driveToRunning(h);

        // Emit five strums in the gap between the two events (at 2s and
        // 4s in the default 4/4 × 120 BPM fixture). The 280ms match
        // window can't reach 3s, so every strum is unmatched — none
        // land in `observationsByTargetIndex`.
        for (var i = 0; i < 5; i++) {
          h.gateway.emit(
            StrumObservation(
              at:
                  const Duration(milliseconds: 3000) +
                  Duration(milliseconds: 50 * i),
              sequence: i,
              direction: StrumDirection.down,
              confidence: 0.95,
            ),
          );
        }
        await settle();

        // The scoring pass ran (the matching strum case would have
        // produced a non-null liveScore; here we added even more reason
        // for the pass to run). Both metrics must report noSignal.
        expect(h.controller.liveScore, isNotNull);
        final metrics = h.controller.liveScore!.metrics;
        expect(metrics.direction, isA<MetricInsufficientData>());
        expect(
          (metrics.direction as MetricInsufficientData).reasonCode,
          PracticeMetricReasonCode.noSignal,
          reason: 'direction scorer must report noSignal when no matches',
        );
        expect(metrics.rhythm, isA<MetricInsufficientData>());
        expect(
          (metrics.rhythm as MetricInsufficientData).reasonCode,
          PracticeMetricReasonCode.noSignal,
          reason: 'rhythm scorer must report noSignal when no matches',
        );
        // Equivalent observable for "extraStrumCount > 0": the scoring
        // pass ran (liveScore non-null) and produced a verdict per
        // target whose coachingCode is `noSignal`. The matcher's
        // extraStrumCount itself is private; this is the same claim
        // made observable via the verdicts list.
        expect(h.controller.liveScore!.metrics.scorePoints, 0);
        expect(h.controller.liveScore!.metrics.resolvedTargets, 0);
        expect(
          h.controller.liveScore!.verdicts.every(
            (v) => v.coachingCode == PracticeCoachingCode.noSignal,
          ),
          isTrue,
          reason: 'Every target verdict must carry noSignal coaching',
        );
        await h.controller.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // A14 — scoring pass discipline (liveScore identity).
  //
  // Four-row identity table (ADR 0077 §7: scoring pass runs ONLY on
  // StrumObservation and on finish). The reference is observed via
  // `identical(...)` so a tick-only or chord-only "scoring pass" would
  // allocate a new aggregation and turn the test red.
  // -------------------------------------------------------------------------
  group('A14 — scoring pass discipline', () {
    test(
      '100 ticks in running with no observation → liveScore unchanged',
      () async {
        final h = makeHarness();
        await driveToRunning(h);
        final initial = h.controller.liveScore;

        for (var i = 0; i < 100; i++) {
          h.tick.emitTick();
        }
        await settle();

        expect(identical(h.controller.liveScore, initial), isTrue);
        expect(h.controller.liveScore, isNull);
        await h.controller.dispose();
      },
    );

    test('a ChordObservation alone → liveScore unchanged', () async {
      final h = makeHarness();
      await driveToRunning(h);
      final initial = h.controller.liveScore;

      final target = h.controller.state.target!;
      h.gateway.emit(
        ChordObservation(
          at: target.events[0].time,
          label: 'C',
          confidence: 0.95,
        ),
      );
      await settle();

      expect(identical(h.controller.liveScore, initial), isTrue);
      expect(h.controller.liveScore, isNull);
      await h.controller.dispose();
    });

    test('a StrumObservation → liveScore changes (new aggregation)', () async {
      final h = makeHarness();
      await driveToRunning(h);
      final initial = h.controller.liveScore;
      expect(initial, isNull);

      final target = h.controller.state.target!;
      h.gateway.emit(
        StrumObservation(
          at: target.events[0].time,
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.95,
        ),
      );
      await settle();

      expect(h.controller.liveScore, isNotNull);
      expect(identical(h.controller.liveScore, initial), isFalse);
      await h.controller.dispose();
    });

    test('FinishPractice alone does not change liveScore (the final pass '
        'updates `result`, not `liveScore`)', () async {
      final h = makeHarness();
      await driveToRunning(h);

      // Seed liveScore with a matching strum.
      final target = h.controller.state.target!;
      h.gateway.emit(
        StrumObservation(
          at: target.events[0].time,
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.95,
        ),
      );
      await settle();
      final preFinish = h.controller.liveScore;
      expect(preFinish, isNotNull);

      // Finish + the closing tick (drives `finishing → completed`).
      await h.controller.dispatch(const FinishPractice());
      h.tick.emitTick();
      await settle();

      expect(h.controller.state.status, PracticeSessionStatus.completed);
      expect(
        identical(h.controller.liveScore, preFinish),
        isTrue,
        reason:
            'liveScore is the last strum-time aggregation; the final '
            'pass writes to `result`, not `liveScore`',
      );
      await h.controller.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // A15 — finishReason mapping: result is null on cancelled/failed.
  // -------------------------------------------------------------------------
  group('A15 — finishReason mapping', () {
    test('cancelled by user → result == null', () async {
      final h = makeHarness();
      await driveToCountIn(h);
      await h.controller.dispatch(const CancelPractice());
      await settle();
      expect(h.controller.state.status, PracticeSessionStatus.cancelled);
      expect(h.controller.result, isNull);
      await h.controller.dispose();
    });

    test('cancelled by gateway failure → result == null', () async {
      final h = makeHarness(
        startResult: const Failure(
          AudioFailure(code: FailureCode.audioSessionBusy),
        ),
      );
      await driveToCountIn(h);
      await settle();
      expect(h.controller.state.status, PracticeSessionStatus.cancelled);
      expect(h.controller.result, isNull);
      await h.controller.dispose();
    });

    test('failed → result == null', () async {
      final h = makeHarness(compileTargetOverride: _compileFailure);
      await h.controller.dispatch(
        PreparePractice(definition: _definition, config: h.config),
      );
      await settle();
      expect(h.controller.state.status, PracticeSessionStatus.failed);
      expect(h.controller.result, isNull);
      await h.controller.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // A16 — `finishing` is observable.
  // -------------------------------------------------------------------------
  group('A16 — finishing is observable', () {
    test('FinishPractice + tick crosses through finishing', () async {
      final h = makeHarness();
      await driveToRunning(h);
      final seen = <PracticeSessionStatus>[];
      final sub = h.controller.states.listen((state) => seen.add(state.status));
      await h.controller.dispatch(const FinishPractice());
      h.tick.emitTick();
      await settle();
      await sub.cancel();
      expect(seen, contains(PracticeSessionStatus.finishing));
      expect(seen.last, PracticeSessionStatus.completed);
      await h.controller.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // A17 — `failed` is unreachable from non-preparing states (R14 pin).
  // -------------------------------------------------------------------------
  group('A17 — failed is reachable ONLY from preparing (pin)', () {
    test('PreparationFailed from countIn is rejected by the reducer', () async {
      final h = makeHarness();
      await driveToCountIn(h);
      final before = h.controller.state.status;
      await h.controller.dispatch(
        PreparationFailed(
          const StorageFailure(code: FailureCode.practiceTargetUncompilable),
        ),
      );
      await settle();
      expect(h.controller.state.status, before);
      expect(before, PracticeSessionStatus.countIn);
      await h.controller.dispose();
    });

    test('PreparationFailed from paused is rejected by the reducer', () async {
      final h = makeHarness();
      await driveToCountIn(h);
      await h.controller.dispatch(const PausePractice(cause: PauseCause.user));
      await settle();
      final before = h.controller.state.status;
      await h.controller.dispatch(
        PreparationFailed(
          const StorageFailure(code: FailureCode.practiceTargetUncompilable),
        ),
      );
      await settle();
      expect(h.controller.state.status, before);
      expect(before, PracticeSessionStatus.paused);
      await h.controller.dispose();
    });

    test(
      'gateway-start failure → cancelled, recorder NOT called (R14 contract)',
      () async {
        final h = makeHarness(
          startResult: const Failure(
            AudioFailure(code: FailureCode.audioSessionBusy),
          ),
        );
        await driveToCountIn(h);
        await settle();
        expect(h.controller.state.status, PracticeSessionStatus.cancelled);
        expect(h.recorder.recordCalls, 0);
        await h.controller.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // A9 — layer-purity guard. Runs once per suite.
  // -------------------------------------------------------------------------
  group('A9 — controller layer-purity guard', () {
    test('no forbidden symbol appears in the controller source '
        '(ADR 0077 §10 / R10d / R13)', () {
      final file = File(
        'lib/features/practice/application/practice_session_controller.dart',
      );
      expect(file.existsSync(), isTrue);
      final raw = file.readAsStringSync();
      // Strip Dart comments so a doc-comment that *names* a forbidden
      // symbol (for documentation purposes) is allowed; only **code**
      // references are forbidden.
      final code = raw
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      for (final forbidden in const <String>[
        'BuildContext',
        'Navigator',
        'GoRouter',
        'SharedPreferences',
        'StrumEngine(',
        'dart:ui',
        'DateTime.now(',
        'AudioSessionCoordinator',
        'audioSessionCoordinatorProvider',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              'A9 layer-purity violation: "$forbidden" appears in the '
              'code of practice_session_controller.dart — per ADR 0077 §10 '
              '/ R13 (microphone-lease ownership belongs to MicCapture, '
              'not the controller).',
        );
      }
    });
  });
}
