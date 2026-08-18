/// Immutable state published while one practice plan is being generated.
library;

import '../../domain/model/practice_generation_request.dart';

/// The observable lifecycle of one generation request.
enum GenerationStatus { idle, running, completed, cancelled, failed }

/// A checkpoint within the cancellable generation pipeline.
enum GenerationStage { assembling, validating, repairing, activating }

/// UI-safe immutable generation state.
///
/// The controller is the only component that advances this state. A terminal
/// state can start a clean retry, while every other invalid transition fails
/// loudly instead of silently presenting an impossible progress state.
final class GenerationState {
  const GenerationState({required this.status, this.requestId, this.stage});

  const GenerationState._initial() : this(status: GenerationStatus.idle);

  final GenerationStatus status;
  final GenerationRequestId? requestId;
  final GenerationStage? stage;

  static const GenerationState initial = GenerationState._initial();

  GenerationState transitionTo(
    GenerationStatus next, {
    GenerationRequestId? requestId,
    GenerationStage? stage,
  }) {
    if (!_canTransitionTo(next)) {
      throw StateError('Cannot transition generation from $status to $next');
    }
    if (next == GenerationStatus.running && requestId == null) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'is required while generation is running',
      );
    }
    if (next != GenerationStatus.running && stage != null) {
      throw ArgumentError.value(
        stage,
        'stage',
        'is only valid while generation is running',
      );
    }
    return GenerationState(
      status: next,
      requestId: requestId ?? this.requestId,
      stage: next == GenerationStatus.running ? stage : null,
    );
  }

  bool _canTransitionTo(GenerationStatus next) => switch (status) {
    GenerationStatus.idle => next == GenerationStatus.running,
    GenerationStatus.running =>
      next == GenerationStatus.running ||
          next == GenerationStatus.completed ||
          next == GenerationStatus.cancelled ||
          next == GenerationStatus.failed,
    GenerationStatus.completed ||
    GenerationStatus.cancelled ||
    GenerationStatus.failed => next == GenerationStatus.running,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenerationState &&
          other.status == status &&
          other.requestId == requestId &&
          other.stage == stage;

  @override
  int get hashCode => Object.hash(status, requestId, stage);
}
