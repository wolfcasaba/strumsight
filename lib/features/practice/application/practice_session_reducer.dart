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
    required List<PracticeSessionStatus> statusPath,
    this.rejection,
  }) : effects = List<PracticeSessionEffect>.unmodifiable(effects),
       statusPath = List<PracticeSessionStatus>.unmodifiable(statusPath);

  /// Convenience constructor for the common case — single status (no
  /// internal lifecycle chains) and rejection nullable. The [statusPath]
  /// is built from the input state and (when accepted) the new state.
  factory PracticeSessionTransition.single({
    required PracticeSessionState state,
    required List<PracticeSessionEffect> effects,
    required PracticeSessionState inputState,
    InvalidSessionTransitionFailure? rejection,
  }) {
    final path = rejection != null || state.status == inputState.status
        ? <PracticeSessionStatus>[inputState.status]
        : <PracticeSessionStatus>[inputState.status, state.status];
    return PracticeSessionTransition(
      state: state,
      effects: effects,
      statusPath: path,
      rejection: rejection,
    );
  }

  /// The state produced by this step. When [rejection] is non-null, [state]
  /// equals the input state by value.
  final PracticeSessionState state;

  /// One-shot effects emitted by this step. Always empty when rejected.
  final List<PracticeSessionEffect> effects;

  /// The ordered statuses traversed by this step.
  ///
  /// Non-tick steps (commands / signals) always have a one-element path
  /// (the input status, even on rejection — so the property gate can assert
  /// the rejection without indexing beyond the array).
  ///
  /// `ClockAdvanced` ticks can chain multiple lifecycle edges in one step
  /// (e.g. `countIn → running → finishing → completed` when a single tick
  /// spans both the count-in end, the timeline end, and the finishing
  /// settle). The path is the full walk; every adjacent pair is asserted
  /// against the raw [allowedTransitions] table by the property gate
  /// (R1 MAJOR-3).
  final List<PracticeSessionStatus> statusPath;

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
          _effectsEqual(other.effects, effects) &&
          _statusPathEqual(other.statusPath, statusPath);

  @override
  int get hashCode => Object.hash(
    state,
    rejection,
    Object.hashAll(effects),
    Object.hashAll(statusPath),
  );
}

bool _statusPathEqual(
  List<PracticeSessionStatus> left,
  List<PracticeSessionStatus> right,
) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
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
  statusPath: [from],
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
    statusPath: [state.status, PracticeSessionStatus.preparing],
  );
}

PracticeSessionTransition _reduceGrantPermission(PracticeSessionState state) {
  if (state.status != PracticeSessionStatus.permissionRequired) {
    return _rejected(state, state.status, 'GrantPermission');
  }
  return PracticeSessionTransition(
    state: state.copyWith(status: PracticeSessionStatus.preparing),
    effects: const [],
    statusPath: const [
      PracticeSessionStatus.permissionRequired,
      PracticeSessionStatus.preparing,
    ],
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
  // R1 MAJOR-1: activeBase carries the active time at the moment of start,
  // NOT a bare zero. The clock's `active` accumulator survives across
  // attempts (the §5.5 booking rule), so on a RestartAttempt (which itself
  // does not reset the `active` accumulator) the playhead must wait
  // exactly `activeElapsed` before advancing off the bar-0 anchor.
  //
  // On a fresh session activeElapsed == 0 and the formula collapses to the
  // §5.5 "initial count-in" case.
  //
  // R1 MAJOR-4: countInSpanBeats is `countInBars * beatsPerBar` for an
  // initial span; ResumePractice writes `beatsPerBar`.
  final target = state.target!; // null-checked above
  final config = state.config!; // paired with target on the `ready` state
  final initialSpanBeats = config.countInBars * target.meter.beatsPerBar;
  final next = state.copyWith(
    status: PracticeSessionStatus.countIn,
    timelineBase: Duration.zero,
    activeBase: state.activeElapsed,
    countInKind: PracticeCountInKind.initial,
    countInSpanBeats: initialSpanBeats,
    countInSpanStartActive: state.activeElapsed,
    clearPausedAtTimeline: true,
    emittedCountInClicks: 0,
    clearPauseCause: true,
    clearFinishReason: true,
  );
  return PracticeSessionTransition(
    state: next,
    effects: const [],
    statusPath: const [
      PracticeSessionStatus.ready,
      PracticeSessionStatus.countIn,
    ],
  );
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
    countInKind: PracticeCountInKind.initial,
    countInSpanBeats: 0,
  );
  return PracticeSessionTransition(
    state: next,
    effects: const [],
    statusPath: [state.status, PracticeSessionStatus.paused],
  );
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
    countInKind: PracticeCountInKind.resume,
    countInSpanBeats: target.meter.beatsPerBar,
    countInSpanStartActive: state.activeElapsed,
    emittedCountInClicks: 0,
    clearPauseCause: true,
    clearPausedAtTimeline: true,
  );
  return PracticeSessionTransition(
    state: next,
    effects: const [],
    statusPath: const [
      PracticeSessionStatus.paused,
      PracticeSessionStatus.countIn,
    ],
  );
}

