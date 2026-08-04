import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as audioplayers;

import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_asset_reference.dart';
import 'backing_audio_player.dart';
import 'playback_capabilities.dart';

typedef BackingAssetReader =
    Future<AppResult<Uint8List?>> Function(String sha256);

abstract interface class LocalPlaybackHandle {
  Stream<Duration> get positions;
  Stream<void> get completions;

  Future<void> setBytes(Uint8List bytes, {String? mimeType});
  Future<void> resume();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}

final class AudioplayersLocalPlaybackHandle implements LocalPlaybackHandle {
  AudioplayersLocalPlaybackHandle() : _player = audioplayers.AudioPlayer();

  final audioplayers.AudioPlayer _player;

  @override
  Stream<void> get completions => _player.onPlayerComplete;

  @override
  Stream<Duration> get positions => _player.onPositionChanged;

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setBytes(Uint8List bytes, {String? mimeType}) =>
      _player.setSourceBytes(bytes, mimeType: mimeType);

  @override
  Future<void> setRate(double rate) => _player.setPlaybackRate(rate);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() => _player.stop();
}

final class LocalBackingAudioPlayer implements BackingAudioPlayer {
  LocalBackingAudioPlayer({
    required this.assetReader,
    LocalPlaybackHandle? handle,
    PlaybackCapabilities? capabilities,
  }) : _handle = handle ?? AudioplayersLocalPlaybackHandle(),
       _capabilities = capabilities ?? defaultLocalPlaybackCapabilities {
    _positionSubscription = _handle.positions.listen(_onPosition);
    _completionSubscription = _handle.completions.listen(_onCompleted);
  }

  static const PlaybackCapabilities defaultLocalPlaybackCapabilities =
      PlaybackCapabilities(
        canSeek: true,
        canChangeRate: true,
        preservesPitchWhenRateChanges: false,
        positionPrecision: Duration(milliseconds: 17),
        supportedFormats: <String>{'mp3', 'wav'},
        minimumRate: 0.5,
        maximumRate: 1.5,
      );

  final BackingAssetReader assetReader;
  final LocalPlaybackHandle _handle;
  final PlaybackCapabilities _capabilities;
  final StreamController<BackingPlaybackEvent> _events =
      StreamController<BackingPlaybackEvent>.broadcast();
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<void> _completionSubscription;
  bool _disposed = false;

  @override
  PlaybackCapabilities get capabilities => _capabilities;

  @override
  Stream<BackingPlaybackEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _positionSubscription.cancel();
    await _completionSubscription.cancel();
    await _handle.dispose();
    await _events.close();
  }

  @override
  Future<AppResult<void>> pause() => _run(_handle.pause);

  @override
  Future<AppResult<void>> play() => _run(_handle.resume);

  @override
  Future<AppResult<void>> prepare(SongAssetReference asset) async {
    if (_disposed) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.disposed,
      );
    }
    if (!_capabilities.supportsFormat(asset.extension)) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.unsupportedFormat,
      );
    }
    final result = await assetReader(asset.sha256);
    final error = result.failureOrNull;
    if (error != null) return AppResult<void>.failure(error);
    final bytes = result.valueOrNull;
    if (bytes == null) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.missingAsset,
      );
    }
    try {
      await _handle.setBytes(bytes, mimeType: asset.mimeType);
      if (!_disposed) _events.add(const BackingPreparedEvent());
      return const AppResult<void>.success(null);
    } on Object catch (error, stackTrace) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.prepare,
        retryable: true,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<AppResult<void>> seek(Duration position) {
    if (!_capabilities.canSeek) {
      return Future<AppResult<void>>.value(
        backingAudioPlayerFailure<void>(
          BackingAudioPlayerFailureCode.unsupportedSeek,
        ),
      );
    }
    return _run(() => _handle.seek(position));
  }

  @override
  Future<AppResult<void>> setRate(double rate) {
    if (!_capabilities.supportsRate(rate)) {
      return Future<AppResult<void>>.value(
        backingAudioPlayerFailure<void>(
          BackingAudioPlayerFailureCode.unsupportedRate,
        ),
      );
    }
    return _run(() => _handle.setRate(rate));
  }

  @override
  Future<AppResult<void>> setVolume(double volume) {
    if (!volume.isFinite || volume < 0 || volume > 1) {
      return Future<AppResult<void>>.value(
        backingAudioPlayerFailure<void>(BackingAudioPlayerFailureCode.playback),
      );
    }
    return _run(() => _handle.setVolume(volume));
  }

  @override
  Future<AppResult<void>> stop() => _run(_handle.stop);

  void _onCompleted(void _) {
    if (!_disposed) _events.add(const BackingCompletedEvent());
  }

  void _onPosition(Duration position) {
    if (!_disposed) _events.add(BackingPositionEvent(position));
  }

  Future<AppResult<void>> _run(Future<void> Function() operation) async {
    if (_disposed) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.disposed,
      );
    }
    try {
      await operation();
      return const AppResult<void>.success(null);
    } on Object catch (error, stackTrace) {
      return backingAudioPlayerFailure<void>(
        BackingAudioPlayerFailureCode.playback,
        retryable: true,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}
