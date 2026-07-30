// Regression probes for the seven findings of the E02-R07 review.
//
// Each probe reproduces a measured defect from `docs/reviews/e02-r07-review.md` §3
// and is kept as a permanent test so future changes cannot regress it.
// These are NOT throw-away probes — every finding is wired to a stable
// acceptance criterion from the revised brief §6.4 / §6.5.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/practice/application/practice_session_clock.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_effect.dart';
import 'package:strumsight/features/practice/application/practice_session_reducer.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/beat_time_converter.dart';
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

CompiledPracticeTarget _targetFor({
  Tempo tempo = const Tempo(120),
  Meter meter = const Meter(beatsPerBar: 4),
  int countInBars = 1,
  int definitionBars = 4,
}) {
  final converter = BeatTimeConverter(tempo: tempo, meter: meter);
  final barMs = converter.barDuration.inMicroseconds;
  final ringOut = converter.barDuration;
  final countIn = Duration(microseconds: barMs * countInBars);
  final musical = Duration(microseconds: barMs * definitionBars);
  final total = countIn + musical + ringOut;
  final barBoundaries = <Duration>[
    for (var b = 0; b <= countInBars; b++) Duration(microseconds: b * barMs),
    for (var b = 1; b <= definitionBars; b++)
      Duration(microseconds: (countInBars + b) * barMs),
  ];
  return CompiledPracticeTarget(
    definitionId: 'd',
    definitionSnapshotVersion: 1,
    tempo: tempo,
    meter: meter,
    countInBars: countInBars,
    countInDuration: countIn,
    events: const <CompiledTargetEvent>[],
    musicalDuration: musical,
    ringOutDuration: ringOut,
    totalDuration: total,
    barBoundaries: barBoundaries,
    loopCount: 1,
    loopRange: null,
    expectedChordSegments: const <ExpectedChordSegment>[],
    scoringApplicable: false,
  );
}