PracticeSessionTransition _reduceRestartAttempt(PracticeSessionState state) {
  switch (state.status) {
    case PracticeSessionStatus.paused:
      // R1 MAJOR-1: activeBase carries the CURRENT activeElapsed — the
      // clock's `active` accumulator survives across attempts. Setting it
      // to zero would put the second attempt's playhead at `activeElapsed`
      // instead of zero, skipping the initial count-in.
      //
      // R1 MAJOR-4: span length is the initial span
      // (`countInBars * beatsPerBar`); the kind is `initial`. From
      // `paused`, both target and config are guaranteed non-null.
      final initialSpanBeats = state.target == null || state.config == null
          ? 0
          : state.config!.countInBars * state.target!.meter.beatsPerBar;
      final next = state.copyWith(
        status: PracticeSessionStatus.countIn,
        timelineBase: Duration.zero,
        activeBase: state.activeElapsed,
        countInKind: PracticeCountInKind.initial,
        countInSpanBeats: initialSpanBeats,
        attemptIndex: state.attemptIndex + 1,
        countInElapsed: Duration.zero,
        playingElapsed: Duration.zero,
        attemptElapsed: Duration.zero,
        countInSpanStartActive: state.activeElapsed,
        emittedCountInClicks: 0,
        clearPauseCause: true,
        clearPausedAtTimeline: true,
        clearFinishReason: true,
        clearRecoverableFailure: true,
      );
      return PracticeSessionTransition(
        state: next,
        effects: const [PlayHaptic()],
        statusPath: const [
          PracticeSessionStatus.paused,
          PracticeSessionStatus.countIn,
        ],
      );
    case PracticeSessionStatus.completed:
    case PracticeSessionStatus.cancelled:
      // Per the §11.2 transition table, both states can return to `ready`;
      // the restart semantics (zero timeline, +1 attempt) are applied on top
      // so the caller can immediately send `StartPractice`.
      //
      // R1 MAJOR-1 / MAJOR-4: the table-driven status is `ready` (not
      // `countIn`), and the count-in bookkeeping is not initialised here —
      // `StartPractice` writes `activeBase = state.activeElapsed` and the
      // correct `countInSpanBeats`.
      final next = state.copyWith(
        status: PracticeSessionStatus.ready,
        timelineBase: Duration.zero,
        activeBase: state.activeElapsed,
        attemptIndex: state.attemptIndex + 1,
        countInElapsed: Duration.zero,
        playingElapsed: Duration.zero,
        attemptElapsed: Duration.zero,
        clearCountInSpanStartActive: true,
        clearPauseCause: true,
        clearPausedAtTimeline: true,
        clearFinishReason: true,
        clearRecoverableFailure: true,
      );
      return PracticeSessionTransition(
        state: next,
        effects: const [PlayHaptic()],
        statusPath: [state.status, PracticeSessionStatus.ready],
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
  return PracticeSessionTransition(
    state: next,
    effects: const [],
    statusPath: [state.status, PracticeSessionStatus.finishing],
  );
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
  return PracticeSessionTransition(
    state: next,
    effects: const [],
    statusPath: [state.status, PracticeSessionStatus.cancelled],
  );
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
    statusPath: const [
      PracticeSessionStatus.failed,
      PracticeSessionStatus.preparing,
    ],
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
    statusPath: [state.status], // status doesn't change — single-element path
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
    statusPath: [state.status], // status doesn't change — single-element path
  );
}

// --- Signals ---------------------------------------------------------------

PracticeSessionTransition _reducePreparationSucceeded(
  PracticeSessionState state,
  CompiledPracticeTarget target,
) {
  // R1 MAJOR-2: accepted ONLY from `preparing`. The §11.2 transition
  // table does not list `permissionRequired → ready`; if the permission
  // grant arrives mid-compile, the correct path is
  // `permissionRequired → preparing` (via GrantPermission) and THEN
  // `preparing → ready` here. A direct `permissionRequired → ready`
  // hop is a controlled rejection.
  if (state.status != PracticeSessionStatus.preparing) {
    return _rejected(state, state.status, 'PreparationSucceeded');
  }
  if (!_canTransition(state.status, PracticeSessionStatus.ready)) {
    return _rejected(state, state.status, 'PreparationSucceeded');
  }
  return PracticeSessionTransition(
    state: state.copyWith(
      status: PracticeSessionStatus.ready,
      target: target,
      clearRecoverableFailure: true,
    ),
    effects: const [],
    statusPath: const [
      PracticeSessionStatus.preparing,
      PracticeSessionStatus.ready,
    ],
  );
}

PracticeSessionTransition _reducePreparationFailed(
  PracticeSessionState state,
  AppFailure failure,
) {
  // R1 MAJOR-2: same gating as PreparationSucceeded — `preparing → failed`
  // is in the §11.2 table; `permissionRequired → failed` is not.
  if (state.status != PracticeSessionStatus.preparing) {
    return _rejected(state, state.status, 'PreparationFailed');
  }
  if (!_canTransition(state.status, PracticeSessionStatus.failed)) {
    return _rejected(state, state.status, 'PreparationFailed');
  }
  return PracticeSessionTransition(
    state: state.copyWith(
      status: PracticeSessionStatus.failed,
      recoverableFailure: failure,
      finishReason: PracticeFinishReason.failed,
    ),
    effects: [ShowRecoverableError(failure)],
    statusPath: const [
      PracticeSessionStatus.preparing,
      PracticeSessionStatus.failed,
    ],
  );
}

PracticeSessionTransition _reducePermissionDenied(PracticeSessionState state) {
  if (!_canTransition(state.status, PracticeSessionStatus.permissionRequired)) {
    return _rejected(state, state.status, 'PermissionDenied');
  }
  return PracticeSessionTransition(
    state: state.copyWith(status: PracticeSessionStatus.permissionRequired),
    effects: const [ShowPermissionSettings()],
    statusPath: [state.status, PracticeSessionStatus.permissionRequired],
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

  // The ordered status path traversed in THIS tick. The very first entry
  // is the input status (so even a no-op tick has a one-element path).
  final path = <PracticeSessionStatus>[previousStatus];

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

  // R1 MAJOR-4 + R1 MAJOR-1 — countIn → running when the count-in completes.
  // The kind field is the source of truth: `initial` exits when the
  // timeline reaches `target.countInDuration`; `resume` exits when the
  // active time reaches `activeBase` (one bar past the resume anchor).
  if (nextState.status == PracticeSessionStatus.countIn) {
    final kind = nextState.countInKind;
    final reachedRunning =
        target != null &&
        ((kind == PracticeCountInKind.initial &&
                nextState.timelinePosition >= target.countInDuration) ||
            (kind == PracticeCountInKind.resume &&
                snapshot.active >= nextState.activeBase));
    if (reachedRunning) {
      nextState = nextState.copyWith(
        status: PracticeSessionStatus.running,
        clearCountInSpanStartActive: true,
        countInKind: PracticeCountInKind.initial,
        countInSpanBeats: 0,
        emittedCountInClicks: 0,
      );
      path.add(PracticeSessionStatus.running);
    }
  }

  // R1 MINOR-1 — timeout wins over timeline completion. The §5.6
  // requirement is "the timeout is stronger": when both conditions hold
  // in the same tick, `finishReason` MUST be `timedOut`. Therefore the
  // `else if` order is exactly reversed compared to the R0 draft.
  //
  // R1 MINOR-2 — the timeout guard runs in BOTH `running` AND `paused`
  // status. `countIn` has no `finishing` edge in the §11.2 table and is
  // therefore exempt; the §5.6 wording "any active status" was a brief
  // bug caught in review.
  final shouldCheckTimeout =
      nextState.status == PracticeSessionStatus.running ||
      nextState.status == PracticeSessionStatus.paused;
  if (shouldCheckTimeout &&
      config != null &&
      snapshot.wall > config.sessionTimeout) {
    nextState = nextState.copyWith(
      status: PracticeSessionStatus.finishing,
      finishReason: PracticeFinishReason.timedOut,
      clearCountInSpanStartActive: true,
      countInKind: PracticeCountInKind.initial,
      countInSpanBeats: 0,
    );
    path.add(PracticeSessionStatus.finishing);
  } else if (nextState.status == PracticeSessionStatus.running &&
      target != null &&
      nextState.timelinePosition >= target.totalDuration) {
    nextState = nextState.copyWith(
      status: PracticeSessionStatus.finishing,
      finishReason: PracticeFinishReason.completedTimeline,
      clearCountInSpanStartActive: true,
      countInKind: PracticeCountInKind.initial,
      countInSpanBeats: 0,
    );
    path.add(PracticeSessionStatus.finishing);
  }

  // finishing → completed ONLY when the session was already in `finishing`
  // on entry to this ClockAdvanced tick — so the `finishing` state is
  // observable for at least one snapshot (per §5.6).
  final wasFinishing = state.status == PracticeSessionStatus.finishing;
  if (wasFinishing && nextState.status == PracticeSessionStatus.finishing) {
    nextState = nextState.copyWith(status: PracticeSessionStatus.completed);
    effects.add(const NavigateToResult());
    path.add(PracticeSessionStatus.completed);
  }

  return PracticeSessionTransition(
    state: nextState,
    effects: effects,
    statusPath: path,
  );
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

  // R1 MAJOR-4 — the span length is read from the explicit
  // `countInSpanBeats` state field, NOT from `meter.beatsPerBar`. The
  // initial span is `countInBars * beatsPerBar`; the resume span is
  // `beatsPerBar`.
  final beatsInSpan = state.countInSpanBeats;
  if (beatsInSpan <= 0) return const [];
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
