import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/platform/app_lifecycle.dart';
import '../../data/playback/backing_audio_player.dart';
import '../../domain/services/song_time_map.dart';
import 'song_transport_clock.dart';
import 'song_transport_command.dart';
import 'song_transport_state.dart';
import 'transport_effect.dart';

abstract final class SongTransportFailureCode {
  static const String disposed = 'songTransport.disposed';
  static const String invalidTransition = 'songTransport.invalidTransition';
  static const String invalidSeek = 'songTransport.invalidSeek';
}

final class SongTransportDispatchResult {
  const SongTransportDispatchResult({
    required this.phasePath,
    required this.effects,
  });

  final List<SongTransportPhase> phasePath;
  final List<TransportEffect> effects;
}

final class SongTransport {
  SongTransport({
    required this.player,
    required this.clock,
    this.lifecycleEvents,
    this.timeMap,
  }) {
    _playerSubscription = player.events.listen(_onPlayerEvent);
    lifecycleEvents?.addListener(_onLifecycleStateChanged);
  }

  final BackingAudioPlayer player;
  final SongTransportClock clock;
  final AppLifecycleEvents? lifecycleEvents;
  final SongTimeMap? timeMap;
  final StreamController<SongTransportState> _states =
      StreamController<SongTransportState>.broadcast();
  final StreamController<TransportEffect> _effects =
      StreamController<TransportEffect>.broadcast();
  late final StreamSubscription<BackingPlaybackEvent> _playerSubscription;
  SongTransportState _state = const SongTransportState();
  Duration _anchorPosition = Duration.zero;
  Duration _anchorElapsed = Duration.zero;
  Future<void> _commandTail = Future<void>.value();
  Future<void>? _disposeFuture;
  bool _disposed = false;

  SongTransportState get state => _withMusicalPosition(
    _state.phase == SongTransportPhase.playing
        ? _state.copyWith(activePosition: _activePositionNow())
        : _state,
  );
  Stream<SongTransportState> get states => _states.stream;
  Stream<TransportEffect> get effects => _effects.stream;

  /// The playback target follows the SDD's explicit grid-offset formula.
  Duration backingPositionFor(Duration musicalPosition) =>
      musicalPosition + _state.gridOffset;

