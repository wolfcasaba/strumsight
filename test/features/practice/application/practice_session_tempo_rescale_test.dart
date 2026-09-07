// R13 (audit §5.2): the mid-session tempo change of a scored session, at the
// Practice-engine level.
//
// The Song Trainer speed slider was inert in a scored session because the
// compiled target is timed once, at the setup speed, and nothing could
// re-time it under a live session. `RescheduleTempo` is that operation, and
// these are its measured guarantees:
//
// T1 — from `paused` the remaining targets are rescheduled to the new tempo
//      and the session config follows; the playhead does not jump.
// T2 — a verdict already earned does NOT move with them.
// T3 — an in-flight attempt is refused (the caller pauses first); the state
//      is returned by value, untouched.
// T4 — from `ready` the whole timeline is re-timed, count-in included.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/application/practice_observation_gateway.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_controller.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_target_compiler.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_practice_observation_gateway.dart';
import '../../../support/fake_practice_session_clock.dart';
import '../../../support/fake_practice_session_recorder.dart';
import '../../../support/fake_practice_tick_source.dart';

void main() {
  test('T0 — the fixture the other cells are read against', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);

    await _driveToRunning(harness);

    final target = harness.controller.state.target!;
    expect(target.countInDuration, const Duration(seconds: 2));
    expect(_eventTimes(harness), const <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 4),
    ]);
    expect(target.totalDuration, const Duration(seconds: 8));
  });

  test('T1 — a paused session reschedules the remaining targets', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await _driveToRunning(harness);
    await _advanceTo(harness, const Duration(milliseconds: 3500));

    await harness.controller.dispatch(
      const PausePractice(cause: PauseCause.user),
    );
    expect(
      harness.controller.state.pausedAtTimeline,
      const Duration(milliseconds: 3500),
    );

    await harness.controller.dispatch(const RescheduleTempo(Tempo(60)));

    final state = harness.controller.state;
    expect(state.status, PracticeSessionStatus.paused);
    expect(state.config!.effectiveTempo, const Tempo(60));
    expect(state.target!.tempo, const Tempo(60));
    // The bar the session sits in is the pivot: everything up to 2 s keeps
    // its placement, everything after it doubles in length.
    expect(_eventTimes(harness), const <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 6),
    ]);
    expect(state.target!.countInDuration, const Duration(seconds: 2));
    expect(state.target!.totalDuration, const Duration(seconds: 14));
    // The playhead does not jump: the pause position and the derived
    // timeline position are the image of where the session actually stood.
    expect(state.pausedAtTimeline, const Duration(seconds: 5));
    expect(state.timelinePosition, const Duration(seconds: 5));
  });

  test('T2 — a verdict already earned does not move', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await _driveToRunning(harness);
    await _emitStrum(harness, at: const Duration(seconds: 2), sequence: 0);
    await _emitStrum(harness, at: const Duration(seconds: 3), sequence: 1);
    final before = harness.controller.liveScore!.verdicts;
    expect(before.length, 3);
    expect(before[0].targetAt, const Duration(seconds: 2));
    expect(before[1].targetAt, const Duration(seconds: 3));
    expect(before[1].matchedObservationSequence, 1);

    await _advanceTo(harness, const Duration(milliseconds: 3500));
    await harness.controller.dispatch(
      const PausePractice(cause: PauseCause.user),
    );
    await harness.controller.dispatch(const RescheduleTempo(Tempo(60)));
    await harness.controller.dispatch(const ResumePractice());
    // One resume bar at the new tempo (4/4 at 60 BPM == 4 s).
    await _advanceTo(harness, const Duration(milliseconds: 7500));
    expect(harness.controller.state.status, PracticeSessionStatus.running);

    // The third target now sits at 6 s; on the old timeline (4 s) this
    // strum would have been an extra.
    await _emitStrum(harness, at: const Duration(seconds: 6), sequence: 2);

    final after = harness.controller.liveScore!.verdicts;
    expect(after[0], before[0]);
    expect(after[1], before[1]);
    // The target moved, the verdict did not: the compiled event is at 4 s
    // now, while the verdict still reports the 3 s it was judged against.
    expect(_eventTimes(harness)[1], const Duration(seconds: 4));
    expect(after[1].targetAt, const Duration(seconds: 3));
    expect(after[2].targetAt, const Duration(seconds: 6));
    expect(after[2].matchedObservationSequence, 2);
  });

  test('T3 — an in-flight attempt is refused, state untouched', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await _driveToRunning(harness);
    final before = harness.controller.state;

    await harness.controller.dispatch(const RescheduleTempo(Tempo(60)));

    expect(harness.controller.state, before);
    expect(harness.controller.state.status, PracticeSessionStatus.running);
    expect(harness.controller.state.config!.effectiveTempo, const Tempo(120));
    expect(_eventTimes(harness)[1], const Duration(seconds: 3));
  });

  test('T4 — from ready the whole timeline is re-timed', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.controller.dispatch(
      PreparePractice(definition: _definition, config: _config),
    );
    expect(harness.controller.state.status, PracticeSessionStatus.ready);

    await harness.controller.dispatch(const RescheduleTempo(Tempo(60)));

    final state = harness.controller.state;
    expect(state.status, PracticeSessionStatus.ready);
    expect(state.target!.countInDuration, const Duration(seconds: 4));
    expect(_eventTimes(harness), const <Duration>[
      Duration(seconds: 4),
      Duration(seconds: 6),
      Duration(seconds: 8),
    ]);
    expect(state.target!.totalDuration, const Duration(seconds: 16));
    expect(state.pausedAtTimeline, isNull);
  });

  test('T5 — an out-of-range tempo is refused', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.controller.dispatch(
      PreparePractice(definition: _definition, config: _config),
    );
    final before = harness.controller.state;

    await harness.controller.dispatch(const RescheduleTempo(Tempo(400)));

    expect(harness.controller.state, before);
    expect(harness.controller.state.config!.effectiveTempo, const Tempo(120));
  });
}

