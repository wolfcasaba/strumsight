import 'dart:async';

import 'package:meta/meta.dart';

import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/platform/microphone_permission.dart';
import '../domain/model/compiled_practice_target.dart';
import '../domain/model/practice_attempt_result.dart';
import '../domain/model/practice_definition.dart';
import '../domain/model/practice_observation.dart';
import '../domain/model/practice_session_config.dart';
import '../domain/model/practice_session_result.dart' as presult;
import '../domain/model/practice_session_state.dart';
import '../domain/model/scoring_profile.dart';
import '../domain/repository/practice_session_recorder.dart';
import '../domain/service/practice_chord_scorer.dart';
import '../domain/service/practice_direction_scorer.dart';
import '../domain/service/practice_event_matcher.dart';
import '../domain/service/practice_score_aggregator.dart';
import '../domain/service/practice_timing_scorer.dart';
import 'practice_observation_activation.dart';
import 'practice_observation_gateway.dart';
import 'practice_session_clock.dart';
import 'practice_session_command.dart';
import 'practice_session_effect.dart';
import 'practice_session_reducer.dart';
import 'practice_tick_source.dart';

/// The single first-call orchestrator of the Practice V2 session
/// (ADR 0077, E02-R11 brief).
///
/// Responsibilities (exhaustive):
///   1. Convert external inputs into [PracticeSessionInput]s and drive
///      [reducePracticeSession] — never mutates state directly.
///   2. Surface the reducer's [PracticeSessionEffect]s on the
///      [effects] stream.
///   3. Own the resource lifecycle: the [PracticeObservationGateway],
///      the [PracticeSessionClock], the [PracticeTickSource], and the
///      [PracticeSessionRecorder]. The audio session lease is **NOT**
///      owned here — `MicCapture` acquires it on the gateway's behalf
///      (ADR 0077 §10).
///   4. Run the scoring pass on `StrumObservation`s and on session
///      finish. Chord observations are accumulated only.
///
/// Forbidden dependencies (A9 guard): `BuildContext`, `Navigator`,
/// `GoRouter`, `SharedPreferences`, `StrumEngine(`, `dart:ui`,
/// `DateTime.now(`, `AudioSessionCoordinator`,
/// `audioSessionCoordinatorProvider`.
final class PracticeSessionController {
  PracticeSessionController({
    required this.clock,
    required this.tickSource,
    required this.recorder,
    required this.logger,
    required this.permissions,
    required this.observationConfig,
    required this.sessionIdFactory,
    required this.compileTarget,
    PracticeObservationGateway? observationGateway,
    PracticeEventMatcher? matcher,
    PracticeTimingScorer? timingScorer,
    PracticeDirectionScorer? directionScorer,
    PracticeChordScorer? chordScorer,
    PracticeScoreAggregator? aggregator,
  }) {
    _observationGateway = observationGateway;
    _matcher = matcher;
    _timingScorer = timingScorer ?? const PracticeTimingScorer();
    _directionScorer = directionScorer ?? const PracticeDirectionScorer();
    _chordScorer = chordScorer ?? const PracticeChordScorer();
    _aggregator = aggregator ?? const PracticeScoreAggregator();
    final gateway = _observationGateway;
    if (gateway != null) {
      _observationSubscription = gateway.observations.listen(
        _onObservation,
        onError: _onObservationStreamError,
        cancelOnError: false,
      );
    }
  }

  // --- Injected dependencies ------------------------------------------------
  final PracticeSessionClock clock;
  final PracticeTickSource tickSource;
  final PracticeSessionRecorder recorder;
  final AppLogger logger;
  final MicrophonePermissionGateway permissions;
  final PracticeObservationConfig observationConfig;
  final String Function() sessionIdFactory;
  final Future<AppResult<CompiledPracticeTarget>> Function(
    PracticeDefinition definition,
    PracticeSessionConfig config,
  ) compileTarget;

  // --- Internal configurable dependencies -----------------------------------
  PracticeObservationGateway? _observationGateway;
  PracticeEventMatcher? _matcher;
  late final PracticeTimingScorer _timingScorer;
  late final PracticeDirectionScorer _directionScorer;
  late final PracticeChordScorer _chordScorer;
  late final PracticeScoreAggregator _aggregator;

  // --- Mutable runtime state ------------------------------------------------
  StreamSubscription<PracticeObservation>? _observationSubscription;
  CompiledPracticeTarget? _currentTarget;
  ScoringProfile? _currentScoringProfile;
  final Map<int, StrumObservation> _observationsByTargetIndex = {};
  final List<ChordObservation> _chordObservations = [];

