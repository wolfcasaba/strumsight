import 'package:meta/meta.dart';

import '../../../../core/foundation/app_failure.dart';
import 'beat_position.dart';
import 'beat_time_converter.dart';
import 'compiled_practice_target.dart';
import 'practice_definition.dart';
import 'practice_session_config.dart';

/// One snapshot of the deterministic practice-session state machine.
///
/// All fields are final; updates are produced by the pure reducer (see
/// `practice_session_reducer.dart`) which returns a new state object. Value
/// equality is field-by-field.
@immutable
final class PracticeSessionState {
  const PracticeSessionState({
    required this.status,
    this.definition,
    this.config,
    this.target,
    this.attemptIndex = 0,
    this.finishReason,
    this.pauseCause,
    this.recoverableFailure,
    this.timelineBase = Duration.zero,
    this.activeBase = Duration.zero,
    this.pausedAtTimeline,
    this.countInSpanStartActive,
    this.emittedCountInClicks = 0,
    this.wallElapsed = Duration.zero,
    this.activeElapsed = Duration.zero,
    this.pausedElapsed = Duration.zero,
    this.countInElapsed = Duration.zero,
    this.playingElapsed = Duration.zero,
    this.attemptElapsed = Duration.zero,
  });

  /// Initial state — no definition, no config, no target; idle.
  static const PracticeSessionState initial = PracticeSessionState(
    status: PracticeSessionStatus.idle,
  );

  final PracticeSessionStatus status;
  final PracticeDefinition? definition;
  final PracticeSessionConfig? config;
  final CompiledPracticeTarget? target;
  final int attemptIndex;
  final PracticeFinishReason? finishReason;
  final PauseCause? pauseCause;
  final AppFailure? recoverableFailure;

  /// Timeline anchor — the `timelinePosition` value corresponding to the
  /// current `activeBase`. Set by `StartPractice` (zero) and
  /// `ResumePractice` (the bar-boundary anchor).
  final Duration timelineBase;

  /// `active` offset at which the playhead reaches `timelineBase`. For an
  /// initial session this is zero; for a resumed session it equals
  /// `active + barDuration` so the playhead waits one bar before resuming.
  final Duration activeBase;

  /// The `timelinePosition` value at the moment the session was paused, if
  /// currently in [PracticeSessionStatus.paused]. Used to compute the
  /// resume anchor.
  final Duration? pausedAtTimeline;

  /// The `active` value at the start of the current count-in span — used to
  /// compute count-in click boundaries.
  final Duration? countInSpanStartActive;

  /// How many count-in click effects have been emitted for the current
  /// count-in span. Reset at each span boundary.
  final int emittedCountInClicks;

  /// `wall` accumulator at the moment of the last accepted
  /// [ClockAdvanced] signal. Exclusively for `sessionTimeout` checks
  /// (§12.2 — must not be used for scoring or daily goal).
  final Duration wallElapsed;

  /// `active` accumulator at the moment of the last accepted
  /// [ClockAdvanced] signal.
  final Duration activeElapsed;

  /// `paused` accumulator at the moment of the last accepted
  /// [ClockAdvanced] signal.
  final Duration pausedElapsed;

  /// Active time accumulated while in [PracticeSessionStatus.countIn].
  final Duration countInElapsed;

  /// Active time accumulated while in [PracticeSessionStatus.running].
  /// Daily goal uses this exclusively (SDD §12.2).
  final Duration playingElapsed;

  /// `attempt` accumulator — active since the last
  /// [PracticeSessionClock.resetAttempt] call.
  final Duration attemptElapsed;

  /// Derived from the clock accumulators and the `timelineBase` anchor
  /// (ADR 0073 §4):
  ///
  /// ```text
  /// timelinePosition = timelineBase + max(Duration.zero, activeElapsed − activeBase)
  /// ```
  ///
  /// Clamped to `target.totalDuration` when the latter is set — the
  /// property invariant from §6.5 requires the position to never exceed
  /// totalDuration, so a single ClockAdvanced that overshoots the end of
  /// the timeline still reports `totalDuration` exactly.
  Duration get timelinePosition {
    final delta = activeElapsed - activeBase;
    final offset = delta < Duration.zero ? Duration.zero : delta;
    final computed = timelineBase + offset;
    final t = target;
    if (t != null && computed > t.totalDuration) return t.totalDuration;
    return computed;
  }

