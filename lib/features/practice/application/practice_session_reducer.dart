import 'package:meta/meta.dart';

import '../../../core/foundation/app_failure.dart';
import '../domain/model/beat_time_converter.dart';
import '../domain/model/compiled_practice_target.dart';
import '../domain/model/practice_definition.dart';
import '../domain/model/practice_session_config.dart';
import '../domain/model/practice_session_state.dart';
import '../domain/model/tempo.dart';
import 'practice_session_clock.dart';
import 'practice_session_command.dart';
import 'practice_session_effect.dart';

/// A controlled rejection of an input by the practice-session reducer.
///
/// The reducer never throws on an illegal `(state, input)` pair — instead it
/// returns the input state unchanged plus a rejection describing what was
/// rejected and why.
///
/// Deliberately NOT an [AppFailure] subclass — `AppFailure` is sealed, and
/// this rejection type is internal to the reducer. The [code] still points
/// at the stable [FailureCode.practiceInvalidSessionTransition] constant
/// so the UI can surface it through the same failure-code pipeline.
@immutable
final class InvalidSessionTransitionFailure {
  const InvalidSessionTransitionFailure({
    required this.from,
    required this.input,
    String? message,
  }) : _customMessage = message;

  /// The status the session was in when the input was rejected.
  final PracticeSessionStatus from;

  /// The fully-qualified input name (e.g. `'StartPractice'`, `'ClockAdvanced'`).
  final String input;

  final String? _customMessage;

  /// Stable machine code — see [FailureCode.practiceInvalidSessionTransition].
  String get code => FailureCode.practiceInvalidSessionTransition;

  /// Human-readable diagnostic message — NOT localized, only for logs.
  String get message =>
      _customMessage ??
      'Input $input is not accepted from status ${from.name}.';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvalidSessionTransitionFailure &&
          other.from == from &&
          other.input == input &&
          other.message == message;

  @override
  int get hashCode => Object.hash(from, input, message);

  @override
  String toString() =>
      'InvalidSessionTransitionFailure(from: ${from.name}, input: $input)';
}

/// The pure output of one reducer step.
@immutable
final class PracticeSessionTransition {
  PracticeSessionTransition({
    required this.state,
    required List<PracticeSessionEffect> effects,
    this.rejection,
  }) : effects = List<PracticeSessionEffect>.unmodifiable(effects);

  /// The state produced by this step. When [rejection] is non-null, [state]
  /// equals the input state by value.
  final PracticeSessionState state;

  /// One-shot effects emitted by this step. Always empty when rejected.
  final List<PracticeSessionEffect> effects;

  /// Non-null iff the input was rejected.
  final InvalidSessionTransitionFailure? rejection;

  bool get isRejected => rejection != null;

  bool get isAccepted => rejection == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSessionTransition &&
          other.state == state &&
          other.rejection == rejection &&
          _effectsEqual(other.effects, effects);

  @override
  int get hashCode => Object.hash(state, rejection, Object.hashAll(effects));
}

