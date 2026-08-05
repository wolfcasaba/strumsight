import 'dart:async';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../dto/tutor_stream_dto.dart';
import 'tutor_model_event.dart';
import 'tutor_model_gateway.dart';
import 'tutor_model_request.dart';

/// Failure code when [RemoteTutorModelGateway.start] is called while a
/// session is already running.
const String _gatewayBusyCode = 'tutor.model_gateway.busy';

/// Tutor model gateway that streams over a [TutorStreamTransport] and
/// normalizes protocol frames onto the [TutorModelEvent] hierarchy
/// (ADR 0142).
///
/// Control frames (`started`, `usage`) are consumed but never surfaced.
/// Sequence gaps, malformed or oversized frames, raw stream errors and
/// truncated streams become terminal [TutorModelError] events with a
/// `transport_*` code — never silent drops.
final class RemoteTutorModelGateway implements TutorModelGateway {
  RemoteTutorModelGateway({
    required this.transport,
    this.maxFrameBytes = defaultTutorFrameBytesLimit,
  });

  /// The frame-stream source this gateway opens turns on.
  final TutorStreamTransport transport;

  /// Upper bound for one frame payload, in bytes.
  final int maxFrameBytes;

  StreamController<TutorModelEvent>? _events;
  StreamSubscription<String>? _frames;

  /// Whether a streaming session is currently active.
  bool get isRunning => _events != null;

  @override
  Future<AppResult<Stream<TutorModelEvent>>> start(
    TutorModelRequest request,
  ) async {
    if (isRunning) {
      return const AppResult.failure(UnknownFailure(code: _gatewayBusyCode));
    }
    final opened = await transport.openTurnStream(
      requestId: request.requestId.value,
      sequence: request.sequence,
      conversationId: request.conversationId.value,
      message: request.message,
    );
    return switch (opened) {
      Failure<Stream<String>>(:final error) => AppResult.failure(error),
      Success<Stream<String>>(:final value) => _beginStreaming(value),
    };
  }

  @override
  void cancel() {
    if (!isRunning) {
      return;
    }
    transport.cancelActiveStream();
    _finish();
  }

  @override
  Future<AppResult<void>> health() => transport.health();

  AppResult<Stream<TutorModelEvent>> _beginStreaming(Stream<String> frames) {
    final parser = TutorStreamFrameParser(maxFrameBytes: maxFrameBytes);
    final controller = StreamController<TutorModelEvent>();
    _events = controller;
    _frames = frames.listen(
      (payload) => _handlePayload(parser, controller, payload),
      onError: (Object error) {
        _emitTerminal(
          controller,
          TutorModelError(
            sequence: parser.nextSequence,
            code: TutorTransportErrorCode.streamError,
            message: 'The tutor stream failed.',
          ),
        );
      },
      onDone: () {
        if (parser.isClosed) {
          _finish();
          return;
        }
        _emitTerminal(
          controller,
          TutorModelError(
            sequence: parser.nextSequence,
            code: TutorTransportErrorCode.truncated,
            message: 'The tutor stream ended without a terminal frame.',
          ),
        );
      },
      cancelOnError: true,
    );
    return AppResult.success(controller.stream);
  }

  void _handlePayload(
    TutorStreamFrameParser parser,
    StreamController<TutorModelEvent> controller,
    String payload,
  ) {
    switch (parser.parse(payload)) {
      case TutorFrameAccepted(:final frame):
        final event = _eventFor(frame);
        if (event == null) {
          return;
        }
        if (frame is TutorStreamComplete || frame is TutorStreamFailure) {
          _emitTerminal(controller, event);
        } else {
          controller.add(event);
        }
      case TutorFrameRejected(:final code):
        _emitTerminal(
          controller,
          TutorModelError(
            sequence: parser.nextSequence,
            code: code,
            message: 'The tutor stream sent an invalid frame.',
          ),
        );
      case TutorFrameDropped():
      // Idempotent duplicate or post-terminal frame — nothing to surface.
    }
  }

  TutorModelEvent? _eventFor(TutorStreamFrame frame) => switch (frame) {
    TutorStreamStarted() || TutorStreamUsage() => null,
    TutorStreamDelta(:final text) => TutorModelDelta(
      sequence: frame.seq,
      delta: text,
    ),
    TutorStreamToolCall(:final toolCallId, :final name, :final arguments) =>
      TutorModelToolCall(
        sequence: frame.seq,
        toolCallId: toolCallId,
        name: name,
        arguments: arguments,
      ),
    TutorStreamComplete() => TutorModelDone(sequence: frame.seq),
    TutorStreamFailure(:final code, :final message) => TutorModelError(
      sequence: frame.seq,
      code: code,
      message: message,
    ),
  };

  void _emitTerminal(
    StreamController<TutorModelEvent> controller,
    TutorModelEvent event,
  ) {
    controller.add(event);
    _finish();
  }

  void _finish() {
    final controller = _events;
    if (controller == null) {
      return;
    }
    _events = null;
    final subscription = _frames;
    _frames = null;
    subscription?.cancel();
    controller.close();
  }
}