  final StreamController<PracticeSessionState> _statesController =
      StreamController<PracticeSessionState>.broadcast();
  final StreamController<PracticeSessionEffect> _effectsController =
      StreamController<PracticeSessionEffect>.broadcast();

  PracticeSessionState _state = PracticeSessionState.initial;
  PracticeScoreAggregation? _liveScore;
  presult.PracticeSessionResult? _result;
  bool _recordInvoked = false;
  bool _disposed = false;

  // --- Test-visible counters ------------------------------------------------
  int _gatewayStartCalls = 0;
  int _gatewayStopCalls = 0;
  int _gatewayDisposeCalls = 0;
  int _compileAttempts = 0;
  bool _gatewayActive = false;
  String? _lastExpectedChord;
  int _navigateToResultEffects = 0;

  // --- Public read-only surface --------------------------------------------
  Stream<PracticeSessionState> get states => _statesController.stream;
  PracticeSessionState get state => _state;
  Stream<PracticeSessionEffect> get effects => _effectsController.stream;
  PracticeScoreAggregation? get liveScore => _liveScore;
  presult.PracticeSessionResult? get result => _result;

  @visibleForTesting
  int get gatewayStartCalls => _gatewayStartCalls;
  @visibleForTesting
  int get gatewayStopCalls => _gatewayStopCalls;
  @visibleForTesting
  int get gatewayDisposeCalls => _gatewayDisposeCalls;
  @visibleForTesting
  int get compileAttempts => _compileAttempts;
  @visibleForTesting
  bool get gatewayIsActive => _gatewayActive;
  @visibleForTesting
  String? get lastExpectedChord => _lastExpectedChord;
  @visibleForTesting
  int get navigateToResultEffects => _navigateToResultEffects;
  @visibleForTesting
  bool get isDisposed => _disposed;

  // --- Dispatch ------------------------------------------------------------

  Future<void> dispatch(PracticeSessionInput input) async {
    if (_disposed) return;
    final transition = reducePracticeSession(_state, input);
    _state = transition.state;
    if (!transition.isRejected) {
      _statesController.add(transition.state);
      for (final effect in transition.effects) {
        _effectsController.add(effect);
        if (effect is NavigateToResult) _navigateToResultEffects++;
      }
    } else {
      logger.warning(
        'practice_session_input_rejected',
        fields: <String, Object?>{
          'input': transition.rejection!.input,
          'from': transition.rejection!.from.name,
        },
      );
    }
    await _applySideEffects(transition, input);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    tickSource.stop();
    final subscription = _observationSubscription;
    _observationSubscription = null;
    await subscription?.cancel();
    await _stopAndDisposeGateway();
    await _statesController.close();
    await _effectsController.close();
  }

  // --- Side-effect handlers ------------------------------------------------

  Future<void> _applySideEffects(
    PracticeSessionTransition transition,
    PracticeSessionInput input,
  ) async {
    final path = transition.statusPath;

    // Capture-activation sync.
    for (final status in path) {
      final shouldBeActive = practiceCaptureActive(status);
      if (shouldBeActive && !_gatewayActive) {
        await _startGateway();
      } else if (!shouldBeActive && _gatewayActive) {
        await _stopGateway();
      }
    }

    // Input-driven resource wiring.
    if (input is PreparePractice) {
      await _onPreparePractice(input);
    }
    if (input is PausePractice) {
      clock.pause();
    }
    if (input is ResumePractice) {
      clock.resume();
    }
    if (input is StartPractice) {
      clock.start();
      clock.resetAttempt();
      _resetAttemptObservation();
    }
    if (input is RestartAttempt) {
      clock.resetAttempt();
      _resetAttemptObservation();
    }

    // Terminal-state cleanup.
    final newStatus = transition.state.status;
    if (newStatus == PracticeSessionStatus.completed) {
      await _finalizeSession(terminalReason: _stateReasonOn(transition.state));
    } else if (newStatus == PracticeSessionStatus.cancelled) {
      await _stopAndDisposeGateway();
      await _finalizeSession(terminalReason: _stateReasonOn(transition.state));
    } else if (newStatus == PracticeSessionStatus.failed) {
      await _stopAndDisposeGateway();
      await _finalizeSession(terminalReason: _stateReasonOn(transition.state));
    }

    // Tick-source management.
    if (const {
      PracticeSessionStatus.countIn,
      PracticeSessionStatus.running,
      PracticeSessionStatus.paused,
      PracticeSessionStatus.finishing,
    }.contains(newStatus)) {
      tickSource.start(_onTick);
    } else if (const {
      PracticeSessionStatus.completed,
      PracticeSessionStatus.cancelled,
      PracticeSessionStatus.failed,
    }.contains(newStatus)) {
      tickSource.stop();
    }

    // Expected-chord update.
    if (_gatewayActive) {
      _pushExpectedChord(transition.state);
    }
  }

