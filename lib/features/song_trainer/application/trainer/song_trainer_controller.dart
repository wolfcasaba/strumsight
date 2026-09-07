// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:strumsight/core/audio/pitch/pitch_observation.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation_config.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation_gateway.dart';
import 'package:strumsight/features/practice/public.dart';

import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_capability.dart';
import '../../domain/models/song_event.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/note_scoring_models.dart';
import '../../domain/models/trainer_range.dart';
import '../../domain/services/monophonic_note_scorer.dart';
import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../data/playback/backing_audio_player.dart';
import '../progress/song_measure_progress_committer.dart';
import 'song_progress_committer.dart';
import 'song_resume_repository.dart';
import 'song_practice_compiler.dart';
import 'song_result_mapper.dart';
import 'song_trainer_state.dart';
import 'song_transport.dart';
import 'song_transport_command.dart';
import 'song_transport_state.dart';
import 'transport_effect.dart';

/// Stable failure codes returned by [SongTrainerController.setPlaybackRate].
abstract final class SongTrainerRateFailureCode {
  /// The controller has already been disposed.
  static const String disposed = 'songTrainer.rate.disposed';

  /// The scored session is not at a boundary where the judged timeline can
  /// be re-timed. The Practice engine accepts `RescheduleTempo` from `ready`
  /// and `paused` only, and this controller pauses a `countIn` / `running`
  /// session on the caller's behalf — every other status (preparing,
  /// permissionRequired, finishing, completed, cancelled, failed) is out of
  /// reach and says so instead of pretending the change landed.
  static const String notRescalable = 'songTrainer.rate.notRescalable';

  /// The requested rate maps to a Practice tempo outside the domain range
  /// (`Tempo.minimumBpm` … `Tempo.maximumBpm`) for this song's tempo.
  static const String tempoOutOfRange = 'songTrainer.rate.tempoOutOfRange';
}

/// Practice statuses at which a scored session's timeline can be re-timed.
///
/// `countIn` and `running` are in the set because [SongTrainerController]
/// pauses first: the pause is what fixes the bar boundary the rescale is
/// anchored to, and the session re-enters through its usual one-bar resume
/// count-in — already at the new tempo.
const Set<PracticeSessionStatus> _rescalableStatuses = <PracticeSessionStatus>{
  PracticeSessionStatus.ready,
  PracticeSessionStatus.countIn,
  PracticeSessionStatus.running,
  PracticeSessionStatus.paused,
};

/// Coordinates SongTransport with the public Practice session runtime.
///
/// The controller deliberately receives an already-created Practice session
/// controller. It never imports a Practice data gateway, a strum engine, or an
/// audio-session coordinator: the public Practice controller owns those
/// details for scored sessions, while playback-only sessions carry no Practice
/// controller at all.
final class SongTrainerController {
  SongTrainerController({
    required this.transport,
    required this.compilation,
    this.backingAsset,
    PracticeSessionController? practiceSession,
    MonophonicPitchSession? pitchSession,
    SongProgressCommitter? progressCommitter,
    SongMeasureProgressCommitter? measureProgressCommitter,
    SongResumeRepository? resumeRepository,
    int maxLoops = 1,
    double? targetSpeed,
  }) : _practiceSession = practiceSession,
       _pitchSession = pitchSession,
       _progressCommitter = progressCommitter,
       _measureProgressCommitter = measureProgressCommitter,
       _resumeRepository = resumeRepository,
       _maxLoops = maxLoops < 1 ? 1 : maxLoops,
       _targetSpeed = targetSpeed {
    if (compilation.isPlaybackOnly != (practiceSession == null)) {
      throw ArgumentError(
        'Scored compilations require a Practice session; playback-only ones do not.',
      );
    }
    if (practiceSession != null && pitchSession?.isScoringEnabled == true) {
      throw ArgumentError(
        'Pitch scoring cannot share a controller with a Practice mic session.',
      );
    }
    _transportSubscription = transport.states.listen(_onTransportState);
    _transportEffectsSubscription = transport.effects.listen(
      (effect) => _emitEffect(SongTrainerTransportEffect(effect)),
    );
    final practice = _practiceSession;
    if (practice != null) {
      _practiceSubscription = practice.states.listen(_onPracticeState);
      _practiceEffectsSubscription = practice.effects.listen(
        (effect) => _emitEffect(SongTrainerPracticeEffect(effect)),
      );
      _state = _state.copyWith(
        practiceState: practice.state,
        status: _statusForPractice(practice.state.status),
      );
    }
    _refreshBackingRateSupport();
    // A scored session's compiled target already runs at `targetSpeed` —
    // `SongPracticeCompiler` scales the authored tempo by it — so the speed
    // control has to OPEN where the session actually is. A playback-only
    // transport starts at 1x, and the state says exactly that.
    final speed = _targetSpeed ?? 1.0;
    _state = _state.copyWith(
      maxLoops: _maxLoops,
      playbackRate: compilation.isPlaybackOnly ? 1.0 : speed,
    );
  }

