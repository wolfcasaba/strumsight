import 'package:strumsight/features/practice/public.dart';

import 'song_trainer_result.dart';
import 'song_transport_state.dart';
import 'transport_effect.dart';

/// Lifecycle of one Song Trainer application session.
enum SongTrainerStatus {
  idle,
  preparing,
  permissionRequired,
  ready,
  countIn,
  running,
  paused,
  completed,
  cancelled,
  failed,
}

/// Immutable application state derived from the two owned controllers.
final class SongTrainerState {
  const SongTrainerState({
    required this.status,
    required this.attemptId,
    required this.transportState,
    this.practiceState,
    this.result,
    this.loopIndex = 1,
    this.maxLoops = 1,
    this.backingRateSupported = false,
    this.speedBuilderState,
  });

  const SongTrainerState.initial()
    : status = SongTrainerStatus.idle,
      attemptId = 0,
      transportState = const SongTransportState(),
      practiceState = null,
      result = null,
      loopIndex = 1,
      maxLoops = 1,
      backingRateSupported = false,
      speedBuilderState = null;

  final SongTrainerStatus status;
  final int attemptId;
  final SongTransportState transportState;
  final PracticeSessionState? practiceState;
  final SongTrainerResult? result;

  /// 1-based loop index of the currently-running attempt. `2/5` means the
  /// second iteration of five.
  final int loopIndex;

  /// Total loop count requested for the session (1 == single pass).
  final int maxLoops;

  /// Whether the backing playback advertises a [PlaybackCapabilities.supportsRate]
  /// covering the current speed. When false, the speed control is rendered
  /// as disabled with a reason.
  final bool backingRateSupported;

  /// Optional Speed Builder state mirror. `null` when the session does not
  /// use Speed Builder.
  final SpeedBuilderState? speedBuilderState;

  SongTrainerState copyWith({
    SongTrainerStatus? status,
    int? attemptId,
    SongTransportState? transportState,
    PracticeSessionState? practiceState,
    bool clearPracticeState = false,
    SongTrainerResult? result,
    bool clearResult = false,
    int? loopIndex,
    int? maxLoops,
    bool? backingRateSupported,
    SpeedBuilderState? speedBuilderState,
    bool clearSpeedBuilderState = false,
  }) => SongTrainerState(
    status: status ?? this.status,
    attemptId: attemptId ?? this.attemptId,
    transportState: transportState ?? this.transportState,
    practiceState: clearPracticeState
        ? null
        : (practiceState ?? this.practiceState),
    result: clearResult ? null : (result ?? this.result),
    loopIndex: loopIndex ?? this.loopIndex,
    maxLoops: maxLoops ?? this.maxLoops,
    backingRateSupported: backingRateSupported ?? this.backingRateSupported,
    speedBuilderState: clearSpeedBuilderState
        ? null
        : (speedBuilderState ?? this.speedBuilderState),
  );
}

/// One-shot output from Song Trainer orchestration.
sealed class SongTrainerEffect {
  const SongTrainerEffect();
}

/// The final scored session has been mapped onto song coordinates.
final class NavigateToSongTrainerResult extends SongTrainerEffect {
  const NavigateToSongTrainerResult(this.result);

  final SongTrainerResult result;
}

/// A Practice-owned effect forwarded through the Song Trainer boundary.
final class SongTrainerPracticeEffect extends SongTrainerEffect {
  const SongTrainerPracticeEffect(this.effect);

  final PracticeSessionEffect effect;
}

/// A transport-owned effect forwarded through the Song Trainer boundary.
final class SongTrainerTransportEffect extends SongTrainerEffect {
  const SongTrainerTransportEffect(this.effect);

  final TransportEffect effect;
}