  Future<void> _startGateway() async {
    final gateway = _observationGateway;
    if (gateway == null) return;
    if (_gatewayActive) return;
    _gatewayStartCalls++;
    final result = await gateway.start(config: observationConfig);
    if (result case Failure(:final error)) {
      logger.warning(
        'practice_session_gateway_start_failed',
        error: error,
        fields: <String, Object?>{'code': error.code},
      );
      _effectsController.add(ShowRecoverableError(error));
      _gatewayActive = false;
      await _driveControlledFailure(error);
    } else {
      _gatewayActive = true;
    }
  }

  Future<void> _stopGateway() async {
    final gateway = _observationGateway;
    if (gateway == null) return;
    if (!_gatewayActive) return;
    _gatewayStopCalls++;
    final result = await gateway.stop();
    if (result case Failure(:final error)) {
      logger.warning(
        'practice_session_gateway_stop_failed',
        error: error,
        fields: <String, Object?>{'code': error.code},
      );
    }
    _gatewayActive = false;
    gateway.setExpectedChord(null);
    _lastExpectedChord = null;
  }

  Future<void> _stopAndDisposeGateway() async {
    await _stopGateway();
    final gateway = _observationGateway;
    if (gateway == null) return;
    if (_gatewayDisposeCalls == 0) {
      _gatewayDisposeCalls++;
      await gateway.dispose();
    }
  }

  Future<void> _driveControlledFailure(AppFailure error) async {
    if (_disposed) return;
    await dispatch(PreparationFailed(error));
  }

  Future<void> _onPreparePractice(PreparePractice input) async {
    _compileAttempts++;
    final state = await permissions.currentState();
    if (!state.isGranted) {
      final next = await permissions.request();
      if (!next.isGranted) {
        await dispatch(const PermissionDenied());
        return;
      }
    }

    final compileResult = await compileTarget(input.definition, input.config);
    switch (compileResult) {
      case Success(:final value):
        _currentTarget = value;
        _currentScoringProfile = input.definition.scoringProfile;
        _matcher = _matcher ?? PracticeEventMatcher(
                target: value,
                scoringProfile: _currentScoringProfile!,
                inputLatency: input.config.inputLatency,
              );
        _resetAttemptObservation();
        await dispatch(PreparationSucceeded(value));
      case Failure(:final error):
        await dispatch(PreparationFailed(error));
    }
  }

  void _resetAttemptObservation() {
    _liveScore = null;
  }

  void _onTick() {
    if (_disposed) return;
    dispatch(ClockAdvanced(clock.now()));
  }

  void _onObservation(PracticeObservation observation) {
    if (_disposed) return;
    final matcher = _matcher;
    final target = _currentTarget;
    if (matcher == null || target == null) return;
    if (observation is StrumObservation) {
      final matched = matcher.registerStrum(observation);
      if (matched != null) {
        _observationsByTargetIndex[matched.targetIndex] = observation;
      }
      _runScoringPass();
    } else if (observation is ChordObservation) {
      _chordObservations.add(observation);
    }
  }