  final SongTransport transport;
  final SongPracticeCompilation compilation;
  final SongAssetReference? backingAsset;
  final PracticeSessionController? _practiceSession;
  final MonophonicPitchSession? _pitchSession;
  final SongProgressCommitter? _progressCommitter;
  final SongMeasureProgressCommitter? _measureProgressCommitter;
  final SongResumeRepository? _resumeRepository;
  final int _maxLoops;
  final double? _targetSpeed;
  final StreamController<SongTrainerState> _states =
      StreamController<SongTrainerState>.broadcast();
  final StreamController<SongTrainerEffect> _effects =
      StreamController<SongTrainerEffect>.broadcast();
  final StreamController<NoteScoringUpdate> _noteUpdates =
      StreamController<NoteScoringUpdate>.broadcast();
  final StreamController<NoteScoringResult> _noteResults =
      StreamController<NoteScoringResult>.broadcast();
  late final StreamSubscription<SongTransportState> _transportSubscription;
  late final StreamSubscription _transportEffectsSubscription;
  StreamSubscription<PracticeSessionState>? _practiceSubscription;
  StreamSubscription<PracticeSessionEffect>? _practiceEffectsSubscription;
  StreamSubscription<PitchObservation>? _pitchSubscription;
  MonophonicNoteScorer? _pitchScorer;
  bool _pitchRunning = false;

  SongTrainerState _state = const SongTrainerState.initial();
  int _operationId = 0;
  int _attemptId = 0;
  int _loopIndex = 1;
  int? _finalizedOperationId;
  bool _backingPrepared = false;
  bool _disposed = false;
  bool _applyingRate = false;
  double? _queuedRate;

  Stream<SongTrainerState> get states => _states.stream;
  Stream<SongTrainerEffect> get effects => _effects.stream;
  Stream<NoteScoringUpdate> get noteUpdates => _noteUpdates.stream;
  Stream<NoteScoringResult> get noteResults => _noteResults.stream;
  SongTrainerState get state => _state;
  bool get isPlaybackOnly => compilation.isPlaybackOnly;
  int get maxLoops => _maxLoops;

  /// Whether a live speed change can actually take effect.
  ///
  /// Playback-only: a backing track must actually be prepared — there is
  /// nothing to re-rate otherwise — and the player must advertise rate
  /// support.
  ///
  /// Scored: the Practice session must sit at a status whose judged timeline
  /// can be re-timed ([_rescalableStatuses]); and when a backing track IS
  /// prepared the player must be able to follow, because a session that
  /// re-times its targets while the audio keeps the old rate is exactly the
  /// desync this control must never produce.
  ///
  /// The presentation layer reads this to decide whether the speed slider is
  /// a real control or an honestly disabled one.
  bool get canChangeBackingRate {
    if (_disposed) return false;
    final practice = _practiceSession;
    if (practice == null) {
      return _backingPrepared && transport.player.capabilities.canChangeRate;
    }
    if (_backingPrepared && !transport.player.capabilities.canChangeRate) {
      return false;
    }
    return compilation.definition != null &&
        _rescalableStatuses.contains(practice.state.status);
  }

