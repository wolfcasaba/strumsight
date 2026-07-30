import '../../../../core/foundation/app_failure.dart';
import '../application/practice_session_clock.dart';
import '../domain/model/compiled_practice_target.dart';
import '../domain/model/practice_definition.dart';
import '../domain/model/practice_session_config.dart';
import '../domain/model/practice_session_state.dart';
import '../domain/model/tempo.dart';

/// One input to the practice-session state machine.
///
/// Inputs are split into two branches:
///   - [PracticeSessionCommand] — user intent (the eleven SDD §11.4
///     commands).
///   - [PracticeSessionSignal] — environmental fact (preparation outcome,
///     permission result, clock advance).
///
/// The reducer takes a [PracticeSessionInput]; pattern-match on the sealed
/// type to dispatch.
sealed class PracticeSessionInput {
  const PracticeSessionInput();
}

/// A user-initiated action. The eleven commands of SDD §11.4.
sealed class PracticeSessionCommand extends PracticeSessionInput {
  const PracticeSessionCommand();
}

/// Begin compiling a definition + config. Drives `idle → preparing`.
final class PreparePractice extends PracticeSessionCommand {
  const PreparePractice({required this.definition, required this.config});

  final PracticeDefinition definition;
  final PracticeSessionConfig config;
}

/// User granted the microphone permission. Drives
/// `permissionRequired → preparing` to resume compilation.
final class GrantPermission extends PracticeSessionCommand {
  const GrantPermission();
}

/// User accepted the prepared target and tapped Start. Drives
/// `ready → countIn`. The reducer rejects this if `state.target == null`
/// (e.g. after a tempo change invalidated the target).
final class StartPractice extends PracticeSessionCommand {
  const StartPractice();
}

/// Pause the active session. Carries the cause so the UI can render the
/// right resume affordance.
final class PausePractice extends PracticeSessionCommand {
  const PausePractice({required this.cause});

  final PauseCause cause;
}

/// Resume a paused session — the reducer re-anchors the timeline to a bar
/// boundary and queues a one-bar resume count-in.
final class ResumePractice extends PracticeSessionCommand {
  const ResumePractice();
}

/// Restart the current attempt — only accepted from `paused`, `completed`
/// or `cancelled` (ADR 0073 §3.1). Running an attempt is rejected.
final class RestartAttempt extends PracticeSessionCommand {
  const RestartAttempt();
}

/// User explicitly finished the session. Drives `running/paused → finishing`
/// with `finishReason = userFinished`.
final class FinishPractice extends PracticeSessionCommand {
  const FinishPractice();
}

/// User cancelled the session. Terminal.
final class CancelPractice extends PracticeSessionCommand {
  const CancelPractice();
}

/// Retry after a failure. Drives `failed → preparing`.
final class RetryPractice extends PracticeSessionCommand {
  const RetryPractice();
}

/// User changed the tempo before the attempt (e.g. via Speed Builder).
///
/// Accepted from `ready`, `completed`, `cancelled` only. Swaps
/// `config.effectiveTempo` via `copyWith` and invalidates `target`. The
/// status does NOT change; the caller must `PreparePractice` again to
/// recompile.
final class ChangeTempoBeforeAttempt extends PracticeSessionCommand {
  const ChangeTempoBeforeAttempt(this.tempo);

  final Tempo tempo;
}

/// User accepted an adaptive suggestion (e.g. "Slow down a notch"). Same
/// effect as [ChangeTempoBeforeAttempt] — kept distinct so the reducer can
/// route to the right logging path later.
final class AcceptAdaptiveSuggestion extends PracticeSessionCommand {
  const AcceptAdaptiveSuggestion(this.tempo);

  final Tempo tempo;
}

/// An environmental fact — preparation outcome, permission result, clock
/// advance.
sealed class PracticeSessionSignal extends PracticeSessionInput {
  const PracticeSessionSignal();
}

/// Compilation finished successfully. Drives `preparing → ready` (or
/// `permissionRequired → ready` when the grant arrived mid-compile).
final class PreparationSucceeded extends PracticeSessionSignal {
  const PreparationSucceeded(this.target);

  final CompiledPracticeTarget target;
}

/// Compilation failed. Drives `preparing → failed` (or `permissionRequired
/// → failed`).
final class PreparationFailed extends PracticeSessionSignal {
  const PreparationFailed(this.failure);

  final AppFailure failure;
}

/// User refused (or system denied) the microphone permission. Drives
/// `preparing → permissionRequired`.
final class PermissionDenied extends PracticeSessionSignal {
  const PermissionDenied();
}

/// The clock advanced. The reducer applies the snapshot to the six
/// accumulators, may emit count-in click effects, may transition
/// `countIn → running`, and may drive `running → finishing` on timeout or
/// timeline completion.
final class ClockAdvanced extends PracticeSessionSignal {
  const ClockAdvanced(this.snapshot);

  final PracticeClockSnapshot snapshot;
}
