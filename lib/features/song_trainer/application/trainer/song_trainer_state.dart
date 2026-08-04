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
  });

  const SongTrainerState.initial()
    : status = SongTrainerStatus.idle,
      attemptId = 0,
      transportState = const SongTransportState(),
      practiceState = null,
      result = null;

  final SongTrainerStatus status;
  final int attemptId;
  final SongTransportState transportState;
  final PracticeSessionState? practiceState;
  final SongTrainerResult? result;

  SongTrainerState copyWith({
    SongTrainerStatus? status,
    int? attemptId,
    SongTransportState? transportState,
    PracticeSessionState? practiceState,
    bool clearPracticeState = false,
    SongTrainerResult? result,
  }) => SongTrainerState(
    status: status ?? this.status,
    attemptId: attemptId ?? this.attemptId,
    transportState: transportState ?? this.transportState,
    practiceState: clearPracticeState
        ? null
        : (practiceState ?? this.practiceState),
    result: result ?? this.result,
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
