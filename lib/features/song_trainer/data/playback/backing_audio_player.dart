import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/models/song_asset_reference.dart';
import 'playback_capabilities.dart';

abstract final class BackingAudioPlayerFailureCode {
  static const String disposed = 'backingAudioPlayer.disposed';
  static const String missingAsset = 'backingAudioPlayer.missingAsset';
  static const String unsupportedFormat =
      'backingAudioPlayer.unsupportedFormat';
  static const String unsupportedRate = 'backingAudioPlayer.unsupportedRate';
  static const String unsupportedSeek = 'backingAudioPlayer.unsupportedSeek';
  static const String prepare = 'backingAudioPlayer.prepare';
  static const String playback = 'backingAudioPlayer.playback';
}

abstract interface class BackingAudioPlayer {
  Stream<BackingPlaybackEvent> get events;

  PlaybackCapabilities get capabilities;

  Future<AppResult<void>> prepare(SongAssetReference asset);

  Future<AppResult<void>> play();

  Future<AppResult<void>> pause();

  Future<AppResult<void>> seek(Duration position);

  Future<AppResult<void>> setRate(double rate);

  Future<AppResult<void>> setVolume(double volume);

  Future<AppResult<void>> stop();

  Future<void> dispose();
}

sealed class BackingPlaybackEvent {
  const BackingPlaybackEvent();
}

final class BackingPreparedEvent extends BackingPlaybackEvent {
  const BackingPreparedEvent();
}

final class BackingPositionEvent extends BackingPlaybackEvent {
  const BackingPositionEvent(this.position);

  final Duration position;

  @override
  bool operator ==(Object other) =>
      other is BackingPositionEvent && other.position == position;

  @override
  int get hashCode => position.hashCode;
}

final class BackingCompletedEvent extends BackingPlaybackEvent {
  const BackingCompletedEvent();
}

final class BackingPlaybackFailureEvent extends BackingPlaybackEvent {
  const BackingPlaybackFailureEvent(this.code);

  final String code;
}

enum BackingDriftAction { tolerate, resyncAtMeasureBoundary, hardResync }

final class BackingDriftReport {
  const BackingDriftReport({
    required this.masterPosition,
    required this.samplePosition,
    required this.absoluteDrift,
    required this.action,
  });

  final Duration masterPosition;
  final Duration samplePosition;
  final Duration absoluteDrift;
  final BackingDriftAction action;

  @override
  bool operator ==(Object other) =>
      other is BackingDriftReport &&
      other.masterPosition == masterPosition &&
      other.samplePosition == samplePosition &&
      other.absoluteDrift == absoluteDrift &&
      other.action == action;

  @override
  int get hashCode =>
      Object.hash(masterPosition, samplePosition, absoluteDrift, action);
}

/// Maps position-sample precision to a deterministic initial resync policy.
final class BackingDriftPolicy {
  const BackingDriftPolicy({required this.resyncThreshold});

  /// Three position-update intervals leave one full update interval on each
  /// side of the current sample before a boundary resync is considered.
  factory BackingDriftPolicy.fromCapabilities(
    PlaybackCapabilities capabilities,
  ) => BackingDriftPolicy(
    resyncThreshold: Duration(
      microseconds: capabilities.positionPrecision.inMicroseconds * 3,
    ),
  );

  final Duration resyncThreshold;

  BackingDriftReport evaluate({
    required Duration masterPosition,
    required Duration samplePosition,
  }) {
    final drift = Duration(
      microseconds:
          (samplePosition.inMicroseconds - masterPosition.inMicroseconds).abs(),
    );
    final action = switch (drift.compareTo(resyncThreshold)) {
      -1 => BackingDriftAction.tolerate,
      0 => BackingDriftAction.resyncAtMeasureBoundary,
      _ => BackingDriftAction.hardResync,
    };
    return BackingDriftReport(
      masterPosition: masterPosition,
      samplePosition: samplePosition,
      absoluteDrift: drift,
      action: action,
    );
  }
}

AppResult<T> backingAudioPlayerFailure<T>(
  String code, {
  bool retryable = false,
  Object? cause,
  StackTrace? stackTrace,
}) => AppResult<T>.failure(
  AudioFailure(
    code: code,
    retryable: retryable,
    cause: cause,
    stackTrace: stackTrace,
  ),
);
