import 'dart:async';

import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_asset_reference.dart';
import 'backing_audio_player.dart';
import 'playback_capabilities.dart';

abstract final class FakeBackingAudioPlayerFailureCode {
  static const String prepare = 'fakeBackingAudioPlayer.prepare';
}

final class FakeBackingAudioPlayer implements BackingAudioPlayer {
  FakeBackingAudioPlayer({PlaybackCapabilities? capabilities})
    : _capabilities =
          capabilities ??
          const PlaybackCapabilities(
            canSeek: true,
            canChangeRate: true,
            preservesPitchWhenRateChanges: false,
            positionPrecision: Duration(milliseconds: 17),
            supportedFormats: <String>{'mp3', 'wav'},
            minimumRate: 0.5,
            maximumRate: 1.5,
          );

  final PlaybackCapabilities _capabilities;
  final StreamController<BackingPlaybackEvent> _events =
      StreamController<BackingPlaybackEvent>.broadcast();
  bool _disposed = false;
  bool _failPrepare = false;
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  int get microphoneLeaseRequests => 0;
  Duration? lastSeekPosition;
  double? lastRate;
  double? lastVolume;

  @override
  PlaybackCapabilities get capabilities => _capabilities;

  @override
  Stream<BackingPlaybackEvent> get events => _events.stream;

  void failNextPrepare() => _failPrepare = true;

  void emitPosition(Duration position) {
    if (!_events.isClosed) _events.add(BackingPositionEvent(position));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    disposeCalls++;
    await _events.close();
  }

  @override
  Future<AppResult<void>> pause() async {
    if (_disposed) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.disposed,
      );
    }
    pauseCalls++;
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> play() async {
    if (_disposed) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.disposed,
      );
    }
    playCalls++;
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> prepare(SongAssetReference asset) async {
    if (_disposed) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.disposed,
      );
    }
    if (_failPrepare) {
      _failPrepare = false;
      return backingAudioPlayerFailure<void>(
        FakeBackingAudioPlayerFailureCode.prepare,
      );
    }
    if (!_capabilities.supportsFormat(asset.extension)) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.unsupportedFormat,
      );
    }
    _events.add(const BackingPreparedEvent());
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> seek(Duration position) async {
    if (_disposed) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.disposed,
      );
    }
    if (!_capabilities.canSeek) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.unsupportedSeek,
      );
    }
    lastSeekPosition = position;
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> setRate(double rate) async {
    if (!_capabilities.supportsRate(rate)) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.unsupportedRate,
      );
    }
    lastRate = rate;
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> setVolume(double volume) async {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.playback,
      );
    }
    lastVolume = volume;
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> stop() async {
    if (_disposed) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.disposed,
      );
    }
    stopCalls++;
    return const AppResult<void>.success(null);
  }
}
