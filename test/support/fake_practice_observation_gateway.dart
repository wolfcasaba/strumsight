import 'dart:async';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/application/practice_observation_gateway.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';

/// A controllable gateway for Practice controller tests.
final class FakePracticeObservationGateway
    implements PracticeObservationGateway {
  FakePracticeObservationGateway({AppResult<void>? startResult})
    : startResult = startResult ?? const Success<void>(null);

  final StreamController<PracticeObservation> _controller =
      StreamController<PracticeObservation>.broadcast();

  AppResult<void> startResult;
  int startCalls = 0;
  int stopCalls = 0;
  final List<PracticeObservationConfig> startConfigs = [];
  final List<String?> expectedChordCalls = [];

  bool _running = false;
  bool _disposed = false;

  @override
  Stream<PracticeObservation> get observations => _controller.stream;

  @override
  Future<AppResult<void>> start({
    required PracticeObservationConfig config,
  }) async {
    if (_disposed) {
      return const Failure(
        AudioFailure(code: FailureCode.practiceObservationGatewayDisposed),
      );
    }
    if (_running) return const Success(null);
    startCalls++;
    startConfigs.add(config);
    final result = startResult;
    if (result case Success<void>()) _running = true;
    return result;
  }

  @override
  void setExpectedChord(String? chord) {
    if (!_disposed) expectedChordCalls.add(chord);
  }

  @override
  Future<AppResult<void>> stop() async {
    if (_disposed) {
      return const Failure(
        AudioFailure(code: FailureCode.practiceObservationGatewayDisposed),
      );
    }
    if (!_running) return const Success(null);
    _running = false;
    stopCalls++;
    return const Success(null);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _running = false;
    await _controller.close();
  }

  void emit(PracticeObservation observation) {
    if (!_disposed) _controller.add(observation);
  }

  void emitError(Object error, [StackTrace? stackTrace]) {
    if (!_disposed) _controller.addError(error, stackTrace);
  }
}