  void _onObservationStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    final mapped = error is AppFailure
        ? error
        : AudioFailure(
            code: FailureCode.practiceObservationStreamFailed,
            cause: error,
            stackTrace: stackTrace,
          );
    logger.warning(
      'practice_session_observation_stream_failed',
      error: mapped,
      stackTrace: stackTrace,
      fields: <String, Object?>{'code': mapped.code},
    );
    _effectsController.add(ShowRecoverableError(mapped));
  }

  void _runScoringPass() {
    final matcher = _matcher;
    final target = _currentTarget;
    final scoringProfile = _currentScoringProfile;
    if (matcher == null || target == null || scoringProfile == null) return;
    final matches = matcher.results;
    final timing = _timingScorer.score(
      matches: matches,
      scoringProfile: scoringProfile,
    );
    final direction = _directionScorer.score(
      matches: matches,
      observationsByTargetIndex: _observationsByTargetIndex,
    );
    final chord = _chordScorer.score(
      matches: matches,
      observations: _chordObservations,
      chordStableDuration: observationConfig.chordStableDuration,
    );
    _liveScore = _aggregator.aggregate(
      matches: matches,
      scoringProfile: scoringProfile,
      timing: timing,
      direction: direction,
      chord: chord,
    );
  }

  Future<void> _finalizeSession({
    required PracticeFinishReason terminalReason,
  }) async {
    if (_recordInvoked) return;
    _recordInvoked = true;
    final matcher = _matcher;
    final target = _currentTarget;
    final scoringProfile = _currentScoringProfile;
    final attemptResult = _buildFinalAttemptResult(
      matcher: matcher,
      target: target,
      scoringProfile: scoringProfile,
    );
    final finishReason = _mapFinishReason(terminalReason);
    final result = presult.PracticeSessionResult(
      id: sessionIdFactory(),
      activeDuration: _state.activeElapsed,
      pausedDuration: _state.pausedElapsed,
      attempts: attemptResult == null ? const [] : [attemptResult],
      finishReason: finishReason,
      highestStableTempo: target?.tempo,
      coachingSummary: _coachingSummary(),
    );
    _result = result;
    final recordResult = await recorder.record(result);
    if (recordResult case Failure(:final error)) {
      logger.warning(
        'practice_session_record_failed',
        error: error,
        fields: <String, Object?>{'code': error.code},
      );
      _effectsController.add(ShowRecoverableError(error));
    }
    tickSource.stop();
    final subscription = _observationSubscription;
    _observationSubscription = null;
    await subscription?.cancel();
  }

  /// Maps the state-oldali finish reason to the result-oldali one. Per
  /// ADR 0077 §9: the result's `interrupted` is never emitted here.
  presult.PracticeFinishReason _mapFinishReason(
    PracticeFinishReason stateReason,
  ) {
    return switch (stateReason) {
      PracticeFinishReason.completedTimeline =>
        presult.PracticeFinishReason.completedAllTargets,
      PracticeFinishReason.userFinished =>
        presult.PracticeFinishReason.userFinished,
      PracticeFinishReason.cancelled => presult.PracticeFinishReason.cancelled,
      PracticeFinishReason.timedOut => presult.PracticeFinishReason.timedOut,
      PracticeFinishReason.failed => presult.PracticeFinishReason.failed,
    };
  }

  PracticeFinishReason _stateReasonOn(PracticeSessionState terminalState) {
    final reason = terminalState.finishReason;
    if (reason == null) {
      return switch (terminalState.status) {
        PracticeSessionStatus.completed =>
          PracticeFinishReason.completedTimeline,
        PracticeSessionStatus.cancelled => PracticeFinishReason.cancelled,
        PracticeSessionStatus.failed => PracticeFinishReason.failed,
        _ => PracticeFinishReason.failed,
      };
    }
    return reason;
  }

  PracticeAttemptResult? _buildFinalAttemptResult({
    required PracticeEventMatcher? matcher,
    required CompiledPracticeTarget? target,
    required ScoringProfile? scoringProfile,
  }) {
    if (matcher == null || target == null || scoringProfile == null) {
      return null;
    }
    final matches = matcher.results;
    final timing = _timingScorer.score(
      matches: matches,
      scoringProfile: scoringProfile,
    );
    final direction = _directionScorer.score(
      matches: matches,
      observationsByTargetIndex: _observationsByTargetIndex,
    );
    final chord = _chordScorer.score(
      matches: matches,
      observations: _chordObservations,
      chordStableDuration: observationConfig.chordStableDuration,
    );
    final aggregation = _aggregator.aggregate(
      matches: matches,
      scoringProfile: scoringProfile,
      timing: timing,
      direction: direction,
      chord: chord,
    );
    return PracticeAttemptResult(
      index: _state.attemptIndex,
      tempo: target.tempo,
      metrics: aggregation.metrics,
      verdicts: aggregation.verdicts,
      outcome: aggregation.outcome,
    );
  }

  List<String> _coachingSummary() {
    final live = _liveScore;
    if (live == null) return const [];
    final codes = <String>{};
    for (final verdict in live.verdicts) {
      final code = verdict.coachingCode;
      if (code != null) codes.add(code);
    }
    return codes.toList(growable: false);
  }

  void _pushExpectedChord(PracticeSessionState nextState) {
    final target = _currentTarget;
    if (target == null) return;
    final segments = target.expectedChordSegments;
    if (segments.isEmpty) {
      _setExpectedChord(null);
      return;
    }
    final active = nextState.activeElapsed;
    final hit = segments.firstWhere(
      (segment) => active >= segment.start && active < segment.end,
      orElse: () => ExpectedChordSegment(
        chord: segments.last.chord,
        start: segments.last.end,
        end: segments.last.end,
      ),
    );
    if (nextState.status == PracticeSessionStatus.completed ||
        nextState.status == PracticeSessionStatus.cancelled ||
        nextState.status == PracticeSessionStatus.failed) {
      _setExpectedChord(null);
    } else {
      _setExpectedChord(hit.chord);
    }
  }

  void _setExpectedChord(String? chord) {
    if (_lastExpectedChord == chord) return;
    _lastExpectedChord = chord;
    _observationGateway?.setExpectedChord(chord);
  }
}
