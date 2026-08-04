import 'dart:async';

import 'package:strumsight/features/practice/public.dart';

import '../../domain/models/song_asset_reference.dart';
import 'song_practice_compiler.dart';
import 'song_result_mapper.dart';
import 'song_trainer_state.dart';
import 'song_transport.dart';
import 'song_transport_command.dart';
import 'song_transport_state.dart';

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
  }) : _practiceSession = practiceSession {
    if (compilation.isPlaybackOnly != (practiceSession == null)) {
      throw ArgumentError(
        'Scored compilations require a Practice session; playback-only ones do not.',
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
  }

  final SongTransport transport;
  final SongPracticeCompilation compilation;
  final SongAssetReference? backingAsset;
  final PracticeSessionController? _practiceSession;
  final StreamController<SongTrainerState> _states =
      StreamController<SongTrainerState>.broadcast();
  final StreamController<SongTrainerEffect> _effects =
      StreamController<SongTrainerEffect>.broadcast();
  late final StreamSubscription<SongTransportState> _transportSubscription;
  late final StreamSubscription _transportEffectsSubscription;
  StreamSubscription<PracticeSessionState>? _practiceSubscription;
  StreamSubscription<PracticeSessionEffect>? _practiceEffectsSubscription;

  SongTrainerState _state = const SongTrainerState.initial();
  int _operationId = 0;
  int _attemptId = 0;
  int? _finalizedOperationId;
  bool _backingPrepared = false;
  bool _disposed = false;

  Stream<SongTrainerState> get states => _states.stream;
  Stream<SongTrainerEffect> get effects => _effects.stream;
  SongTrainerState get state => _state;
  bool get isPlaybackOnly => compilation.isPlaybackOnly;

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
    final practice = _practiceSession;
    if (practice == null) {
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
      if (transport.state.phase == SongTransportPhase.playing) {
        await transport.dispatch(const FinishSongTransport());
      }
      _emit(_state.copyWith(status: SongTrainerStatus.completed));
      return;
    }
    await practice.dispatch(const FinishPractice());
    _syncPracticeState();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _practiceSubscription?.cancel();
    await _practiceEffectsSubscription?.cancel();
    await _transportSubscription.cancel();
    await _transportEffectsSubscription.cancel();
    await _practiceSession?.dispose();
    await _states.close();
    await _effects.close();
  }

  Future<void> _pause(PauseCause cause) async {
    if (_disposed) return;
    ++_operationId;
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
      _emit(
        _state.copyWith(status: SongTrainerStatus.completed, result: mapped),
      );
      _emitEffect(NavigateToSongTrainerResult(mapped));
      return;
    }
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