  /// Applies [rate] to the session and mirrors it into the state.
  ///
  /// Returns a failure rather than throwing or silently ignoring the request:
  /// an unsupported rate, a session that is not at a boundary, and a
  /// transport-level refusal are all things the coach surface has to be able
  /// to say out loud.
  ///
  /// A slider drag fires one call per notch, so the calls are serialised
  /// here: while one is in flight the newest requested rate is queued and
  /// applied by that run when it finishes. Two pause/resume brackets
  /// interleaving over one session is how the audio and the judged timeline
  /// would end up on different tempi — the exact desync this operation
  /// exists to prevent.
  Future<AppResult<void>> setPlaybackRate(double rate) async {
    if (_disposed) {
      return const Failure<void>(
        AudioFailure(code: SongTrainerRateFailureCode.disposed),
      );
    }
    if (!transport.player.capabilities.supportsRate(rate)) {
      return const Failure<void>(
        AudioFailure(code: BackingAudioPlayerFailureCode.unsupportedRate),
      );
    }
    if (rate == _state.playbackRate) return const Success<void>(null);
    if (_applyingRate) {
      _queuedRate = rate;
      return const Success<void>(null);
    }
    _applyingRate = true;
    try {
      var requested = rate;
      while (true) {
        final applied = await _applyRate(requested);
        final queued = _queuedRate;
        _queuedRate = null;
        if (applied.isFailure || queued == null || queued == requested) {
          return applied;
        }
        requested = queued;
      }
    } finally {
      _applyingRate = false;
      _queuedRate = null;
    }
  }

  Future<AppResult<void>> _applyRate(double rate) {
    final practice = _practiceSession;
    if (practice != null) return _setScoredRate(practice, rate);
    return _setBackingRate(rate);
  }

  /// Playback-only: the audio transport is the only timeline in the session.
  Future<AppResult<void>> _setBackingRate(double rate) async {
    // `SongTransport` accepts `SetSongTransportSpeed` only while `ready` or
    // `paused` (its own transition table). Bracketing the change with a
    // pause/resume keeps the audio clock's anchor honest: the transport
    // re-anchors `activePosition` on a successful rate change.
    final wasPlaying = transport.state.phase == SongTransportPhase.playing;
    if (wasPlaying) await transport.dispatch(const PauseSongTransport());
    final applied = await transport.dispatch(SetSongTransportSpeed(rate));
    if (wasPlaying) await transport.dispatch(const ResumeSongTransport());
    final failed = _transportFailureIn(applied);
    if (failed != null) return Failure<void>(AudioFailure(code: failed));
    if (_disposed) {
      return const Failure<void>(
        AudioFailure(code: SongTrainerRateFailureCode.disposed),
      );
    }
    _emit(_state.copyWith(playbackRate: rate));
    return const Success<void>(null);
  }

