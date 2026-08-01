import 'package:meta/meta.dart';

import 'practice_attempt_result.dart';
import 'practice_value_equality.dart';
import 'speed_builder_policy.dart';
import 'tempo.dart';

enum AdaptiveSuggestionReason {
  insufficientSignal,
  lowCompletion,
  timingBias,
  directionError,
  chordError,
  tempoTooHigh,
  positiveReinforcement,
  nextDifficulty,
}

enum AdaptiveSuggestionKind {
  retry,
  reduceTempo,
  shorterLoop,
  enableMetronome,
  focusDirection,
  focusChordChanges,
  increaseTempo,
  nextDifficulty,
}

/// One deterministic, user-confirmable practice adaptation.
@immutable
final class AdaptiveSuggestion {
  const AdaptiveSuggestion({
    required this.reason,
    required this.kind,
    this.suggestedTempo,
  });

  final AdaptiveSuggestionReason reason;
  final AdaptiveSuggestionKind kind;
  final Tempo? suggestedTempo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdaptiveSuggestion &&
          other.reason == reason &&
          other.kind == kind &&
          other.suggestedTempo == suggestedTempo;

  @override
  int get hashCode => Object.hash(reason, kind, suggestedTempo);
}

enum SpeedBuilderStatus { active, completed, maxAttemptsReached, userFinished }

/// Immutable state of one Speed Builder session.
@immutable
final class SpeedBuilderState {
  SpeedBuilderState({
    required this.policy,
    required this.currentTempo,
    required this.successStreak,
    required this.failStreak,
    required List<PracticeAttemptResult> attempts,
    required this.highestStableTempo,
    required this.status,
  }) : attempts = List.unmodifiable(attempts);

  factory SpeedBuilderState.initial(SpeedBuilderPolicy policy) =>
      SpeedBuilderState(
        policy: policy,
        currentTempo: policy.startBpm,
        successStreak: 0,
        failStreak: 0,
        attempts: const [],
        highestStableTempo: null,
        status: SpeedBuilderStatus.active,
      );

  final SpeedBuilderPolicy policy;
  final Tempo currentTempo;
  final int successStreak;
  final int failStreak;
  final List<PracticeAttemptResult> attempts;
  final Tempo? highestStableTempo;
  final SpeedBuilderStatus status;

  bool get isClosed => status != SpeedBuilderStatus.active;

  SpeedBuilderState copyWith({
    Tempo? currentTempo,
    int? successStreak,
    int? failStreak,
    List<PracticeAttemptResult>? attempts,
    Tempo? highestStableTempo,
    bool clearHighestStableTempo = false,
    SpeedBuilderStatus? status,
  }) => SpeedBuilderState(
    policy: policy,
    currentTempo: currentTempo ?? this.currentTempo,
    successStreak: successStreak ?? this.successStreak,
    failStreak: failStreak ?? this.failStreak,
    attempts: attempts ?? this.attempts,
    highestStableTempo: clearHighestStableTempo
        ? null
        : highestStableTempo ?? this.highestStableTempo,
    status: status ?? this.status,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeedBuilderState &&
          other.policy == policy &&
          other.currentTempo == currentTempo &&
          other.successStreak == successStreak &&
          other.failStreak == failStreak &&
          listEquals(other.attempts, attempts) &&
          other.highestStableTempo == highestStableTempo &&
          other.status == status;

  @override
  int get hashCode => Object.hash(
    policy,
    currentTempo,
    successStreak,
    failStreak,
    listHash(attempts),
    highestStableTempo,
    status,
  );
}
