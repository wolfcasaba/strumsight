import '../../data/playback/backing_audio_player.dart';
import '../../domain/models/tempo_map.dart';

enum SongTransportPhase {
  idle,
  preparing,
  ready,
  countIn,
  playing,
  paused,
  seeking,
  completed,
  stopping,
  error,
}

enum BackingPlaybackStatus {
  idle,
  preparing,
  ready,
  playing,
  paused,
  stopped,
  error,
}

enum SongTransportInterruptionReason {
  appBackground,
  audioRouteChanged,
  audioFocusLost,
}

abstract final class SongTransportTransitionTable {
  static bool allows({
    required SongTransportPhase from,
    required SongTransportPhase to,
  }) => switch (from) {
    SongTransportPhase.idle => to == SongTransportPhase.preparing,
    SongTransportPhase.preparing =>
      to == SongTransportPhase.ready || to == SongTransportPhase.error,
    SongTransportPhase.ready =>
      to == SongTransportPhase.countIn ||
          to == SongTransportPhase.playing ||
          to == SongTransportPhase.stopping,
    SongTransportPhase.countIn =>
      to == SongTransportPhase.playing ||
          to == SongTransportPhase.paused ||
          to == SongTransportPhase.stopping ||
          to == SongTransportPhase.error,
    SongTransportPhase.playing =>
      to == SongTransportPhase.paused ||
          to == SongTransportPhase.seeking ||
          to == SongTransportPhase.completed ||
          to == SongTransportPhase.stopping ||
          to == SongTransportPhase.error,
    SongTransportPhase.paused =>
      to == SongTransportPhase.playing ||
          to == SongTransportPhase.seeking ||
          to == SongTransportPhase.stopping,
    SongTransportPhase.seeking =>
      to == SongTransportPhase.playing ||
          to == SongTransportPhase.paused ||
          to == SongTransportPhase.error,
    SongTransportPhase.completed =>
      to == SongTransportPhase.ready || to == SongTransportPhase.stopping,
    SongTransportPhase.stopping => to == SongTransportPhase.idle,
    SongTransportPhase.error =>
      to == SongTransportPhase.preparing || to == SongTransportPhase.idle,
  };
}

final class SongTransportState {
  const SongTransportState({
    this.phase = SongTransportPhase.idle,
    this.activePosition = Duration.zero,
    this.gridOffset = Duration.zero,
    this.speed = 1,
    this.backingStatus = BackingPlaybackStatus.idle,
    this.lastFailureCode,
    this.interruptionReason,
    this.lastDriftReport,
    this.musicalPosition,
  });

  final SongTransportPhase phase;
  final Duration activePosition;
  final Duration gridOffset;
  final double speed;
  final BackingPlaybackStatus backingStatus;
  final String? lastFailureCode;
  final SongTransportInterruptionReason? interruptionReason;
  final BackingDriftReport? lastDriftReport;
  final BeatPosition? musicalPosition;

  SongTransportState copyWith({
    SongTransportPhase? phase,
    Duration? activePosition,
    Duration? gridOffset,
    double? speed,
    BackingPlaybackStatus? backingStatus,
    String? lastFailureCode,
    bool clearFailure = false,
    SongTransportInterruptionReason? interruptionReason,
    bool clearInterruptionReason = false,
    BackingDriftReport? lastDriftReport,
    BeatPosition? musicalPosition,
  }) => SongTransportState(
    phase: phase ?? this.phase,
    activePosition: activePosition ?? this.activePosition,
    gridOffset: gridOffset ?? this.gridOffset,
    speed: speed ?? this.speed,
    backingStatus: backingStatus ?? this.backingStatus,
    lastFailureCode: clearFailure
        ? null
        : (lastFailureCode ?? this.lastFailureCode),
    interruptionReason: clearInterruptionReason
        ? null
        : (interruptionReason ?? this.interruptionReason),
    lastDriftReport: lastDriftReport ?? this.lastDriftReport,
    musicalPosition: musicalPosition ?? this.musicalPosition,
  );

  @override
  bool operator ==(Object other) =>
      other is SongTransportState &&
      other.phase == phase &&
      other.activePosition == activePosition &&
      other.gridOffset == gridOffset &&
      other.speed == speed &&
      other.backingStatus == backingStatus &&
      other.lastFailureCode == lastFailureCode &&
      other.interruptionReason == interruptionReason &&
      other.lastDriftReport == lastDriftReport &&
      other.musicalPosition == musicalPosition;

  @override
  int get hashCode => Object.hash(
    phase,
    activePosition,
    gridOffset,
    speed,
    backingStatus,
    lastFailureCode,
    interruptionReason,
    lastDriftReport,
    musicalPosition,
  );
}