  /// Scored: the judged timeline moves WITH the audio, at a safe boundary.
  ///
  /// The Practice target is compiled once, at the setup speed, and the
  /// engine only re-times it while no attempt is in flight. So the change
  /// runs as one bracket — pause → re-time the target → re-rate the audio →
  /// resume — which is also the musically honest thing to do, since a tempo
  /// cannot change mid-bar. Everything already played keeps its placement
  /// (and with it every verdict already earned); only what is still to come
  /// moves, and the one-bar resume count-in already ticks at the new tempo.
  Future<AppResult<void>> _setScoredRate(
    PracticeSessionController practice,
    double rate,
  ) async {
    final tempo = _scoredTempoFor(rate);
    if (tempo == null) {
      return const Failure<void>(
        AudioFailure(code: SongTrainerRateFailureCode.tempoOutOfRange),
      );
    }
    final status = practice.state.status;
    if (!_rescalableStatuses.contains(status)) {
      return const Failure<void>(
        AudioFailure(code: SongTrainerRateFailureCode.notRescalable),
      );
    }
    final wasRunning =
        status == PracticeSessionStatus.countIn ||
        status == PracticeSessionStatus.running;
    if (wasRunning) await pause();
    if (_disposed) {
      return const Failure<void>(
        AudioFailure(code: SongTrainerRateFailureCode.disposed),
      );
    }
    await practice.dispatch(RescheduleTempo(tempo));
    if (practice.state.target?.tempo != tempo) {
      // The reducer refused (and logged) the input: put the session back
      // where the caller had it instead of leaving it half-applied.
      if (wasRunning) await resume();
      return const Failure<void>(
        AudioFailure(code: SongTrainerRateFailureCode.notRescalable),
      );
    }
    // The transport only accepts a speed while `ready` or `paused`; a
    // session with no backing track has no transport timeline to move.
    final phase = transport.state.phase;
    if (phase == SongTransportPhase.ready ||
        phase == SongTransportPhase.paused) {
      final applied = await transport.dispatch(SetSongTransportSpeed(rate));
      final failed = _transportFailureIn(applied);
      if (failed != null) return Failure<void>(AudioFailure(code: failed));
    }
    if (_disposed) {
      return const Failure<void>(
        AudioFailure(code: SongTrainerRateFailureCode.disposed),
      );
    }
    _emit(
      _state.copyWith(
        playbackRate: rate,
        practiceState: practice.state,
        status: _statusForPractice(practice.state.status),
      ),
    );
    if (wasRunning) await resume();
    return const Success<void>(null);
  }

  /// The Practice tempo a scored session runs at for [rate], or null when
  /// the song's authored tempo cannot carry it.
  Tempo? _scoredTempoFor(double rate) {
    final definition = compilation.definition;
    if (definition == null) return null;
    final tempo = Tempo(definition.defaultTempo.bpm * rate);
    return tempo.validate().isEmpty ? tempo : null;
  }

  String? _transportFailureIn(SongTransportDispatchResult result) {
    for (final effect in result.effects) {
      if (effect is TransportFailureEffect) return effect.code;
    }
    return null;
  }

  /// Prepares the optional backing transport and the scored Practice session.
  Future<void> prepare({SongAssetReference? backingAsset}) async {
    if (_disposed) return;
    final operation = ++_operationId;
    _finalizedOperationId = null;
    _backingPrepared = false;
    _emit(_state.copyWith(status: SongTrainerStatus.preparing));
    final selectedBackingAsset = backingAsset ?? this.backingAsset;
    if (selectedBackingAsset != null) {
      await transport.dispatch(
        PrepareSongTransport(asset: selectedBackingAsset),
      );
      if (!_isCurrent(operation)) return;
      _backingPrepared = transport.state.phase == SongTransportPhase.ready;
    }
    await _restoreCheckpoint();
    if (!_isCurrent(operation)) return;
    final practice = _practiceSession;
    if (practice == null) {
      await _startPitchScoring();
      _emit(_state.copyWith(status: SongTrainerStatus.ready));
      return;
    }
    await practice.dispatch(
      PreparePractice(
        definition: compilation.definition!,
        config: compilation.practiceConfig!,
      ),
    );
    if (_isCurrent(operation)) _syncPracticeState();
  }

  /// Starts the scored count-in, or playback directly for a transport-only
  /// session. Backing stays stopped until the scored Practice state is running.
  Future<void> start() async {
    if (_disposed) return;
    final practice = _practiceSession;
    if (practice == null) {
      await _startPlaybackOnly();
      return;
    }
    await practice.dispatch(const StartPractice());
    _syncPracticeState();
  }

