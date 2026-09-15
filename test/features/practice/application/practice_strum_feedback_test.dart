// Per-strum feedback stream (chunk 016b P0 juice on the Practice engine):
// the controller emits one PracticeStrumFeedback per StrumObservation it
// scores — the observed stroke plus the live verdict of the target it
// matched — and nothing while capture is inactive. Same harness shape as
// practice_session_integration_test.dart, trimmed to what this cell needs.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_controller.dart';
import 'package:strumsight/features/practice/application/practice_strum_feedback.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_target_compiler.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_practice_observation_gateway.dart';
import '../../../support/fake_practice_session_clock.dart';
import '../../../support/fake_practice_session_recorder.dart';
import '../../../support/fake_practice_tick_source.dart';

final PracticeDefinition _definition = PracticeDefinition(
  id: 'def.strum-feedback',
  schemaVersion: 1,
  titleKey: 'def.strum-feedback.title',
  descriptionKey: 'def.strum-feedback.desc',
  mode: PracticeMode.strumPattern,
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
    PracticeEvent(
      id: 'event.1',
      position: BeatPosition.fromTicks(4 * 480),
      direction: StrumDirection.up,
    ),
  ],
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: <String>[],
);

PracticeSessionConfig _config() => PracticeSessionConfig(
  definitionId: _definition.id,
  definitionSnapshotVersion: _definition.schemaVersion,
  effectiveTempo: _definition.defaultTempo,
  countInBars: 1,
  loopCount: 1,
  metronomeEnabled: false,
  accentEnabled: false,
  backingEnabled: false,
  scoringProfileId: 'legacyLearnParity',
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: false,
  sessionTimeout: const Duration(minutes: 10),
  reducedMotion: false,
);

Future<AppResult<CompiledPracticeTarget>> _compile(
  PracticeDefinition definition,
  PracticeSessionConfig config,
) async => compilePracticeTarget(definition: definition, config: config);

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

Future<void> _settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePracticeObservationGateway gateway;
  late FakePracticeSessionClock clock;
  late FakePracticeTickSource tick;
  late PracticeSessionController controller;
  late List<PracticeStrumFeedback> heard;

  setUp(() {
    gateway = FakePracticeObservationGateway();
    clock = FakePracticeSessionClock();
    tick = FakePracticeTickSource();
    var n = 0;
    controller = PracticeSessionController(
      clock: clock,
      tickSource: tick,
      recorder: FakePracticeSessionRecorder(),
      logger: const _SilentLogger(),
      permissions: FakeMicrophonePermissionGateway(
        state: MicrophonePermissionState.granted,
      ),
      sessionIdFactory: () => 'session-strum-${++n}',
      compileTarget: _compile,
      observationGateway: gateway,
    );
    heard = <PracticeStrumFeedback>[];
    controller.strumFeedback.listen(heard.add);
  });

  tearDown(() => controller.dispose());

  Future<void> driveToRunning() async {
    await controller.dispatch(
      PreparePractice(definition: _definition, config: _config()),
    );
    await controller.dispatch(const GrantPermission());
    await controller.dispatch(const StartPractice());
    clock.start();
    clock.advance(const Duration(milliseconds: 2100));
    tick.emitTick();
    await _settle();
  }

  test(
    'a scored strum emits its observed stroke with the live verdict',
    () async {
      await driveToRunning();
      final target = controller.state.target!;
      gateway.emit(
        StrumObservation(
          at: target.events[0].time,
          sequence: 7,
          direction: StrumDirection.down,
          confidence: 0.91,
        ),
      );
      await _settle();

      expect(heard, hasLength(1));
      final f = heard.single;
      expect(f.sequence, 7);
      expect(f.direction, StrumDirection.down);
      expect(f.isDown, isTrue);
      expect(f.confidence, 0.91);
      // On the target's exact time → matched, PERFECT, full-strength burst.
      expect(f.verdict, isNotNull);
      expect(f.verdict!.matchedObservationSequence, 7);
      expect(f.verdict!.timingGrade, TimingGrade.perfect);
      expect(f.strength, 1.0);
    },
  );

  test('every strum is reported once, in order', () async {
    await driveToRunning();
    final target = controller.state.target!;
    gateway.emit(
      StrumObservation(
        at: target.events[0].time,
        sequence: 0,
        direction: StrumDirection.down,
        confidence: 0.9,
      ),
    );
    gateway.emit(
      StrumObservation(
        at: target.events[1].time,
        sequence: 1,
        direction: StrumDirection.up,
        confidence: 0.8,
      ),
    );
    await _settle();
    expect(heard.map((f) => f.sequence), [0, 1]);
    expect(heard.map((f) => f.direction), [
      StrumDirection.down,
      StrumDirection.up,
    ]);
  });

  test('nothing is emitted while capture is inactive (before Start)', () async {
    await controller.dispatch(
      PreparePractice(definition: _definition, config: _config()),
    );
    await controller.dispatch(const GrantPermission());
    gateway.emit(
      const StrumObservation(
        at: Duration.zero,
        sequence: 0,
        direction: StrumDirection.down,
        confidence: 0.9,
      ),
    );
    await _settle();
    expect(heard, isEmpty);
  });

  test('strength follows the Learn timing ladder', () {
    PracticeStrumFeedback withGrade(TimingGrade? grade) =>
        PracticeStrumFeedback(
          sequence: 0,
          direction: StrumDirection.up,
          confidence: 0.9,
          verdict: grade == null
              ? null
              : PracticeVerdict(
                  targetEventId: 'e',
                  matchedObservationSequence: 0,
                  targetAt: Duration.zero,
                  observedAt: Duration.zero,
                  timingOffset: Duration.zero,
                  timingGrade: grade,
                  expectedDirection: StrumDirection.up,
                  observedDirection: StrumDirection.up,
                  directionOutcome: DirectionOutcome.correct,
                  expectedChord: null,
                  observedChord: null,
                  chordOutcome: ChordOutcome.notApplicable,
                  eventScore: 1,
                  missReasonCode: null,
                  coachingCode: null,
                ),
        );
    expect(withGrade(TimingGrade.perfect).strength, 1.0);
    expect(withGrade(TimingGrade.good).strength, 0.72);
    expect(withGrade(TimingGrade.early).strength, 0.45);
    expect(withGrade(TimingGrade.late).strength, 0.45);
    expect(withGrade(TimingGrade.missed).strength, 0.35);
    expect(withGrade(null).strength, 0.35); // a stray strum still shows
  });
}