  Future<SongTransportDispatchResult> dispatch(SongTransportCommand command) {
    final scheduled = _commandTail.then((_) => _dispatch(command));
    _commandTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  Future<void> handleInterruption(SongTransportInterruptionReason reason) {
    final scheduled = _commandTail.then((_) => _interrupt(reason));
    _commandTail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    lifecycleEvents?.removeListener(_onLifecycleStateChanged);
    clock.stop();
    await _playerSubscription.cancel();
    await player.dispose();
    await _states.close();
    await _effects.close();
  }

  Future<SongTransportDispatchResult> _dispatch(SongTransportCommand command) {
    if (_disposed) {
      return Future<SongTransportDispatchResult>.value(
        _failureResult(SongTransportFailureCode.disposed),
      );
    }
    return switch (command) {
      PrepareSongTransport() => _prepare(command),
      StartSongTransport() => _start(command),
      CompleteCountIn() => _completeCountIn(),
      PauseSongTransport() => _pause(),
      ResumeSongTransport() => _resume(),
      SeekSongTransport() => _seek(command),
      SetSongTransportSpeed() => _setSpeed(command),
      RestartSongTransport() => _restart(),
      FinishSongTransport() => _finish(),
      StopSongTransport() => _stop(),
    };
  }

  Future<SongTransportDispatchResult> _prepare(
    PrepareSongTransport command,
  ) async {
    if (_state.phase != SongTransportPhase.idle &&
        _state.phase != SongTransportPhase.error) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    final path = _newPath();
    final effects = <TransportEffect>[];
    _move(
      SongTransportPhase.preparing,
      path,
      backingStatus: BackingPlaybackStatus.preparing,
      gridOffset: command.gridOffset,
      clearFailure: true,
      clearInterruptionReason: true,
    );
    _recordEffect(PrepareBackingAudioEffect(command.asset), effects);
    final result = await player.prepare(command.asset);
    if (_disposed) {
      return SongTransportDispatchResult(phasePath: path, effects: effects);
    }
    if (result.isFailure) {
      _move(
        SongTransportPhase.error,
        path,
        backingStatus: BackingPlaybackStatus.error,
        lastFailureCode: result.failureOrNull!.code,
      );
      _recordEffect(
        TransportFailureEffect(result.failureOrNull!.code),
        effects,
      );
    } else {
      _anchorPosition = Duration.zero;
      _anchorElapsed = clock.elapsed;
      _move(
        SongTransportPhase.ready,
        path,
        activePosition: Duration.zero,
        backingStatus: BackingPlaybackStatus.ready,
      );
    }
    return SongTransportDispatchResult(phasePath: path, effects: effects);
  }

  Future<SongTransportDispatchResult> _start(StartSongTransport command) async {
    if (_state.phase != SongTransportPhase.ready) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    final path = _newPath();
    final effects = <TransportEffect>[];
    if (command.withCountIn) {
      _move(SongTransportPhase.countIn, path);
      return SongTransportDispatchResult(phasePath: path, effects: effects);
    }
    await _playFromCurrentPhase(path, effects);
    return SongTransportDispatchResult(phasePath: path, effects: effects);
  }

  Future<SongTransportDispatchResult> _completeCountIn() async {
    if (_state.phase != SongTransportPhase.countIn) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    final path = _newPath();
    final effects = <TransportEffect>[];
    await _playFromCurrentPhase(path, effects);
    return SongTransportDispatchResult(phasePath: path, effects: effects);
  }

  Future<void> _playFromCurrentPhase(
    List<SongTransportPhase> path,
    List<TransportEffect> emitted,
  ) async {
    _move(
      SongTransportPhase.playing,
      path,
      backingStatus: BackingPlaybackStatus.playing,
      clearInterruptionReason: true,
    );
    _recordEffect(const StartBackingAudioEffect(), emitted);
    final result = await player.play();
    if (_disposed) return;
    if (result.isFailure) {
      _moveToError(path, emitted, result.failureOrNull!.code);
      return;
    }
    if (_state.speed != 1) {
      _recordEffect(SetBackingRateEffect(_state.speed), emitted);
      final rateResult = await player.setRate(_state.speed);
      if (rateResult.isFailure) {
        _moveToError(path, emitted, rateResult.failureOrNull!.code);
        return;
      }
    }
    _anchorPosition = _state.activePosition;
    _anchorElapsed = clock.elapsed;
    clock.start();
  }

  Future<SongTransportDispatchResult> _pause() async {
    if (_state.phase == SongTransportPhase.countIn) {
      final path = _newPath();
      _move(SongTransportPhase.paused, path);
      return SongTransportDispatchResult(phasePath: path, effects: const []);
    }
    if (_state.phase != SongTransportPhase.playing) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    final path = _newPath();
    final emitted = <TransportEffect>[];
    final position = _activePositionNow();
    _recordEffect(const PauseBackingAudioEffect(), emitted);
    final result = await player.pause();
    if (_disposed) {
      return SongTransportDispatchResult(phasePath: path, effects: emitted);
    }
    if (result.isFailure) {
      _moveToError(path, emitted, result.failureOrNull!.code);
    } else {
      clock.stop();
      _anchorPosition = position;
      _anchorElapsed = clock.elapsed;
      _move(
        SongTransportPhase.paused,
        path,
        activePosition: position,
        backingStatus: BackingPlaybackStatus.paused,
      );
    }
    return SongTransportDispatchResult(phasePath: path, effects: emitted);
  }

  Future<SongTransportDispatchResult> _resume() async {
    if (_state.phase != SongTransportPhase.paused) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    final path = _newPath();
    final emitted = <TransportEffect>[];
    await _playFromCurrentPhase(path, emitted);
    return SongTransportDispatchResult(phasePath: path, effects: emitted);
  }

  Future<SongTransportDispatchResult> _seek(SeekSongTransport command) async {
    if (command.position.isNegative) {
      return _failureResult(SongTransportFailureCode.invalidSeek);
    }
    final wasPlaying = _state.phase == SongTransportPhase.playing;
    if (!wasPlaying && _state.phase != SongTransportPhase.paused) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    final path = _newPath();
    final emitted = <TransportEffect>[];
    _move(SongTransportPhase.seeking, path);
    if (wasPlaying) {
      _recordEffect(const PauseBackingAudioEffect(), emitted);
      final pauseResult = await player.pause();
      if (pauseResult.isFailure) {
        _moveToError(path, emitted, pauseResult.failureOrNull!.code);
        return SongTransportDispatchResult(phasePath: path, effects: emitted);
      }
      clock.stop();
    }
    final backingPosition = backingPositionFor(command.position);
    _recordEffect(SeekBackingAudioEffect(backingPosition), emitted);
    final seekResult = await player.seek(backingPosition);
    if (seekResult.isFailure) {
      _moveToError(path, emitted, seekResult.failureOrNull!.code);
      return SongTransportDispatchResult(phasePath: path, effects: emitted);
    }
    _anchorPosition = command.position;
    _anchorElapsed = clock.elapsed;
    _setState(_state.copyWith(activePosition: command.position));
    if (!wasPlaying) {
      _move(
        SongTransportPhase.paused,
        path,
        backingStatus: BackingPlaybackStatus.paused,
      );
      return SongTransportDispatchResult(phasePath: path, effects: emitted);
    }
    await _playFromCurrentPhase(path, emitted);
    return SongTransportDispatchResult(phasePath: path, effects: emitted);
  }

  Future<SongTransportDispatchResult> _setSpeed(
    SetSongTransportSpeed command,
  ) async {
    if (_state.phase != SongTransportPhase.ready &&
        _state.phase != SongTransportPhase.paused) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    final path = _newPath();
    final emitted = <TransportEffect>[];
    if (!player.capabilities.supportsRate(command.speed)) {
      _recordEffect(
        const TransportFailureEffect(
          BackingAudioPlayerFailureCode.unsupportedRate,
        ),
        emitted,
      );
      _setState(
        _state.copyWith(
          lastFailureCode: BackingAudioPlayerFailureCode.unsupportedRate,
        ),
      );
      return SongTransportDispatchResult(phasePath: path, effects: emitted);
    }
    if (_state.phase == SongTransportPhase.ready) {
      _setState(_state.copyWith(speed: command.speed, clearFailure: true));
      return SongTransportDispatchResult(phasePath: path, effects: emitted);
    }
    _recordEffect(SetBackingRateEffect(command.speed), emitted);
    final result = await player.setRate(command.speed);
    if (result.isFailure) {
      _recordEffect(
        TransportFailureEffect(result.failureOrNull!.code),
        emitted,
      );
      _setState(_state.copyWith(lastFailureCode: result.failureOrNull!.code));
    } else {
      _anchorPosition = _state.activePosition;
      _anchorElapsed = clock.elapsed;
      _setState(_state.copyWith(speed: command.speed, clearFailure: true));
    }
    return SongTransportDispatchResult(phasePath: path, effects: emitted);
  }

  Future<SongTransportDispatchResult> _restart() async {
    if (_state.phase != SongTransportPhase.completed) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    final path = _newPath();
    clock.reset();
    _anchorPosition = Duration.zero;
    _anchorElapsed = Duration.zero;
    _move(
      SongTransportPhase.ready,
      path,
      activePosition: Duration.zero,
      backingStatus: BackingPlaybackStatus.ready,
      clearFailure: true,
    );
    return SongTransportDispatchResult(phasePath: path, effects: const []);
  }

  Future<SongTransportDispatchResult> _finish() async {
    if (_state.phase != SongTransportPhase.playing) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    final path = _newPath();
    final emitted = <TransportEffect>[];
    final position = _activePositionNow();
    _recordEffect(const PauseBackingAudioEffect(), emitted);
    final result = await player.pause();
    if (result.isFailure) {
      _moveToError(path, emitted, result.failureOrNull!.code);
    } else {
      clock.stop();
      _anchorPosition = position;
      _anchorElapsed = clock.elapsed;
      _move(
        SongTransportPhase.completed,
        path,
        activePosition: position,
        backingStatus: BackingPlaybackStatus.paused,
      );
    }
    return SongTransportDispatchResult(phasePath: path, effects: emitted);
  }

  Future<SongTransportDispatchResult> _stop() async {
    final path = _newPath();
    final emitted = <TransportEffect>[];
    if (_state.phase == SongTransportPhase.idle ||
        _state.phase == SongTransportPhase.stopping) {
      return SongTransportDispatchResult(phasePath: path, effects: emitted);
    }
    if (_state.phase == SongTransportPhase.error) {
      await player.stop();
      clock.stop();
      _move(
        SongTransportPhase.idle,
        path,
        activePosition: Duration.zero,
        backingStatus: BackingPlaybackStatus.stopped,
      );
      return SongTransportDispatchResult(phasePath: path, effects: emitted);
    }
    if (!SongTransportTransitionTable.allows(
      from: _state.phase,
      to: SongTransportPhase.stopping,
    )) {
      return _failureResult(SongTransportFailureCode.invalidTransition);
    }
    _move(SongTransportPhase.stopping, path);
    _recordEffect(const PauseBackingAudioEffect(), emitted);
    final result = await player.stop();
    clock.stop();
    _anchorPosition = Duration.zero;
    _anchorElapsed = clock.elapsed;
    _move(
      SongTransportPhase.idle,
      path,
      activePosition: Duration.zero,
      backingStatus: BackingPlaybackStatus.stopped,
      lastFailureCode: result.failureOrNull?.code,
    );
    if (result.isFailure) {
      _recordEffect(
        TransportFailureEffect(result.failureOrNull!.code),
        emitted,
      );
    }
    return SongTransportDispatchResult(phasePath: path, effects: emitted);
  }

  Future<void> _interrupt(SongTransportInterruptionReason reason) async {
    if (_disposed ||
        (_state.phase != SongTransportPhase.playing &&
            _state.phase != SongTransportPhase.countIn)) {
      return;
    }
    if (_state.phase == SongTransportPhase.countIn) {
      _move(SongTransportPhase.paused, _newPath());
    } else {
      await _pause();
    }
    if (!_disposed) _setState(_state.copyWith(interruptionReason: reason));
  }

  void _onLifecycleStateChanged(AppLifecycleState lifecycleState) {
    if (isBackgroundLifecycleState(lifecycleState)) {
      unawaited(
        handleInterruption(SongTransportInterruptionReason.appBackground),
      );
    }
  }

  void _onPlayerEvent(BackingPlaybackEvent event) {
    if (_disposed) return;
    switch (event) {
      case BackingPositionEvent(:final position)
          when _state.phase == SongTransportPhase.playing:
        final masterPosition = backingPositionFor(_activePositionNow());
        final report = BackingDriftPolicy.fromCapabilities(
          player.capabilities,
        ).evaluate(masterPosition: masterPosition, samplePosition: position);
        _setState(
          _state.copyWith(
            activePosition: _activePositionNow(),
            lastDriftReport: report,
          ),
        );
        _emitEffect(BackingDriftEffect(report));
        if (report.action == BackingDriftAction.hardResync) {
          unawaited(_hardResync(masterPosition));
        }
      case BackingCompletedEvent()
          when _state.phase == SongTransportPhase.playing:
        final position = _activePositionNow();
        clock.stop();
        _anchorPosition = position;
        _anchorElapsed = clock.elapsed;
        _move(
          SongTransportPhase.completed,
          _newPath(),
          activePosition: position,
          backingStatus: BackingPlaybackStatus.paused,
        );
      case BackingPlaybackFailureEvent(:final code):
        _moveToError(_newPath(), <TransportEffect>[], code);
      default:
        break;
    }
  }

  Future<void> _hardResync(Duration targetPosition) async {
    if (_disposed || _state.phase != SongTransportPhase.playing) return;
    final result = await player.seek(targetPosition);
    if (result.isFailure && !_disposed) {
      _moveToError(_newPath(), <TransportEffect>[], result.failureOrNull!.code);
    }
  }

  Duration _activePositionNow() {
    if (_state.phase != SongTransportPhase.playing) {
      return _state.activePosition;
    }
    return _anchorPosition + (clock.elapsed - _anchorElapsed);
  }

  List<SongTransportPhase> _newPath() => <SongTransportPhase>[_state.phase];

  void _move(
    SongTransportPhase destination,
    List<SongTransportPhase> path, {
    Duration? activePosition,
    Duration? gridOffset,
    BackingPlaybackStatus? backingStatus,
    String? lastFailureCode,
    bool clearFailure = false,
    bool clearInterruptionReason = false,
  }) {
    if (!SongTransportTransitionTable.allows(
      from: _state.phase,
      to: destination,
    )) {
      throw StateError(
        'Invalid song transport transition: ${_state.phase} -> $destination',
      );
    }
    _setState(
      _state.copyWith(
        phase: destination,
        activePosition: activePosition,
        gridOffset: gridOffset,
        backingStatus: backingStatus,
        lastFailureCode: lastFailureCode,
        clearFailure: clearFailure,
        clearInterruptionReason: clearInterruptionReason,
      ),
    );
    path.add(destination);
  }

  void _moveToError(
    List<SongTransportPhase> path,
    List<TransportEffect> emitted,
    String code,
  ) {
    if (SongTransportTransitionTable.allows(
      from: _state.phase,
      to: SongTransportPhase.error,
    )) {
      _move(
        SongTransportPhase.error,
        path,
        backingStatus: BackingPlaybackStatus.error,
        lastFailureCode: code,
      );
    } else {
      _setState(_state.copyWith(lastFailureCode: code));
    }
    _recordEffect(TransportFailureEffect(code), emitted);
  }

  SongTransportDispatchResult _failureResult(String code) {
    _setState(_state.copyWith(lastFailureCode: code));
    final effect = TransportFailureEffect(code);
    _emitEffect(effect);
    return SongTransportDispatchResult(
      phasePath: <SongTransportPhase>[_state.phase],
      effects: <TransportEffect>[effect],
    );
  }

  void _recordEffect(TransportEffect effect, List<TransportEffect> emitted) {
    emitted.add(effect);
    _emitEffect(effect);
  }

  void _emitEffect(TransportEffect effect) {
    if (!_disposed && !_effects.isClosed) _effects.add(effect);
  }

  void _setState(SongTransportState value) {
    if (_disposed) return;
    _state = _withMusicalPosition(value);
    if (!_states.isClosed) _states.add(_state);
  }

  SongTransportState _withMusicalPosition(SongTransportState value) {
    final activeTimeMap = timeMap;
    if (activeTimeMap == null) return value;
    return value.copyWith(
      musicalPosition: activeTimeMap.positionAt(value.activePosition),
    );
  }
}