  /// Pauses both timelines. The Practice pause cause is user initiated.
  Future<void> pause() => _pause(PauseCause.user);

  /// Resumes a scored Practice session through its one-bar resume count-in.
  Future<void> resume() async {
    if (_disposed) return;
    final practice = _practiceSession;
    if (practice == null) {
      await _startPitchScoring();
      if (transport.state.phase == SongTransportPhase.paused) {
        await transport.dispatch(const ResumeSongTransport());
      }
      _emit(_state.copyWith(status: SongTrainerStatus.running));
      return;
    }
    await practice.dispatch(const ResumePractice());
    _syncPracticeState();
  }

  /// Seeks transport first while paused, then starts a new scored attempt.
  ///
  /// Incrementing both operation and attempt identifiers before asynchronous
  /// transport work makes late callbacks from the abandoned timeline inert.
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    final operation = ++_operationId;
    _attemptId++;
    final practice = _practiceSession;
    if (practice != null &&
        (practice.state.status == PracticeSessionStatus.countIn ||
            practice.state.status == PracticeSessionStatus.running)) {
      await practice.dispatch(const PausePractice(cause: PauseCause.user));
    }
    if (transport.state.phase == SongTransportPhase.playing) {
      await transport.dispatch(const PauseSongTransport());
    }
    if (transport.state.phase == SongTransportPhase.paused) {
      await transport.dispatch(SeekSongTransport(position));
    }
    if (!_isCurrent(operation)) return;
    if (practice == null) {
      await _stopPitchScoring();
      _emit(
        _state.copyWith(
          status: SongTrainerStatus.paused,
          attemptId: _attemptId,
        ),
      );
      return;
    }
    await practice.dispatch(const RestartAttempt());
    if (_isCurrent(operation)) _syncPracticeState();
  }

  /// Handles a background interruption without inventing a new Practice mode.
  Future<void> handleAppBackground() => _pause(PauseCause.interruption);

  /// Requests a finish. The Practice terminal tick produces the result.
  Future<void> finish() async {
    if (_disposed) return;
    final practice = _practiceSession;
    if (practice == null) {
      await _stopPitchScoring(emitResult: true);
      if (transport.state.phase == SongTransportPhase.playing) {
        await transport.dispatch(const FinishSongTransport());
      }
      _emit(_state.copyWith(status: SongTrainerStatus.completed));
      return;
    }
    await practice.dispatch(const FinishPractice());
    _syncPracticeState();
  }

  /// Re-enters a paused session using a checkpoint previously saved by the
  /// resume repository. The attempt counter is rolled forward to the value
  /// recorded by the checkpoint (subsequent `seek` calls continue to bump it).
  void hydrateAttempt(SongResumeCheckpoint checkpoint) {
    if (_disposed) return;
    _attemptId = checkpoint.attemptCounter;
    _loopIndex = checkpoint.attemptCounter.clamp(1, _maxLoops);
    _emit(_state.copyWith(attemptId: _attemptId, loopIndex: _loopIndex));
  }

  /// Re-applies a saved checkpoint on re-entry. The returned future resolves
  /// once the relevant state has been rehydrated.
  Future<void> reenter({required SongId songId, required int revision}) async {
    final repo = _resumeRepository;
    if (repo == null) return;
    final loaded = await repo.load(songId: songId, revision: revision);
    if (loaded.isFailure || _disposed) return;
    hydrateAttempt(loaded.valueOrNull!);
  }

  /// Persists the current attempt counter + resume position to the resume
  /// repository. Failures are swallowed at the boundary — the caller already
  /// has a dedicated commit / progress path for the scorer.
  Future<void> persistResume({
    required SongId songId,
    required int revision,
    required MeasureRange range,
    required Duration resumedFrom,
  }) async {
    final repo = _resumeRepository;
    if (repo == null || _disposed) return;
    await repo.save(
      SongResumeCheckpoint(
        songId: songId,
        songRevision: revision,
        range: range,
        attemptCounter: _attemptId,
        resumedFrom: resumedFrom,
        recordedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _practiceSubscription?.cancel();
    await _practiceEffectsSubscription?.cancel();
    await _stopPitchScoring(emitResult: true);
    await _transportSubscription.cancel();
    await _transportEffectsSubscription.cancel();
    await _practiceSession?.dispose();
    await _progressCommitter?.dispose();
    await _states.close();
    await _effects.close();
    await _noteUpdates.close();
    await _noteResults.close();
  }

  Future<void> _pause(PauseCause cause) async {
    if (_disposed) return;
    ++_operationId;
    await _stopPitchScoring();
    final practice = _practiceSession;
    if (practice != null &&
        (practice.state.status == PracticeSessionStatus.countIn ||
            practice.state.status == PracticeSessionStatus.running)) {
      await practice.dispatch(PausePractice(cause: cause));
    }
    if (transport.state.phase == SongTransportPhase.playing) {
      await transport.dispatch(const PauseSongTransport());
    } else if (transport.state.phase == SongTransportPhase.countIn) {
      await transport.dispatch(const PauseSongTransport());
    }
    if (practice == null) {
      _emit(_state.copyWith(status: SongTrainerStatus.paused));
    } else {
      _syncPracticeState();
    }
    // The checkpoint is written on EVERY pause (user or interruption) — a
    // resume point that only exists in memory is the bug the persisted
    // repository was added for (audit §5.2).
    await _persistResumeCheckpoint();
  }

  /// Rolls the attempt counter forward from a checkpoint left behind by an
  /// earlier run of the same song revision, when one is stored.
  Future<void> _restoreCheckpoint() async {
    final reference = compilation.eventReferences.values.firstOrNull;
    if (_resumeRepository == null || reference == null) return;
    await reenter(songId: reference.songId, revision: reference.songRevision);
  }

  /// Writes the current attempt / position as a resume checkpoint, when the
  /// compiled session carries song coordinates to key it by.
  Future<void> _persistResumeCheckpoint() async {
    final reference = compilation.eventReferences.values.firstOrNull;
    final range = _sessionRange();
    if (_resumeRepository == null || reference == null || range == null) {
      return;
    }
    await persistResume(
      songId: reference.songId,
      revision: reference.songRevision,
      range: range,
      resumedFrom: transport.state.activePosition,
    );
  }

  /// The measure interval the compiled session actually covers, derived from
  /// the compiler's own event references — the controller never re-reads the
  /// document.
  MeasureRange? _sessionRange() {
    var start = -1;
    var endExclusive = -1;
    for (final reference in compilation.eventReferences.values) {
      final index = reference.measureIndex;
      if (start < 0 || index < start) start = index;
      if (index + 1 > endExclusive) endExclusive = index + 1;
    }
    if (start < 0) return null;
    return MeasureRange(start: start, endExclusive: endExclusive);
  }

  Future<void> _startPlaybackOnly() async {
    if (_backingPrepared && transport.state.phase == SongTransportPhase.ready) {
      await transport.dispatch(const StartSongTransport());
    }
    _emit(_state.copyWith(status: SongTrainerStatus.running));
  }

  void _onPracticeState(PracticeSessionState next) {
    if (_disposed) return;
    _emit(
      _state.copyWith(
        status: _statusForPractice(next.status),
        practiceState: next,
        attemptId: _attemptId,
      ),
    );
    if (next.status == PracticeSessionStatus.running) {
      final operation = _operationId;
      final attempt = _attemptId;
      unawaited(_startBackingForAttempt(operation, attempt));
    }
    if (next.status == PracticeSessionStatus.completed) {
      final operation = _operationId;
      unawaited(_finishAndFinalize(operation));
    }
  }

  void _onTransportState(SongTransportState next) {
    if (_disposed) return;
    _emit(_state.copyWith(transportState: next));
  }

  Future<void> _startBackingForAttempt(int operation, int attempt) async {
    if (!_isCurrent(operation) || attempt != _attemptId || !_backingPrepared) {
      return;
    }
    if (transport.state.phase == SongTransportPhase.ready) {
      await transport.dispatch(const StartSongTransport());
    } else if (transport.state.phase == SongTransportPhase.paused) {
      await transport.dispatch(const ResumeSongTransport());
    }
  }

  Future<void> _finishAndFinalize(int operation) async {
    if (!_isCurrent(operation) || _finalizedOperationId == operation) return;
    if (_practiceSession?.state.status != PracticeSessionStatus.completed) {
      return;
    }
    if (transport.state.phase == SongTransportPhase.playing) {
      await transport.dispatch(const FinishSongTransport());
    }
    for (var index = 0; index < 3; index++) {
      await Future<void>.delayed(Duration.zero);
      final result = _practiceSession?.result;
      if (result == null) continue;
      if (!_isCurrent(operation) || _finalizedOperationId == operation) return;
      final mapped = SongResultMapper.map(
        sessionResult: result,
        references: compilation.eventReferences,
      );
      _finalizedOperationId = operation;
      final idempotencyKey = _progressIdempotencyKey(result);
      await _progressCommitter?.commit(
        idempotencyKey: idempotencyKey,
        sessionResult: result,
      );
      // Per-measure progress is what the heatmap and the "Song progress"
      // card read back; without this commit `SongProgressRepository` stayed
      // empty for every session (audit §5.2).
      await _measureProgressCommitter?.commit(
        attemptKey: idempotencyKey,
        result: mapped,
        activeDuration: result.activeDuration,
      );
      _emit(
        _state.copyWith(status: SongTrainerStatus.completed, result: mapped),
      );
      _emitEffect(NavigateToSongTrainerResult(mapped));
      if (_loopIndex < _maxLoops) {
        _loopIndex++;
        _attemptId++;
        _emit(_state.copyWith(loopIndex: _loopIndex, attemptId: _attemptId));
      }
      return;
    }
  }

  String _progressIdempotencyKey(PracticeSessionResult sessionResult) {
    final practiceId = sessionResult.id;
    final progressAttempt = _attemptId;
    return 'song|${compilation.eventReferences.values.firstOrNull?.songId.value ?? 'unknown'}'
        '|attempt|$progressAttempt'
        '|practice|$practiceId';
  }

  void _refreshBackingRateSupport() {
    final speed = _targetSpeed ?? 1.0;
    final capabilities = transport.player.capabilities;
    final supported =
        capabilities.canChangeRate && capabilities.supportsRate(speed);
    _state = _state.copyWith(backingRateSupported: supported);
  }

  void _syncPracticeState() {
    final practice = _practiceSession;
    if (practice == null || _disposed) return;
    _emit(
      _state.copyWith(
        status: _statusForPractice(practice.state.status),
        practiceState: practice.state,
        attemptId: _attemptId,
      ),
    );
  }

  Future<void> _startPitchScoring() async {
    final pitchSession = _pitchSession;
    if (_disposed ||
        _pitchRunning ||
        pitchSession == null ||
        !pitchSession.isScoringEnabled) {
      return;
    }
    _pitchScorer = pitchSession.createScorer();
    _pitchSubscription = pitchSession.gateway.observations.listen(
      _onPitchObservation,
      onError: _onPitchObservationError,
      cancelOnError: false,
    );
    final started = await pitchSession.gateway.start(pitchSession.config);
    if (started.isSuccess) {
      _pitchRunning = true;
      return;
    }
    await _pitchSubscription?.cancel();
    _pitchSubscription = null;
    _pitchScorer = null;
  }

  Future<void> _stopPitchScoring({bool emitResult = false}) async {
    final scorer = _pitchScorer;
    if (emitResult && scorer != null && !_noteResults.isClosed) {
      _noteResults.add(scorer.finalize());
    }
    _pitchScorer = null;
    await _pitchSubscription?.cancel();
    _pitchSubscription = null;
    if (!_pitchRunning) return;
    _pitchRunning = false;
    await _pitchSession?.gateway.stop();
  }

  void _onPitchObservation(PitchObservation observation) {
    final scorer = _pitchScorer;
    if (_disposed || scorer == null || _noteUpdates.isClosed) return;
    _noteUpdates.add(scorer.observe(observation));
  }

  void _onPitchObservationError(Object error, StackTrace stackTrace) {
    unawaited(_stopPitchScoring(emitResult: true));
  }

  bool _isCurrent(int operation) => !_disposed && operation == _operationId;

  void _emit(SongTrainerState next) {
    if (_disposed) return;
    _state = next;
    _states.add(next);
  }

  void _emitEffect(SongTrainerEffect effect) {
    if (!_disposed) _effects.add(effect);
  }

  static SongTrainerStatus _statusForPractice(PracticeSessionStatus status) =>
      switch (status) {
        PracticeSessionStatus.idle => SongTrainerStatus.idle,
        PracticeSessionStatus.preparing => SongTrainerStatus.preparing,
        PracticeSessionStatus.permissionRequired =>
          SongTrainerStatus.permissionRequired,
        PracticeSessionStatus.ready => SongTrainerStatus.ready,
        PracticeSessionStatus.countIn => SongTrainerStatus.countIn,
        PracticeSessionStatus.running => SongTrainerStatus.running,
        PracticeSessionStatus.paused => SongTrainerStatus.paused,
        PracticeSessionStatus.finishing => SongTrainerStatus.running,
        PracticeSessionStatus.completed => SongTrainerStatus.completed,
        PracticeSessionStatus.cancelled => SongTrainerStatus.cancelled,
        PracticeSessionStatus.failed => SongTrainerStatus.failed,
      };
}

/// A caller-assembled pitch session for an already selected note range.
final class MonophonicPitchSession {
  MonophonicPitchSession({
    required this.gateway,
    required this.config,
    required this.capability,
    required this.startedAt,
    required List<NoteScoringTarget> targets,
  }) : targets = List<NoteScoringTarget>.unmodifiable(targets);

  factory MonophonicPitchSession.fromSongNotes({
    required PitchObservationGateway gateway,
    required DateTime startedAt,
    required SongPitchCapability capability,
    required int capo,
    required List<SongNoteEvent> notes,
    PitchObservationConfig config = const PitchObservationConfig(),
    Duration rangeStart = Duration.zero,
  }) {
    if (capo < 0 || capo > 15) {
      throw ArgumentError.value(capo, 'capo');
    }
    final targets =
        <NoteScoringTarget>[
          for (final note in notes)
            NoteScoringTarget(
              id: note.id.value,
              midiPitch: note.midiPitch + capo,
              start: note.start - rangeStart,
              duration: note.duration,
            ),
        ]..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
    if (targets.any((target) => target.start.isNegative)) {
      throw ArgumentError.value(rangeStart, 'rangeStart');
    }
    return MonophonicPitchSession(
      gateway: gateway,
      config: config,
      capability: capability,
      startedAt: startedAt,
      targets: targets,
    );
  }

  final PitchObservationGateway gateway;
  final PitchObservationConfig config;
  final SongPitchCapability capability;
  final DateTime startedAt;
  final List<NoteScoringTarget> targets;

  bool get isScoringEnabled =>
      capability.scoring && capability.isMonophonic && targets.isNotEmpty;

  MonophonicNoteScorer createScorer() =>
      MonophonicNoteScorer(startedAt: startedAt, targets: targets);
}