bool _effectsEqual(
  List<PracticeSessionEffect> left,
  List<PracticeSessionEffect> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

/// The pure reducer: `(state, input) → transition`.
///
/// Never throws. On rejection, returns the input state by value with an
/// empty effect list and a populated [InvalidSessionTransitionFailure].
PracticeSessionTransition reducePracticeSession(
  PracticeSessionState state,
  PracticeSessionInput input,
) {
  return switch (input) {
    PreparePractice(:final definition, :final config) => _reducePreparePractice(
      state,
      definition,
      config,
    ),
    GrantPermission() => _reduceGrantPermission(state),
    StartPractice() => _reduceStartPractice(state),
    PausePractice(:final cause) => _reducePausePractice(state, cause),
    ResumePractice() => _reduceResumePractice(state),
    RestartAttempt() => _reduceRestartAttempt(state),
    FinishPractice() => _reduceFinishPractice(state),
    CancelPractice() => _reduceCancelPractice(state),
    RetryPractice() => _reduceRetryPractice(state),
    ChangeTempoBeforeAttempt(:final tempo) => _reduceChangeTempoBeforeAttempt(
      state,
      tempo,
    ),
    AcceptAdaptiveSuggestion(:final tempo) => _reduceAcceptAdaptiveSuggestion(
      state,
      tempo,
    ),
    PreparationSucceeded(:final target) => _reducePreparationSucceeded(
      state,
      target,
    ),
    PreparationFailed(:final failure) => _reducePreparationFailed(
      state,
      failure,
    ),
    PermissionDenied() => _reducePermissionDenied(state),
    ClockAdvanced(:final snapshot) => _reduceClockAdvanced(state, snapshot),
  };
}

// --- Rejection helper ------------------------------------------------------

PracticeSessionTransition _rejected(
  PracticeSessionState state,
  PracticeSessionStatus from,
  String inputName, {
  String? message,
}) => PracticeSessionTransition(
  state: state,
  effects: const [],
  rejection: InvalidSessionTransitionFailure(
    from: from,
    input: inputName,
    message: message,
  ),
);

bool _canTransition(PracticeSessionStatus from, PracticeSessionStatus to) {
  final allowed = allowedTransitions[from];
  return allowed != null && allowed.contains(to);
}

// --- Commands --------------------------------------------------------------

PracticeSessionTransition _reducePreparePractice(
  PracticeSessionState state,
  PracticeDefinition definition,
  PracticeSessionConfig config,
) {
  if (state.status != PracticeSessionStatus.idle &&
      state.status != PracticeSessionStatus.permissionRequired) {
    return _rejected(state, state.status, 'PreparePractice');
  }
  return PracticeSessionTransition(
    state: state.copyWith(
      status: PracticeSessionStatus.preparing,
      definition: definition,
      config: config,
      clearTarget: true,
      clearPauseCause: true,
      clearRecoverableFailure: true,
    ),
    effects: const [],
  );
}

PracticeSessionTransition _reduceGrantPermission(PracticeSessionState state) {
  if (state.status != PracticeSessionStatus.permissionRequired) {
    return _rejected(state, state.status, 'GrantPermission');
  }
  return PracticeSessionTransition(
    state: state.copyWith(status: PracticeSessionStatus.preparing),
    effects: const [],
  );
}

PracticeSessionTransition _reduceStartPractice(PracticeSessionState state) {
  if (state.status != PracticeSessionStatus.ready) {
    return _rejected(state, state.status, 'StartPractice');
  }
  if (state.target == null) {
    return _rejected(
      state,
      state.status,
      'StartPractice',
      message:
          'StartPractice is rejected when state.target is null '
          '(e.g. after a tempo change invalidated the target).',
    );
  }
  final next = state.copyWith(
    status: PracticeSessionStatus.countIn,
    timelineBase: Duration.zero,
    activeBase: Duration.zero,
    countInSpanStartActive: state.activeElapsed,
    clearPausedAtTimeline: true,
    emittedCountInClicks: 0,
    clearPauseCause: true,
    clearFinishReason: true,
  );
  return PracticeSessionTransition(state: next, effects: const []);
}

PracticeSessionTransition _reducePausePractice(
  PracticeSessionState state,
  PauseCause cause,
) {
  if (!_canTransition(state.status, PracticeSessionStatus.paused)) {
    return _rejected(state, state.status, 'PausePractice');
  }
  final next = state.copyWith(
    status: PracticeSessionStatus.paused,
    pauseCause: cause,
    pausedAtTimeline: state.timelinePosition,
    clearCountInSpanStartActive: true,
  );
  return PracticeSessionTransition(state: next, effects: const []);
}

PracticeSessionTransition _reduceResumePractice(PracticeSessionState state) {
  if (state.status != PracticeSessionStatus.paused) {
    return _rejected(state, state.status, 'ResumePractice');
  }
  final target = state.target;
  final pausedAt = state.pausedAtTimeline;
  if (target == null || pausedAt == null) {
    return _rejected(
      state,
      state.status,
      'ResumePractice',
      message:
          'ResumePractice requires a non-null target and pausedAtTimeline.',
    );
  }
  final converter = BeatTimeConverter(tempo: target.tempo, meter: target.meter);
  final barDuration = converter.barDuration;
  final anchor = _barBoundaryAtOrBefore(target.barBoundaries, pausedAt);
  final activeBase = state.activeElapsed + barDuration;
  final next = state.copyWith(
    status: PracticeSessionStatus.countIn,
    timelineBase: anchor,
    activeBase: activeBase,
    countInSpanStartActive: state.activeElapsed,
    emittedCountInClicks: 0,
    clearPauseCause: true,
    clearPausedAtTimeline: true,
  );
  return PracticeSessionTransition(state: next, effects: const []);
}

PracticeSessionTransition _reduceRestartAttempt(PracticeSessionState state) {
  switch (state.status) {
    case PracticeSessionStatus.paused:
      final next = state.copyWith(
        status: PracticeSessionStatus.countIn,
        timelineBase: Duration.zero,
        activeBase: Duration.zero,
        attemptIndex: state.attemptIndex + 1,
        countInElapsed: Duration.zero,
        playingElapsed: Duration.zero,
        attemptElapsed: Duration.zero,
        emittedCountInClicks: 0,
        clearCountInSpanStartActive: true,
        clearPauseCause: true,
        clearPausedAtTimeline: true,
        clearFinishReason: true,
        clearRecoverableFailure: true,
      );
      return PracticeSessionTransition(
        state: next,
        effects: const [PlayHaptic()],
      );
    case PracticeSessionStatus.completed:
    case PracticeSessionStatus.cancelled:
      // Per the §11.2 transition table, both states can return to `ready`;
      // the restart semantics (zero timeline, +1 attempt) are applied on top
      // so the caller can immediately send `StartPractice`.
      final targetStatus = PracticeSessionStatus.ready;
      final next = state.copyWith(
        status: targetStatus,
        timelineBase: Duration.zero,
        activeBase: Duration.zero,
        attemptIndex: state.attemptIndex + 1,
        countInElapsed: Duration.zero,
        playingElapsed: Duration.zero,
        attemptElapsed: Duration.zero,
        emittedCountInClicks: 0,
        clearCountInSpanStartActive: true,
        clearPauseCause: true,
        clearPausedAtTimeline: true,
        clearFinishReason: true,
        clearRecoverableFailure: true,
      );
      return PracticeSessionTransition(
        state: next,
        effects: const [PlayHaptic()],
      );
    case PracticeSessionStatus.running:
      // Explicit ADR 0073 §3.1 rejection — running attempts cannot be
      // restarted; the caller must PausePractice first.
      return _rejected(
        state,
        state.status,
        'RestartAttempt',
        message: 'Running attempts cannot be restarted; pause first.',
      );
    case PracticeSessionStatus.idle:
    case PracticeSessionStatus.preparing:
    case PracticeSessionStatus.permissionRequired:
    case PracticeSessionStatus.ready:
    case PracticeSessionStatus.countIn:
    case PracticeSessionStatus.finishing:
    case PracticeSessionStatus.failed:
      return _rejected(state, state.status, 'RestartAttempt');
  }
}

PracticeSessionTransition _reduceFinishPractice(PracticeSessionState state) {
  if (!_canTransition(state.status, PracticeSessionStatus.finishing)) {
    return _rejected(state, state.status, 'FinishPractice');
  }
  final next = state.copyWith(
    status: PracticeSessionStatus.finishing,
    finishReason: PracticeFinishReason.userFinished,
    clearPauseCause: true,
  );
  return PracticeSessionTransition(state: next, effects: const []);
}

PracticeSessionTransition _reduceCancelPractice(PracticeSessionState state) {
  if (!_canTransition(state.status, PracticeSessionStatus.cancelled)) {
    return _rejected(state, state.status, 'CancelPractice');
  }
  final next = state.copyWith(
    status: PracticeSessionStatus.cancelled,
    finishReason: PracticeFinishReason.cancelled,
    clearPauseCause: true,
  );
  return PracticeSessionTransition(state: next, effects: const []);
}

PracticeSessionTransition _reduceRetryPractice(PracticeSessionState state) {
  if (state.status != PracticeSessionStatus.failed) {
    return _rejected(state, state.status, 'RetryPractice');
  }
  return PracticeSessionTransition(
    state: state.copyWith(
      status: PracticeSessionStatus.preparing,
      clearRecoverableFailure: true,
      clearFinishReason: true,
    ),
    effects: const [],
  );
}

PracticeSessionTransition _reduceChangeTempoBeforeAttempt(
  PracticeSessionState state,
  Tempo tempo,
) {
  if (state.status != PracticeSessionStatus.ready &&
      state.status != PracticeSessionStatus.completed &&
      state.status != PracticeSessionStatus.cancelled) {
    return _rejected(state, state.status, 'ChangeTempoBeforeAttempt');
  }
  final config = state.config;
  if (config == null) {
    return _rejected(state, state.status, 'ChangeTempoBeforeAttempt');
  }
  return PracticeSessionTransition(
    state: state.copyWith(
      config: config.copyWith(effectiveTempo: tempo),
      clearTarget: true,
    ),
    effects: const [],
  );
}

PracticeSessionTransition _reduceAcceptAdaptiveSuggestion(
  PracticeSessionState state,
  Tempo tempo,
) {
  if (state.status != PracticeSessionStatus.ready &&
      state.status != PracticeSessionStatus.completed &&
      state.status != PracticeSessionStatus.cancelled) {
    return _rejected(state, state.status, 'AcceptAdaptiveSuggestion');
  }
  final config = state.config;
  if (config == null) {
    return _rejected(state, state.status, 'AcceptAdaptiveSuggestion');
  }
  return PracticeSessionTransition(
    state: state.copyWith(
      config: config.copyWith(effectiveTempo: tempo),
      clearTarget: true,
    ),
    effects: const [],
  );
}

// --- Signals ---------------------------------------------------------------

PracticeSessionTransition _reducePreparationSucceeded(
  PracticeSessionState state,
  CompiledPracticeTarget target,
) {
  // Accepted from preparing (normal path) OR from permissionRequired when
  // the permission grant arrived mid-compile.
  if (state.status != PracticeSessionStatus.preparing &&
      state.status != PracticeSessionStatus.permissionRequired) {
    return _rejected(state, state.status, 'PreparationSucceeded');
  }
  return PracticeSessionTransition(
    state: state.copyWith(
      status: PracticeSessionStatus.ready,
      target: target,
      clearRecoverableFailure: true,
    ),
    effects: const [],
  );
}

PracticeSessionTransition _reducePreparationFailed(
  PracticeSessionState state,
  AppFailure failure,
) {
  if (state.status != PracticeSessionStatus.preparing &&
      state.status != PracticeSessionStatus.permissionRequired) {
    return _rejected(state, state.status, 'PreparationFailed');
  }
  return PracticeSessionTransition(
    state: state.copyWith(
      status: PracticeSessionStatus.failed,
      recoverableFailure: failure,
      finishReason: PracticeFinishReason.failed,
    ),
    effects: [ShowRecoverableError(failure)],
  );
}

PracticeSessionTransition _reducePermissionDenied(PracticeSessionState state) {
  if (!_canTransition(state.status, PracticeSessionStatus.permissionRequired)) {
    return _rejected(state, state.status, 'PermissionDenied');
  }
  return PracticeSessionTransition(
    state: state.copyWith(status: PracticeSessionStatus.permissionRequired),
    effects: const [ShowPermissionSettings()],
  );
}

// --- ClockAdvanced (Phase 4 lifecycle + Phase 5 timing) --------------------

PracticeSessionTransition _reduceClockAdvanced(
  PracticeSessionState state,
  PracticeClockSnapshot snapshot,
) {
  // Step 1 — apply the snapshot to the six accumulators. `countIn` and
  // `playing` are split by the status we were in *before* this tick, per
  // ADR 0073 §5: "az aktív deltát a feldolgozás ELŐTTI statushoz könyveld".
  final previousStatus = state.status;
  final activeDelta = snapshot.active - state.activeElapsed;

  var nextState = state.copyWith(
    wallElapsed: snapshot.wall,
    activeElapsed: snapshot.active,
    pausedElapsed: snapshot.paused,
    attemptElapsed: snapshot.attempt,
    countInElapsed: previousStatus == PracticeSessionStatus.countIn
        ? state.countInElapsed + activeDelta
        : state.countInElapsed,
    playingElapsed: previousStatus == PracticeSessionStatus.running
        ? state.playingElapsed + activeDelta
        : state.playingElapsed,
  );

  // Step 2 — emit count-in click effects for each beat boundary crossed
  // inside the snapshot delta. We use the PRE-tick status so that clicks
  // still fire when the count-in ends within this same tick.
  final effects = <PracticeSessionEffect>[];
  effects.addAll(_countInClicksCrossed(state, snapshot));
  if (effects.isNotEmpty) {
    nextState = nextState.copyWith(
      emittedCountInClicks: nextState.emittedCountInClicks + effects.length,
    );
  }

  // Step 3 — drive lifecycle transitions from the new timeline position.
  final config = nextState.config;
  final target = nextState.target;
  final position = nextState.timelinePosition;

  // countIn → running when the count-in completes. For the INITIAL count-in
  // (activeBase == 0) this happens when timelinePosition reaches the initial
  // count-in duration; for a RESUME count-in (activeBase > 0) it happens
  // when active time reaches activeBase (one bar past the resume point).
  if (nextState.status == PracticeSessionStatus.countIn) {
    final reachedRunning =
        target != null &&
        ((nextState.activeBase > Duration.zero &&
                snapshot.active >= nextState.activeBase) ||
            (nextState.activeBase == Duration.zero &&
                position >= target.countInDuration));
    if (reachedRunning) {
      nextState = nextState.copyWith(
        status: PracticeSessionStatus.running,
        clearCountInSpanStartActive: true,
        emittedCountInClicks: 0,
      );
    }
  }

  // running → finishing on timeline completion OR wall-time timeout.
  if (nextState.status == PracticeSessionStatus.running) {
    if (target != null && position >= target.totalDuration) {
      nextState = nextState.copyWith(
        status: PracticeSessionStatus.finishing,
        finishReason: PracticeFinishReason.completedTimeline,
      );
    } else if (config != null && snapshot.wall > config.sessionTimeout) {
      nextState = nextState.copyWith(
        status: PracticeSessionStatus.finishing,
        finishReason: PracticeFinishReason.timedOut,
      );
    }
  }

  // finishing → completed ONLY when the session was already in `finishing`
  // on entry to this ClockAdvanced tick — so the `finishing` state is
  // observable for at least one snapshot (per §5.6).
  final wasFinishing = state.status == PracticeSessionStatus.finishing;
  if (wasFinishing && nextState.status == PracticeSessionStatus.finishing) {
    nextState = nextState.copyWith(status: PracticeSessionStatus.completed);
    effects.add(const NavigateToResult());
  }

  return PracticeSessionTransition(state: nextState, effects: effects);
}

List<PracticeSessionEffect> _countInClicksCrossed(
  PracticeSessionState state,
  PracticeClockSnapshot snapshot,
) {
  if (state.status != PracticeSessionStatus.countIn) return const [];
  final target = state.target;
  final spanStart = state.countInSpanStartActive;
  if (target == null || spanStart == null) return const [];

  final converter = BeatTimeConverter(tempo: target.tempo, meter: target.meter);
  final beatDuration = converter.beatDuration;
  final beatsInSpan = target.meter.beatsPerBar;
  final spanStartActive = spanStart;

  // Click boundaries are at `spanStartActive + k * beatDuration` for
  // k = state.emittedCountInClicks … beatsInSpan - 1. Each boundary that
  // lies within (state.activeElapsed, snapshot.active] is emitted exactly
  // once — the range guard below handles the lower bound.
  final startBeat = state.emittedCountInClicks;
  if (startBeat >= beatsInSpan) return const [];

  final effects = <PracticeSessionEffect>[];
  for (var k = startBeat; k < beatsInSpan; k++) {
    final boundaryActive = spanStartActive + beatDuration * k;
    if (boundaryActive > snapshot.active) break;
    if (boundaryActive < state.activeElapsed) {
      // The boundary was crossed in an earlier tick — already emitted or
      // impossible (the first tick cannot have prior crossings); skip.
      continue;
    }
    effects.add(PlayCountInClick(k));
  }
  return effects;
}

// --- Helpers ---------------------------------------------------------------

Duration _barBoundaryAtOrBefore(List<Duration> boundaries, Duration time) {
  Duration result = Duration.zero;
  for (final boundary in boundaries) {
    if (boundary <= time) {
      result = boundary;
    } else {
      break;
    }
  }
  return result;
}
