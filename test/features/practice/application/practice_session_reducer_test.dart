// Practice session state-machine tests — the 11 mandatory transition tests
// from §6.3 of the brief, plus the exhaustive (status × input) matrix that
// pins every accepted/rejected pair in code, plus rejection-shape assertions.
//
// The matrix table is a literal in this file, NOT derived from production
// code — adding a new status or input MUST force this table to be updated.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/practice/application/practice_session_clock.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_effect.dart';
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

final CompiledPracticeTarget _testTarget = CompiledPracticeTarget(
  definitionId: 'definition',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(120),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 1,
  countInDuration: const Duration(seconds: 2), // one bar of 4/4 at 120 BPM
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

const PracticeDefinition _testDefinition = PracticeDefinition(
  id: 'definition',
  schemaVersion: 1,
  titleKey: 'definition.title',
  descriptionKey: 'definition.description',
  mode: PracticeMode.freePractice,
  source: PracticeSource.builtin,
  meter: Meter(beatsPerBar: 4),
  defaultTempo: Tempo(120),
  totalBeats: BeatPosition(1920), // 4 bars of 4/4 at 480 PPQ
  events: <PracticeEvent>[],
  scoringProfile: ScoringProfile.freePracticeOpen,
  skillTags: <String>[],
);

PracticeSessionConfig _config({
  Duration sessionTimeout = const Duration(minutes: 10),
  int countInBars = 1,
  Tempo? tempo,
}) => PracticeSessionConfig(
  definitionId: 'definition',
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

PracticeClockSnapshot _snapshot({
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

void main() {
  // ------------------------------------------------------------------
  // 11 mandatory transition tests from §6.3
  // ------------------------------------------------------------------

  test('happy path: idle → preparing → ready → countIn → running → '
      'finishing → completed', () {
    var state = PracticeSessionState.initial;

    var t = reducePracticeSession(
      state,
      PreparePractice(definition: _testDefinition, config: _config()),
    );
    state = t.state;
    expect(state.status, PracticeSessionStatus.preparing);

    t = reducePracticeSession(state, PreparationSucceeded(_testTarget));
    state = t.state;
    expect(state.status, PracticeSessionStatus.ready);

    t = reducePracticeSession(state, const StartPractice());
    state = t.state;
    expect(state.status, PracticeSessionStatus.countIn);
    expect(state.timelineBase, Duration.zero);
    expect(state.activeBase, Duration.zero);

    // Drive the count-in to completion: snapshot.active reaches countInDuration.
    t = reducePracticeSession(
      state,
      ClockAdvanced(_snapshot(active: _testTarget.countInDuration)),
    );
    state = t.state;
    expect(state.status, PracticeSessionStatus.running);

    // Drive past totalDuration.
    t = reducePracticeSession(
      state,
      ClockAdvanced(_snapshot(active: _testTarget.totalDuration)),
    );
    state = t.state;
    expect(state.status, PracticeSessionStatus.finishing);
    expect(state.finishReason, PracticeFinishReason.completedTimeline);

    // finishing + ClockAdvanced → completed.
    t = reducePracticeSession(
      state,
      ClockAdvanced(_snapshot(active: _testTarget.totalDuration)),
    );
    state = t.state;
    expect(state.status, PracticeSessionStatus.completed);
    expect(t.effects, contains(const NavigateToResult()));
  });

  test(
    'permission path: preparing → permissionRequired → preparing → ready',
    () {
      var state = PracticeSessionState.initial;
      state = reducePracticeSession(
        state,
        PreparePractice(definition: _testDefinition, config: _config()),
      ).state;
      expect(state.status, PracticeSessionStatus.preparing);

      state = reducePracticeSession(state, const PermissionDenied()).state;
      expect(state.status, PracticeSessionStatus.permissionRequired);

      state = reducePracticeSession(state, const GrantPermission()).state;
      expect(state.status, PracticeSessionStatus.preparing);

      state = reducePracticeSession(
        state,
        PreparationSucceeded(_testTarget),
      ).state;
      expect(state.status, PracticeSessionStatus.ready);
    },
  );

  test('pause/resume: the resume count-in actually runs', () {
    // Build a paused state directly so we test the Resume path in isolation.
    var state = PracticeSessionState.initial.copyWith(
      status: PracticeSessionStatus.paused,
      config: _config(),
      target: _testTarget,
      pauseCause: PauseCause.user,
      pausedAtTimeline: const Duration(seconds: 4),
      activeElapsed: const Duration(seconds: 4),
    );

    // ResumePractice goes paused → countIn with the resume-policy applied.
    final transition = reducePracticeSession(state, const ResumePractice());
    state = transition.state;
    expect(state.status, PracticeSessionStatus.countIn);
    // Anchor = bar boundary at or before 4s = 4s.
    expect(state.timelineBase, const Duration(seconds: 4));
    // activeBase = active + barDuration = 4 + 2 = 6.
    expect(state.activeBase, const Duration(seconds: 6));
    // countInSpanStartActive = active at resume = 4.
    expect(state.countInSpanStartActive, const Duration(seconds: 4));
    expect(state.pauseCause, isNull);
    expect(state.pausedAtTimeline, isNull);
  });

  test('pause during count-in is accepted', () {
    var state = PracticeSessionState.initial.copyWith(
      status: PracticeSessionStatus.countIn,
      config: _config(),
      target: _testTarget,
    );
    final transition = reducePracticeSession(
      state,
      const PausePractice(cause: PauseCause.user),
    );
    state = transition.state;
    expect(state.status, PracticeSessionStatus.paused);
    expect(state.pauseCause, PauseCause.user);
    expect(state.pausedAtTimeline, Duration.zero); // pause happened at t=0
  });

  test('cancel before start: ready → cancelled', () {
    var state = PracticeSessionState.initial.copyWith(
      status: PracticeSessionStatus.ready,
      config: _config(),
      target: _testTarget,
    );
    final transition = reducePracticeSession(state, const CancelPractice());
    state = transition.state;
    expect(state.status, PracticeSessionStatus.cancelled);
    expect(state.finishReason, PracticeFinishReason.cancelled);
  });

  test('cancel during running: running → cancelled', () {
    var state = PracticeSessionState.initial.copyWith(
      status: PracticeSessionStatus.running,
      config: _config(),
      target: _testTarget,
    );
    final transition = reducePracticeSession(state, const CancelPractice());
    state = transition.state;
    expect(state.status, PracticeSessionStatus.cancelled);
    expect(state.finishReason, PracticeFinishReason.cancelled);
  });

  test('failure and retry: preparing → failed → preparing', () {
    var state = PracticeSessionState.initial;
    state = reducePracticeSession(
      state,
      PreparePractice(definition: _testDefinition, config: _config()),
    ).state;

    const failure = ValidationFailure(code: 'test.failure');
    state = reducePracticeSession(state, PreparationFailed(failure)).state;
    expect(state.status, PracticeSessionStatus.failed);
    expect(state.recoverableFailure, failure);

    state = reducePracticeSession(state, const RetryPractice()).state;
    expect(state.status, PracticeSessionStatus.preparing);
    expect(state.recoverableFailure, isNull);
  });

  test(
    'double start: the second StartPractice is rejected; state unchanged',
    () {
      var state = PracticeSessionState.initial.copyWith(
        status: PracticeSessionStatus.ready,
        config: _config(),
        target: _testTarget,
      );
      state = reducePracticeSession(state, const StartPractice()).state;
      expect(state.status, PracticeSessionStatus.countIn);

      final transition = reducePracticeSession(state, const StartPractice());
      expect(transition.isRejected, isTrue);
      expect(transition.rejection!.from, PracticeSessionStatus.countIn);
      expect(transition.rejection!.input, 'StartPractice');
      expect(transition.effects, isEmpty);
      expect(transition.state, equals(state));
    },
  );

  test('double finish: the second FinishPractice is rejected', () {
    var state = PracticeSessionState.initial.copyWith(
      status: PracticeSessionStatus.running,
      config: _config(),
      target: _testTarget,
    );
    state = reducePracticeSession(state, const FinishPractice()).state;
    expect(state.status, PracticeSessionStatus.finishing);

    final transition = reducePracticeSession(state, const FinishPractice());
    expect(transition.isRejected, isTrue);
    expect(transition.rejection!.from, PracticeSessionStatus.finishing);
    expect(transition.rejection!.input, 'FinishPractice');
  });

  test(
    'restart attempt: paused → countIn, attemptIndex +1, attemptElapsed 0',
    () {
      var state = PracticeSessionState.initial.copyWith(
        status: PracticeSessionStatus.paused,
        config: _config(),
        target: _testTarget,
        attemptIndex: 2,
        pauseCause: PauseCause.user,
        activeElapsed: const Duration(seconds: 5),
        playingElapsed: const Duration(seconds: 3),
      );

      final transition = reducePracticeSession(state, const RestartAttempt());
      state = transition.state;
      expect(state.status, PracticeSessionStatus.countIn);
      expect(state.attemptIndex, 3);
      expect(state.playingElapsed, Duration.zero);
      expect(state.timelineBase, Duration.zero);
      // R1 MAJOR-1: activeBase carries the activeElapsed — on a second
      // attempt, the clock's `active` accumulator survives, so the
      // timelineBase-anchored playhead must wait for it. On a fresh
      // session activeElapsed == 0 and the value collapses to zero; here
      // it equals 5s.
      expect(state.activeBase, const Duration(seconds: 5));
      expect(state.pauseCause, isNull);
      expect(state.timelinePosition, Duration.zero);
      expect(transition.effects, contains(const PlayHaptic()));
    },
  );

  test('background interruption: PausePractice(PauseCause.interruption) '
      'preserves the cause on the state', () {
    var state = PracticeSessionState.initial.copyWith(
      status: PracticeSessionStatus.running,
      config: _config(),
      target: _testTarget,
    );
    state = reducePracticeSession(
      state,
      const PausePractice(cause: PauseCause.interruption),
    ).state;
    expect(state.status, PracticeSessionStatus.paused);
    expect(state.pauseCause, PauseCause.interruption);
  });

  // ------------------------------------------------------------------
  // Exhaustive (status × input) matrix test — §6.3
  // ------------------------------------------------------------------

  group('exhaustive transition matrix', () {
    // For each (status, input) pair, this literal table records whether the
    // reducer must accept (→ listed target status) or reject (→ null).
    // Adding a new status or input MUST force an update here.
    final accepted = <(PracticeSessionStatus, Type), PracticeSessionStatus>{
      // PreparePractice
      (PracticeSessionStatus.idle, PreparePractice):
          PracticeSessionStatus.preparing,
      (PracticeSessionStatus.permissionRequired, PreparePractice):
          PracticeSessionStatus.preparing,
      // GrantPermission
      (PracticeSessionStatus.permissionRequired, GrantPermission):
          PracticeSessionStatus.preparing,
      // StartPractice
      (PracticeSessionStatus.ready, StartPractice):
          PracticeSessionStatus.countIn,
      // PausePractice
      (PracticeSessionStatus.countIn, PausePractice):
          PracticeSessionStatus.paused,
      (PracticeSessionStatus.running, PausePractice):
          PracticeSessionStatus.paused,
      // ResumePractice
      (PracticeSessionStatus.paused, ResumePractice):
          PracticeSessionStatus.countIn,
      // RestartAttempt
      (PracticeSessionStatus.paused, RestartAttempt):
          PracticeSessionStatus.countIn,
      (PracticeSessionStatus.completed, RestartAttempt):
          PracticeSessionStatus.ready,
      (PracticeSessionStatus.cancelled, RestartAttempt):
          PracticeSessionStatus.ready,
      // FinishPractice
      (PracticeSessionStatus.running, FinishPractice):
          PracticeSessionStatus.finishing,
      (PracticeSessionStatus.paused, FinishPractice):
          PracticeSessionStatus.finishing,
      // CancelPractice — only states whose transition table allows → cancelled
      // (per the §11.2 verbatim table; preparing → cancelled is not in the
      // table and is therefore rejected).
      (PracticeSessionStatus.permissionRequired, CancelPractice):
          PracticeSessionStatus.cancelled,
      (PracticeSessionStatus.ready, CancelPractice):
          PracticeSessionStatus.cancelled,
      (PracticeSessionStatus.countIn, CancelPractice):
          PracticeSessionStatus.cancelled,
      (PracticeSessionStatus.running, CancelPractice):
          PracticeSessionStatus.cancelled,
      (PracticeSessionStatus.paused, CancelPractice):
          PracticeSessionStatus.cancelled,
      // RetryPractice
      (PracticeSessionStatus.failed, RetryPractice):
          PracticeSessionStatus.preparing,
      // ChangeTempoBeforeAttempt — accepted but does NOT change status
      // (the §11.2 table has no edge for it; we keep the literal entries
      // here so the matrix still asserts the same value back).
      (PracticeSessionStatus.ready, ChangeTempoBeforeAttempt):
          PracticeSessionStatus.ready,
      (PracticeSessionStatus.completed, ChangeTempoBeforeAttempt):
          PracticeSessionStatus.completed,
      (PracticeSessionStatus.cancelled, ChangeTempoBeforeAttempt):
          PracticeSessionStatus.cancelled,
      // AcceptAdaptiveSuggestion — same as ChangeTempoBeforeAttempt.
      (PracticeSessionStatus.ready, AcceptAdaptiveSuggestion):
          PracticeSessionStatus.ready,
      (PracticeSessionStatus.completed, AcceptAdaptiveSuggestion):
          PracticeSessionStatus.completed,
      (PracticeSessionStatus.cancelled, AcceptAdaptiveSuggestion):
          PracticeSessionStatus.cancelled,
      // PreparationSucceeded — R1 MAJOR-2: ONLY from `preparing`. The
      // direct `permissionRequired → ready` hop is not in the §11.2 table
      // and is therefore rejected (the caller must GrantPermission first).
      (PracticeSessionStatus.preparing, PreparationSucceeded):
          PracticeSessionStatus.ready,
      // PreparationFailed — same gating as PreparationSucceeded.
      (PracticeSessionStatus.preparing, PreparationFailed):
          PracticeSessionStatus.failed,
      // PermissionDenied
      (PracticeSessionStatus.preparing, PermissionDenied):
          PracticeSessionStatus.permissionRequired,
    };

    // Helper to assemble the minimal state for any status.
    PracticeSessionState stateFor(PracticeSessionStatus status) {
      var state = PracticeSessionState.initial.copyWith(
        status: status,
        config: _config(),
        target: _testTarget,
      );
      // For paused status, set the pausedAtTimeline so ResumePractice is
      // meaningfully tested.
      if (status == PracticeSessionStatus.paused) {
        state = state.copyWith(
          pausedAtTimeline: const Duration(seconds: 4),
          activeElapsed: const Duration(seconds: 4),
        );
      }
      return state;
    }

    // The inputs to enumerate. ClockAdvanced is handled separately because
    // its behaviour depends on the snapshot and is covered by timing tests.
    final inputs = <(String, PracticeSessionInput Function())>[
      (
        'PreparePractice',
        () => PreparePractice(definition: _testDefinition, config: _config()),
      ),
      ('GrantPermission', () => const GrantPermission()),
      ('StartPractice', () => const StartPractice()),
      ('PausePractice', () => const PausePractice(cause: PauseCause.user)),
      ('ResumePractice', () => const ResumePractice()),
      ('RestartAttempt', () => const RestartAttempt()),
      ('FinishPractice', () => const FinishPractice()),
      ('CancelPractice', () => const CancelPractice()),
      ('RetryPractice', () => const RetryPractice()),
      (
        'ChangeTempoBeforeAttempt',
        () => const ChangeTempoBeforeAttempt(Tempo(90)),
      ),
      (
        'AcceptAdaptiveSuggestion',
        () => const AcceptAdaptiveSuggestion(Tempo(90)),
      ),
      ('PreparationSucceeded', () => PreparationSucceeded(_testTarget)),
      (
        'PreparationFailed',
        () => const PreparationFailed(ValidationFailure(code: 'x')),
      ),
      ('PermissionDenied', () => const PermissionDenied()),
    ];

    test('every (status, input) pair matches the pinned table', () {
      for (final status in PracticeSessionStatus.values) {
        for (final (label, make) in inputs) {
          final state = stateFor(status);
          final transition = reducePracticeSession(state, make());
          final inputType = make().runtimeType;
          final key = (status, inputType);
          final expectedTarget = accepted[key];

          if (expectedTarget != null) {
            expect(
              transition.isAccepted,
              isTrue,
              reason:
                  '$label from $status should be ACCEPTED, got '
                  'rejection=${transition.rejection}',
            );
            expect(
              transition.state.status,
              expectedTarget,
              reason:
                  '$label from $status → expected '
                  '$expectedTarget, got ${transition.state.status}',
            );
            expect(transition.effects, isNotNull);
          } else {
            expect(
              transition.isRejected,
              isTrue,
              reason:
                  '$label from $status should be REJECTED, got '
                  'accepted with new state ${transition.state}',
            );
            expect(transition.effects, isEmpty);
            expect(transition.rejection!.from, status);
            expect(transition.rejection!.input, label);
          }
        }
      }
    });

    test('rejected transitions return the input state by value', () {
      for (final status in PracticeSessionStatus.values) {
        final state = stateFor(status);
        for (final (label, make) in inputs) {
          final transition = reducePracticeSession(state, make());
          if (transition.isRejected) {
            expect(
              transition.state,
              equals(state),
              reason: 'rejected $label from $status must keep state',
            );
          }
        }
      }
    });

    test('reducer never throws on any (status, input) pair', () {
      for (final status in PracticeSessionStatus.values) {
        final state = stateFor(status);
        for (final (label, make) in inputs) {
          expect(
            () => reducePracticeSession(state, make()),
            returnsNormally,
            reason: 'reducer threw on $label from $status',
          );
        }
      }
    });
  });

  // ------------------------------------------------------------------
  // Rejection shape — fields carry the truth.
  // ------------------------------------------------------------------

  test('rejection carries from / input / code; never throws', () {
    final state = PracticeSessionState.initial;
    final transition = reducePracticeSession(state, const StartPractice());
    expect(transition.isRejected, isTrue);
    expect(transition.rejection!.from, PracticeSessionStatus.idle);
    expect(transition.rejection!.input, 'StartPractice');
    expect(
      transition.rejection!.code,
      FailureCode.practiceInvalidSessionTransition,
    );
    expect(transition.state, equals(state));
  });

  // ------------------------------------------------------------------
  // StartPractice special case: rejected if target == null (§5.4)
  // ------------------------------------------------------------------

  test('StartPractice is rejected when target is null', () {
    final state = PracticeSessionState.initial.copyWith(
      status: PracticeSessionStatus.ready,
      config: _config(),
    );
    final transition = reducePracticeSession(state, const StartPractice());
    expect(transition.isRejected, isTrue);
    expect(transition.rejection!.from, PracticeSessionStatus.ready);
    expect(transition.rejection!.input, 'StartPractice');
    expect(transition.rejection!.message, contains('target'));
  });

  test('ChangeTempoBeforeAttempt updates config.effectiveTempo and '
      'invalidates target', () {
    final state = PracticeSessionState.initial.copyWith(
      status: PracticeSessionStatus.ready,
      config: _config(),
      target: _testTarget,
    );
    final transition = reducePracticeSession(
      state,
      const ChangeTempoBeforeAttempt(Tempo(90)),
    );
    expect(transition.isAccepted, isTrue);
    expect(transition.state.status, PracticeSessionStatus.ready);
    expect(transition.state.config!.effectiveTempo, const Tempo(90));
    expect(transition.state.target, isNull);
  });

  // ------------------------------------------------------------------
  // §6.1 file-content guardrails: no own beat-to-time formula and no
  // ambient IO in the reducer / command / effect sources.
  // ------------------------------------------------------------------

  group('§6.1 source-purity guardrails', () {
    String read(String relativePath) =>
        File('lib/features/practice/$relativePath').readAsStringSync();

    test('reducer does not define its own beat-to-time formula '
        '(no bare `bpm` identifier, no `60` literal in arithmetic)', () {
      final source = read('application/practice_session_reducer.dart');
      // A "bpm" identifier in a string literal or comment is fine; we
      // scan the code mask like the domain purity test does.
      final bannedIdentifier = RegExp(r'\bbpm\b');
      final bannedLiteral = RegExp(r'\b60\s*[\.\)]');
      // The source IS allowed to reference the `bpm` field of a Tempo
      // instance — that's not a beat-to-time formula. So we only flag
      // `bpm` when used as a bare identifier on its own (e.g. as a
      // function or variable name).
      expect(
        bannedIdentifier.hasMatch(source),
        isFalse,
        reason:
            'reducer must not reference a `bpm` identifier directly — '
            'use BeatTimeConverter instead (ADR 0072 §1.1)',
      );
      expect(
        bannedLiteral.hasMatch(source),
        isFalse,
        reason:
            'reducer must not contain `60` as a numeric literal — '
            'use BeatTimeConverter for beat→time conversion',
      );
    });

    test(
      'reducer source does not contain DateTime.now, Stopwatch, Random, print',
      () {
        final source = read('application/practice_session_reducer.dart');
        for (final pattern in [
          r'DateTime\s*\.\s*now\s*\(',
          r'\bStopwatch\s*\(',
          r'\bRandom(?:\s*\.\s*secure)?\s*\(',
          r'\bprint\s*\(',
        ]) {
          expect(
            RegExp(pattern).hasMatch(source),
            isFalse,
            reason: 'reducer must not contain $pattern',
          );
        }
      },
    );

    test(
      'reducer / command / effect files do not import Flutter or Riverpod',
      () {
        for (final relative in const [
          'application/practice_session_reducer.dart',
          'application/practice_session_command.dart',
          'application/practice_session_effect.dart',
          'application/practice_session_clock.dart',
        ]) {
          final source = read(relative);
          for (final pattern in const [
            r'''import\s+['"]package:flutter/''',
            r'''import\s+['"]package:flutter_riverpod/''',
            r'''import\s+['"]package:riverpod/''',
          ]) {
            expect(
              RegExp(pattern).hasMatch(source),
              isFalse,
              reason: '$relative must not $pattern',
            );
          }
        }
      },
    );
  });
}
