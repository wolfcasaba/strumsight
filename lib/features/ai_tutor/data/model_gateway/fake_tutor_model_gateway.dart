import 'dart:async';

import 'package:meta/meta.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import 'tutor_model_event.dart';
import 'tutor_model_gateway.dart';
import 'tutor_model_request.dart';

/// A controllable clock for deterministic timeout testing.
final class FakeClock {
  FakeClock({DateTime? initialTime})
    : _now = initialTime ?? DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _now;
  final List<_ScheduledCallback> _scheduled = [];

  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
    _fireDueCallbacks();
  }

  Timer createTimer(DateTime deadline, void Function() callback) {
    final entry = _ScheduledCallback(deadline, callback);
    _scheduled.add(entry);
    return _FakeTimer(() => _scheduled.remove(entry));
  }

  void _fireDueCallbacks() {
    final due = _scheduled.where((e) => !e.deadline.isAfter(_now)).toList();
    for (final entry in due) {
      _scheduled.remove(entry);
      entry.callback();
    }
  }
}

class _ScheduledCallback {
  _ScheduledCallback(this.deadline, this.callback);
  final DateTime deadline;
  final void Function() callback;
}

class _FakeTimer implements Timer {
  _FakeTimer(this._onCancel);
  final void Function() _onCancel;
  bool _cancelled = false;

  @override
  void cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _onCancel();
    }
  }

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;
}

@immutable
sealed class FakeGatewayStep {
  const FakeGatewayStep();
}

final class FakeGatewayDelay extends FakeGatewayStep {
  const FakeGatewayDelay(this.duration);
  final Duration duration;
}

final class FakeGatewayDelta extends FakeGatewayStep {
  const FakeGatewayDelta(this.delta, {this.sequence = 0});
  final String delta;
  final int sequence;
}

final class FakeGatewayToolCall extends FakeGatewayStep {
  const FakeGatewayToolCall(
    this.toolCallId,
    this.name,
    this.arguments, {
    this.sequence = 0,
  });
  final String toolCallId;
  final String name;
  final String arguments;
  final int sequence;
}

final class FakeGatewayDone extends FakeGatewayStep {
  const FakeGatewayDone({this.sequence = 0});
  final int sequence;
}

final class FakeGatewayError extends FakeGatewayStep {
  const FakeGatewayError(this.code, this.message, {this.sequence = 0});
  final String code;
  final String message;
  final int sequence;
}

final class FakeTutorModelGateway implements TutorModelGateway {
  FakeTutorModelGateway({required this.script, FakeClock? clock})
    : clock = clock ?? FakeClock();

  final List<FakeGatewayStep> script;
  final FakeClock clock;

  StreamController<TutorModelEvent>? _controller;
  bool _isClosed = false;
  bool _terminalEmitted = false;

  bool get isRunning => _controller != null && !_isClosed;

  @override
  Future<AppResult<Stream<TutorModelEvent>>> start(
    TutorModelRequest request,
  ) async {
    if (_isClosed || isRunning) {
      return AppResult.failure(UnknownFailure(code: FailureCode.unknown));
    }

    _controller = StreamController<TutorModelEvent>(onCancel: _handleCancel);
    _terminalEmitted = false;
    _scheduleScript();
    return AppResult.success(_controller!.stream);
  }

  @override
  void cancel() {
    _controller?.close();
    _cleanup();
  }

  @override
  Future<AppResult<void>> health() async {
    if (_isClosed) {
      return AppResult.failure(UnknownFailure(code: FailureCode.unknown));
    }
    return const AppResult.success(null);
  }

  void _scheduleScript() {
    var elapsed = Duration.zero;
    for (final step in script) {
      switch (step) {
        case FakeGatewayDelay(:final duration):
          elapsed += duration;
        case FakeGatewayDelta(:final delta, :final sequence):
          _scheduleEvent(
            elapsed,
            TutorModelDelta(delta: delta, sequence: sequence),
          );
        case FakeGatewayToolCall(
          :final toolCallId,
          :final name,
          :final arguments,
          :final sequence,
        ):
          _scheduleEvent(
            elapsed,
            TutorModelToolCall(
              toolCallId: toolCallId,
              name: name,
              arguments: arguments,
              sequence: sequence,
            ),
          );
        case FakeGatewayDone(:final sequence):
          _scheduleEvent(elapsed, TutorModelDone(sequence: sequence));
        case FakeGatewayError(:final code, :final message, :final sequence):
          _scheduleEvent(
            elapsed,
            TutorModelError(code: code, message: message, sequence: sequence),
          );
      }
    }
  }

  void _scheduleEvent(Duration fireAt, TutorModelEvent event) {
    final deadline = clock.now().add(fireAt);
    clock.createTimer(deadline, () {
      if (_isClosed || _controller == null || _terminalEmitted) return;

      if (event is TutorModelDone || event is TutorModelError) {
        _terminalEmitted = true;
      }

      _controller!.add(event);

      if (_terminalEmitted) {
        _controller!.close();
        _cleanup();
      }
    });
  }

  Future<void> _handleCancel() async {
    _cleanup();
  }

  void _cleanup() {
    if (_isClosed) return;
    _isClosed = true;
    _controller = null;
  }
}
