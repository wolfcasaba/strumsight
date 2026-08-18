/// Application-facing state controller for cancellable plan generation.
library;

import 'dart:async';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../model/generation_state.dart';
import '../service/generation_orchestrator.dart';
import '../../domain/model/adaptive_practice_plan.dart';

/// Bridges [GenerationOrchestrator] progress to immutable UI-facing state.
///
/// This controller has no Flutter dependency. Presentation can subscribe to
/// [states] or read [state], while a later Riverpod provider owns its lifecycle.
final class PlanGeneratorController {
  PlanGeneratorController({required this.orchestrator}) {
    _progressSubscription = orchestrator.progress.listen(_onProgress);
  }

  final GenerationOrchestrator orchestrator;
  final StreamController<GenerationState> _statesController =
      StreamController<GenerationState>.broadcast(sync: true);
  late final StreamSubscription<GenerationProgress> _progressSubscription;

  GenerationState _state = GenerationState.initial;
  bool _disposed = false;

  GenerationState get state => _state;
  Stream<GenerationState> get states => _statesController.stream;

  /// Starts (or joins) a generation request without blocking its caller.
  Future<AppResult<AdaptivePracticePlan>> generate(
    GenerationPlanInput input,
  ) async {
    if (_disposed) {
      return const Failure<AdaptivePracticePlan>(
        CancelledFailure(cause: 'plan generator controller disposed'),
      );
    }
    if (_state.status != GenerationStatus.running ||
        _state.requestId != input.request.id) {
      _publish(
        _state.transitionTo(
          GenerationStatus.running,
          requestId: input.request.id,
        ),
      );
    }
    final result = await orchestrator.generate(input);
    if (_disposed || _state.requestId != input.request.id) return result;
    final terminal = switch (result) {
      Success<AdaptivePracticePlan>() => GenerationStatus.completed,
      Failure<AdaptivePracticePlan>(:final error)
          when error is CancelledFailure =>
        GenerationStatus.cancelled,
      Failure<AdaptivePracticePlan>() => GenerationStatus.failed,
    };
    _publish(_state.transitionTo(terminal));
    return result;
  }

  void cancel() {
    final requestId = _state.requestId;
    if (_state.status == GenerationStatus.running && requestId != null) {
      orchestrator.cancel(requestId);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _progressSubscription.cancel();
    await _statesController.close();
  }

  void _onProgress(GenerationProgress progress) {
    if (_disposed || _state.requestId != progress.requestId) return;
    _publish(
      _state.transitionTo(
        GenerationStatus.running,
        requestId: progress.requestId,
        stage: progress.stage,
      ),
    );
  }

  void _publish(GenerationState next) {
    _state = next;
    _statesController.add(next);
  }
}