const _testDefinition = PracticeDefinition(
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

PracticeSessionConfig _config({
  Duration sessionTimeout = const Duration(minutes: 10),
  int countInBars = 1,
  Tempo? tempo,
}) => PracticeSessionConfig(
  definitionId: 'd',
  definitionSnapshotVersion: 1,
  effectiveTempo: tempo ?? const Tempo(120),
  countInBars: countInBars,
  loopCount: 1,
  metronomeEnabled: true,
  accentEnabled: true,
  backingEnabled: false,
  scoringProfileId: 'free',
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: false,
  sessionTimeout: sessionTimeout,
  reducedMotion: false,
);

PracticeClockSnapshot snap({
  Duration wall = Duration.zero,
  Duration active = Duration.zero,
  Duration paused = Duration.zero,
  Duration attempt = Duration.zero,
}) => PracticeClockSnapshot(
  wall: wall,
  active: active,
  paused: paused,
  attempt: attempt,
);

/// Bring a session to a given status from `idle` via the natural input
/// sequence. Returns the state at the end of seeding.
PracticeSessionState _seed({
  CompiledPracticeTarget? target,
  PracticeSessionConfig? config,
}) {
  final t = target ?? _targetFor();
  final c = config ?? _config();
  var state = PracticeSessionState.initial;
  state = reducePracticeSession(
    state,
    PreparePractice(definition: _testDefinition, config: c),
  ).state;
  state = reducePracticeSession(state, PreparationSucceeded(t)).state;
  state = reducePracticeSession(state, const StartPractice()).state;
  return state;
}

void main() {
  // ------------------------------------------------------------------
  // P1 — `permissionRequired` + `PreparationSucceeded` is REJECTED
  // (R1 MAJOR-2).
  // ------------------------------------------------------------------
  test('P1: permissionRequired + PreparationSucceeded is rejected', () {
    var state = PracticeSessionState.initial;
    state = reducePracticeSession(
      state,
      PreparePractice(definition: _testDefinition, config: _config()),
    ).state;
    expect(state.status, PracticeSessionStatus.preparing);

    state = reducePracticeSession(state, const PermissionDenied()).state;
    expect(state.status, PracticeSessionStatus.permissionRequired);

    final target = _targetFor();
    final transition = reducePracticeSession(
      state,
      PreparationSucceeded(target),
    );
    expect(transition.isRejected, isTrue);
    expect(
      transition.rejection!.from,
      PracticeSessionStatus.permissionRequired,
    );
    expect(transition.rejection!.input, 'PreparationSucceeded');
    expect(transition.effects, isEmpty);
    expect(transition.state, equals(state));
    expect(transition.state.status, PracticeSessionStatus.permissionRequired);
    expect(transition.state.target, isNull);
  });

  // ------------------------------------------------------------------
  // P1b — `permissionRequired` + `PreparationFailed` is REJECTED
  // (R1 MAJOR-2).
  // ------------------------------------------------------------------
  test('P1b: permissionRequired + PreparationFailed is rejected', () {
    var state = PracticeSessionState.initial;
    state = reducePracticeSession(
      state,
      PreparePractice(definition: _testDefinition, config: _config()),
    ).state;
    state = reducePracticeSession(state, const PermissionDenied()).state;
    expect(state.status, PracticeSessionStatus.permissionRequired);

    const failure = ValidationFailure(code: 'test.failure');
    final transition = reducePracticeSession(
      state,
      const PreparationFailed(failure),
    );
    expect(transition.isRejected, isTrue);
    expect(
      transition.rejection!.from,
      PracticeSessionStatus.permissionRequired,
    );
    expect(transition.rejection!.input, 'PreparationFailed');
    expect(transition.effects, isEmpty);
    expect(transition.state, equals(state));
    expect(transition.state.status, PracticeSessionStatus.permissionRequired);
    expect(transition.state.recoverableFailure, isNull);
  });

  // ------------------------------------------------------------------
  // P2 — 2-bar initial count-in emits 8 clicks (R1 MAJOR-4).
  // ------------------------------------------------------------------
  test('P2: 2-bar initial count-in (4/4, 120 BPM) emits 8 clicks', () {
    final target = _targetFor(countInBars: 2, definitionBars: 4);
    final config = _config(countInBars: 2);
    var state = _seed(target: target, config: config);
    expect(state.status, PracticeSessionStatus.countIn);
    expect(state.countInSpanBeats, 8); // 2 bars × 4 beats

    // One big ClockAdvanced that spans the whole count-in (4s) → all 8
    // clicks, in order, no duplicates.
    final transition = reducePracticeSession(
      state,
      ClockAdvanced(snap(active: const Duration(seconds: 4))),
    );
    state = transition.state;
    expect(state.status, PracticeSessionStatus.running);
    final clicks = transition.effects.whereType<PlayCountInClick>().toList();
    expect(
      clicks.map((c) => c.beatIndex).toList(),
      [0, 1, 2, 3, 4, 5, 6, 7],
      reason: 'expected 8 clicks for 2-bar initial count-in',
    );
  });

  // ------------------------------------------------------------------
  // P3 — timeout WINS over timeline completion when both fire in the
  // same tick (R1 MINOR-1, NOTE-1).
  // ------------------------------------------------------------------
  test('P3: timeout beats completedTimeline when both conditions hold', () {
    final config = _config(sessionTimeout: const Duration(seconds: 5));
    final target = _targetFor();
    var state = _seed(target: target, config: config);
    // Drive to running.
    state = reducePracticeSession(
      state,
      ClockAdvanced(snap(active: const Duration(seconds: 2))),
    ).state;
    expect(state.status, PracticeSessionStatus.running);

    // One tick: wall = 100s (way past 5s timeout), active = 10s (past
    // totalDuration = 8s). Both conditions hold; timeout MUST win.
    final transition = reducePracticeSession(
      state,
      ClockAdvanced(
        snap(
          wall: const Duration(seconds: 100),
          active: const Duration(seconds: 10),
        ),
      ),
    );
    expect(transition.state.status, PracticeSessionStatus.finishing);
    expect(
      transition.state.finishReason,
      PracticeFinishReason.timedOut,
      reason: 'timeout must beat completedTimeline per §5.6 (R1 MINOR-1)',
    );
  });

  // ------------------------------------------------------------------
  // P4 — pause > sessionTimeout closes the session (R1 MINOR-2).
  // ------------------------------------------------------------------
  test('P4: paused past sessionTimeout → finishing + timedOut', () {
    final config = _config(sessionTimeout: const Duration(seconds: 5));
    final target = _targetFor();
    var state = _seed(target: target, config: config);
    state = reducePracticeSession(
      state,
      ClockAdvanced(snap(active: const Duration(seconds: 2))),
    ).state;
    expect(state.status, PracticeSessionStatus.running);

    state = reducePracticeSession(
      state,
      const PausePractice(cause: PauseCause.user),
    ).state;
    expect(state.status, PracticeSessionStatus.paused);

    // 30 minutes of wall time passes — active stays at 2s, paused grows.
    final transition = reducePracticeSession(
      state,
      ClockAdvanced(
        snap(
          wall: const Duration(minutes: 30),
          active: const Duration(seconds: 2),
          paused: const Duration(minutes: 30),
        ),
      ),
    );
    expect(
      transition.state.status,
      PracticeSessionStatus.finishing,
      reason: 'timeout must fire from paused status (R1 MINOR-2)',
    );
    expect(transition.state.finishReason, PracticeFinishReason.timedOut);
  });

  // ------------------------------------------------------------------
  // P5 — second attempt timelinePosition starts at zero, not at
  // activeElapsed (R1 MAJOR-1).
  // ------------------------------------------------------------------
  test('P5: second attempt timelinePosition starts at Duration.zero', () {
    var state = _seed();
    state = reducePracticeSession(
      state,
      ClockAdvanced(snap(active: const Duration(seconds: 3))),
    ).state;
    expect(state.status, PracticeSessionStatus.running);

    state = reducePracticeSession(
      state,
      const PausePractice(cause: PauseCause.user),
    ).state;
    expect(state.status, PracticeSessionStatus.paused);

    final transition = reducePracticeSession(state, const RestartAttempt());
    state = transition.state;
    expect(state.status, PracticeSessionStatus.countIn);
    // R1 MAJOR-1: playhead MUST be zero, not activeElapsed.
    expect(
      state.timelinePosition,
      Duration.zero,
      reason:
          'second attempt timeline must start at 0 (R1 MAJOR-1 — '
          'was activeElapsed in R0)',
    );
    // And activeBase must carry the activeElapsed.
    expect(state.activeBase, const Duration(seconds: 3));

    // A 500 ms tick advances the timeline to exactly 500 ms.
    state = reducePracticeSession(
      state,
      ClockAdvanced(
        snap(
          wall: const Duration(seconds: 10),
          active: const Duration(milliseconds: 3500),
        ),
      ),
    ).state;
    expect(
      state.timelinePosition,
      const Duration(milliseconds: 500),
      reason:
          'second attempt timeline advances exactly with the delta past '
          'activeBase (R1 MAJOR-1 acceptance)',
    );
  });

  // ------------------------------------------------------------------
  // P6 — timelinePosition is NOT clamped (R1 MINOR-3). The new
  // invariant: when timelinePosition >= totalDuration, the status is
  // no longer `running`.
  // ------------------------------------------------------------------
  test('P6: timelinePosition can exceed totalDuration, status is no longer '
      'running', () {
    final target = _targetFor();
    var state = _seed(target: target);
    state = reducePracticeSession(
      state,
      ClockAdvanced(snap(active: const Duration(seconds: 2))),
    ).state;
    expect(state.status, PracticeSessionStatus.running);

    // Tick way past totalDuration = 8s.
    final transition = reducePracticeSession(
      state,
      ClockAdvanced(snap(active: const Duration(seconds: 30))),
    );
    state = transition.state;
    // Status MUST have moved off running (the §6.5 MINOR-3 invariant).
    expect(state.status, isNot(PracticeSessionStatus.running));
    expect(state.status, PracticeSessionStatus.finishing);
    // timelinePosition is NOT clamped to totalDuration (R1 MINOR-3).
    expect(
      state.timelinePosition,
      const Duration(seconds: 30),
      reason: 'getter must not clamp (R1 MINOR-3)',
    );
  });

  // ------------------------------------------------------------------
  // Bonus probe — statusPath is edge-by-edge (R1 MAJOR-3).
  // ------------------------------------------------------------------
  test('R1 MAJOR-3: statusPath walks every adjacent edge through '
      'allowedTransitions', () {
    var state = _seed();
    // First tick goes countIn → running (one edge).
    final t1 = reducePracticeSession(
      state,
      ClockAdvanced(snap(active: const Duration(seconds: 2))),
    );
    state = t1.state;
    expect(t1.statusPath, [
      PracticeSessionStatus.countIn,
      PracticeSessionStatus.running,
    ]);

    // Second tick drives through totalDuration → `running → finishing`.
    // The wasFinishing-only branch keeps `finishing → completed` on the
    // NEXT tick so the `finishing` state stays observable.
    final t2 = reducePracticeSession(
      state,
      ClockAdvanced(snap(active: const Duration(seconds: 30))),
    );
    expect(t2.statusPath, [
      PracticeSessionStatus.running,
      PracticeSessionStatus.finishing,
    ]);

    // Third tick — finishing enters as `wasFinishing`, then settles to
    // `completed`. Path: `[finishing, completed]`.
    final t3 = reducePracticeSession(
      t2.state,
      ClockAdvanced(snap(active: const Duration(seconds: 30))),
    );
    expect(t3.statusPath, [
      PracticeSessionStatus.finishing,
      PracticeSessionStatus.completed,
    ]);

    // Every adjacent pair in every statusPath is a member of the RAW
    // allowedTransitions table (not the transitive closure).
    for (final path in <List<PracticeSessionStatus>>[
      t1.statusPath,
      t2.statusPath,
      t3.statusPath,
    ]) {
      for (var i = 0; i + 1 < path.length; i++) {
        final from = path[i];
        final to = path[i + 1];
        expect(
          allowedTransitions[from]?.contains(to) ?? false,
          isTrue,
          reason: '$from → $to not in raw allowedTransitions',
        );
      }
    }
  });

  // ------------------------------------------------------------------
  // Acceptance — initial count-in span length is explicit field.
  // ------------------------------------------------------------------
  test('StartPractice sets countInSpanBeats = countInBars * beatsPerBar '
      '(R1 MAJOR-4)', () {
    final target = _targetFor(countInBars: 2);
    final config = _config(countInBars: 2);
    final state = _seed(target: target, config: config);
    expect(state.countInSpanBeats, 8); // 2 * 4
    expect(state.countInKind, PracticeCountInKind.initial);

    // After ResumePractice, countInSpanBeats = beatsPerBar.
    var s2 = _seed(target: target, config: config);
    s2 = reducePracticeSession(
      s2,
      ClockAdvanced(snap(active: const Duration(seconds: 2))),
    ).state;
    s2 = reducePracticeSession(
      s2,
      const PausePractice(cause: PauseCause.user),
    ).state;
    s2 = reducePracticeSession(s2, const ResumePractice()).state;
    expect(s2.countInSpanBeats, 4);
    expect(s2.countInKind, PracticeCountInKind.resume);
  });
}