List<Duration> _eventTimes(_Harness harness) {
  final events = harness.controller.state.target!.events;
  return <Duration>[for (final event in events) event.time];
}

Future<void> _driveToRunning(_Harness harness) async {
  await harness.controller.dispatch(
    PreparePractice(definition: _definition, config: _config),
  );
  await harness.controller.dispatch(const StartPractice());
  await _advanceTo(harness, const Duration(milliseconds: 2100));
  expect(harness.controller.state.status, PracticeSessionStatus.running);
}

/// Advances the fake clock so the session's ACTIVE time reaches [active],
/// then delivers one tick.
Future<void> _advanceTo(_Harness harness, Duration active) async {
  final elapsed = harness.controller.state.activeElapsed;
  harness.clock.advance(active - elapsed);
  harness.tick.emitTick();
  await _settle();
}

Future<void> _emitStrum(
  _Harness harness, {
  required Duration at,
  required int sequence,
}) async {
  harness.gateway.emit(
    StrumObservation(
      at: at,
      sequence: sequence,
      direction: StrumDirection.down,
      confidence: 1,
    ),
  );
  await _settle();
}

Future<void> _settle() async {
  for (var index = 0; index < 3; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Harness {
  _Harness() {
    gateway = FakePracticeObservationGateway();
    clock = FakePracticeSessionClock();
    tick = FakePracticeTickSource();
    controller = PracticeSessionController(
      clock: clock,
      tickSource: tick,
      recorder: FakePracticeSessionRecorder(),
      logger: const NoopAppLogger(),
      permissions: FakeMicrophonePermissionGateway(),
      observationConfig: const PracticeObservationConfig(),
      sessionIdFactory: () => 'practice-result',
      compileTarget: (definition, config) => Future.value(
        compilePracticeTarget(definition: definition, config: config),
      ),
      observationGateway: gateway,
    );
  }

  late final FakePracticeObservationGateway gateway;
  late final FakePracticeSessionClock clock;
  late final FakePracticeTickSource tick;
  late final PracticeSessionController controller;

  Future<void> dispose() => controller.dispose();
}

final PracticeDefinition _definition = PracticeDefinition(
  id: 'def.rescale',
  schemaVersion: 1,
  titleKey: 'def.rescale.title',
  descriptionKey: 'def.rescale.desc',
  mode: PracticeMode.chordProgression,
  source: PracticeSource.builtin,
  meter: Meter(beatsPerBar: 4),
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
      position: BeatPosition.fromTicks(2 * 480),
      chord: 'G',
      direction: StrumDirection.down,
    ),
    PracticeEvent(
      id: 'event.2',
      position: BeatPosition.fromTicks(4 * 480),
      chord: 'D',
      direction: StrumDirection.down,
    ),
  ],
  scoringProfile: ScoringProfile.chordProgressionDefault,
  skillTags: <String>[],
);

final PracticeSessionConfig _config = PracticeSessionConfig(
  definitionId: _definition.id,
  definitionSnapshotVersion: _definition.schemaVersion,
  effectiveTempo: _definition.defaultTempo,
  countInBars: 1,
  loopCount: 1,
  metronomeEnabled: true,
  accentEnabled: true,
  backingEnabled: false,
  scoringProfileId: 'chordProgressionDefault',
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: false,
  sessionTimeout: const Duration(minutes: 10),
  reducedMotion: false,
);