  /// Whether the session is in an active (not terminal) phase.
  bool get isActive => const {
    PracticeSessionStatus.countIn,
    PracticeSessionStatus.running,
    PracticeSessionStatus.paused,
    PracticeSessionStatus.finishing,
  }.contains(status);

  /// `BeatPosition` of the playhead relative to the musical origin
  /// (excluding count-in), or `null` while in count-in or before a target
  /// is available.
  BeatPosition? get musicalPosition {
    final target = this.target;
    if (target == null) return null;
    if (timelinePosition < target.countInDuration) return null;
    final converter = BeatTimeConverter(
      tempo: target.tempo,
      meter: target.meter,
    );
    return converter.positionAt(timelinePosition - target.countInDuration);
  }

  PracticeSessionState copyWith({
    PracticeSessionStatus? status,
    PracticeDefinition? definition,
    PracticeSessionConfig? config,
    CompiledPracticeTarget? target,
    int? attemptIndex,
    PracticeFinishReason? finishReason,
    PauseCause? pauseCause,
    AppFailure? recoverableFailure,
    Duration? timelineBase,
    Duration? activeBase,
    Duration? pausedAtTimeline,
    Duration? countInSpanStartActive,
    int? emittedCountInClicks,
    Duration? wallElapsed,
    Duration? activeElapsed,
    Duration? pausedElapsed,
    Duration? countInElapsed,
    Duration? playingElapsed,
    Duration? attemptElapsed,
    bool clearDefinition = false,
    bool clearConfig = false,
    bool clearTarget = false,
    bool clearFinishReason = false,
    bool clearPauseCause = false,
    bool clearRecoverableFailure = false,
    bool clearPausedAtTimeline = false,
    bool clearCountInSpanStartActive = false,
  }) => PracticeSessionState(
    status: status ?? this.status,
    definition: clearDefinition ? null : (definition ?? this.definition),
    config: clearConfig ? null : (config ?? this.config),
    target: clearTarget ? null : (target ?? this.target),
    attemptIndex: attemptIndex ?? this.attemptIndex,
    finishReason: clearFinishReason
        ? null
        : (finishReason ?? this.finishReason),
    pauseCause: clearPauseCause ? null : (pauseCause ?? this.pauseCause),
    recoverableFailure: clearRecoverableFailure
        ? null
        : (recoverableFailure ?? this.recoverableFailure),
    timelineBase: timelineBase ?? this.timelineBase,
    activeBase: activeBase ?? this.activeBase,
    pausedAtTimeline: clearPausedAtTimeline
        ? null
        : (pausedAtTimeline ?? this.pausedAtTimeline),
    countInSpanStartActive: clearCountInSpanStartActive
        ? null
        : (countInSpanStartActive ?? this.countInSpanStartActive),
    emittedCountInClicks: emittedCountInClicks ?? this.emittedCountInClicks,
    wallElapsed: wallElapsed ?? this.wallElapsed,
    activeElapsed: activeElapsed ?? this.activeElapsed,
    pausedElapsed: pausedElapsed ?? this.pausedElapsed,
    countInElapsed: countInElapsed ?? this.countInElapsed,
    playingElapsed: playingElapsed ?? this.playingElapsed,
    attemptElapsed: attemptElapsed ?? this.attemptElapsed,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSessionState &&
          other.status == status &&
          other.definition == definition &&
          other.config == config &&
          other.target == target &&
          other.attemptIndex == attemptIndex &&
          other.finishReason == finishReason &&
          other.pauseCause == pauseCause &&
          other.recoverableFailure == recoverableFailure &&
          other.timelineBase == timelineBase &&
          other.activeBase == activeBase &&
          other.pausedAtTimeline == pausedAtTimeline &&
          other.countInSpanStartActive == countInSpanStartActive &&
          other.emittedCountInClicks == emittedCountInClicks &&
          other.wallElapsed == wallElapsed &&
          other.activeElapsed == activeElapsed &&
          other.pausedElapsed == pausedElapsed &&
          other.countInElapsed == countInElapsed &&
          other.playingElapsed == playingElapsed &&
          other.attemptElapsed == attemptElapsed;

  @override
  int get hashCode => Object.hash(
    status,
    definition,
    config,
    target,
    attemptIndex,
    finishReason,
    pauseCause,
    recoverableFailure,
    timelineBase,
    activeBase,
    pausedAtTimeline,
    countInSpanStartActive,
    emittedCountInClicks,
    wallElapsed,
    activeElapsed,
    pausedElapsed,
    countInElapsed,
    playingElapsed,
    attemptElapsed,
  );
}

/// Practice session lifecycle states — SDD §11.2 verbatim.
///
/// The state machine has eleven states; transitions are exactly those in
/// [allowedTransitions]. Every other transition is rejected by the reducer.
enum PracticeSessionStatus {
  idle,
  preparing,
  permissionRequired,
  ready,
  countIn,
  running,
  paused,
  finishing,
  completed,
  cancelled,
  failed,
}

/// Const transition table — the only source of truth for which
/// `(from, to)` status pairs are legal. The reducer consults this map for
/// every status change.
///
/// SDD §11.2, transcribed verbatim:
/// ```
/// idle               -> preparing
/// preparing          -> permissionRequired | ready | failed
/// permissionRequired -> preparing | cancelled
/// ready              -> countIn | cancelled
/// countIn            -> running | paused | cancelled | failed
/// running            -> paused | finishing | cancelled | failed
/// paused             -> countIn | running | finishing | cancelled
/// finishing          -> completed | failed
/// completed          -> ready | idle
/// cancelled          -> ready | idle
/// failed             -> preparing | idle
/// ```
const Map<PracticeSessionStatus, Set<PracticeSessionStatus>>
allowedTransitions = {
  PracticeSessionStatus.idle: {PracticeSessionStatus.preparing},
  PracticeSessionStatus.preparing: {
    PracticeSessionStatus.permissionRequired,
    PracticeSessionStatus.ready,
    PracticeSessionStatus.failed,
  },
  PracticeSessionStatus.permissionRequired: {
    PracticeSessionStatus.preparing,
    PracticeSessionStatus.cancelled,
  },
  PracticeSessionStatus.ready: {
    PracticeSessionStatus.countIn,
    PracticeSessionStatus.cancelled,
  },
  PracticeSessionStatus.countIn: {
    PracticeSessionStatus.running,
    PracticeSessionStatus.paused,
    PracticeSessionStatus.cancelled,
    PracticeSessionStatus.failed,
  },
  PracticeSessionStatus.running: {
    PracticeSessionStatus.paused,
    PracticeSessionStatus.finishing,
    PracticeSessionStatus.cancelled,
    PracticeSessionStatus.failed,
  },
  PracticeSessionStatus.paused: {
    PracticeSessionStatus.countIn,
    PracticeSessionStatus.running,
    PracticeSessionStatus.finishing,
    PracticeSessionStatus.cancelled,
  },
  PracticeSessionStatus.finishing: {
    PracticeSessionStatus.completed,
    PracticeSessionStatus.failed,
  },
  PracticeSessionStatus.completed: {
    PracticeSessionStatus.ready,
    PracticeSessionStatus.idle,
  },
  PracticeSessionStatus.cancelled: {
    PracticeSessionStatus.ready,
    PracticeSessionStatus.idle,
  },
  PracticeSessionStatus.failed: {
    PracticeSessionStatus.preparing,
    PracticeSessionStatus.idle,
  },
};

/// Why the session entered [PracticeSessionStatus.paused]. Preserved on the
/// state so the UI can render the right affordance on resume.
enum PauseCause {
  /// User-initiated pause.
  user,

  /// System-initiated pause (phone call, app backgrounded, …).
  interruption,
}

/// How the session reached a terminal state.
enum PracticeFinishReason {
  /// Timeline reached `target.totalDuration` during
  /// [PracticeSessionStatus.running].
  completedTimeline,

  /// User explicitly tapped Finish.
  userFinished,

  /// User explicitly cancelled the session.
  cancelled,

  /// `wallElapsed` exceeded `config.sessionTimeout`.
  timedOut,

  /// An unrecoverable failure forced the session out (see
  /// [PracticeSessionState.recoverableFailure]).
  failed,
}
