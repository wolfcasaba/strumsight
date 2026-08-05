import 'dart:convert';

import 'package:meta/meta.dart';

import '../../../../core/foundation/app_result.dart';

/// Default upper bound for one tutor stream frame payload, in bytes.
///
/// Mirrors the backend `MAX_FRAME_BYTES` (ADR 0142 D8): the server never
/// emits a frame above it, and the client rejects larger frames as a
/// controlled transport failure.
const int defaultTutorFrameBytesLimit = 8192;

/// Stable machine-readable transport-failure codes (ADR 0142 D4/D6/D8).
///
/// Transport problems are controlled, signalled failures — a frame is never
/// silently skipped. The codes surface verbatim as `TutorModelError.code`
/// values on the normalized event stream.
abstract final class TutorTransportErrorCode {
  /// A frame arrived with a sequence number other than the expected next one
  /// (gap or out-of-order delivery).
  static const String sequenceGap = 'transport_sequence_gap';

  /// A frame payload is not valid JSON, not a JSON object, has an unknown
  /// type, or a required field is missing or has the wrong shape.
  static const String malformed = 'transport_malformed';

  /// A frame payload exceeds the parser's byte limit.
  static const String frameTooLarge = 'transport_frame_too_large';

  /// The frame stream ended before a terminal frame arrived.
  static const String truncated = 'transport_truncated';

  /// The underlying frame stream signalled an error.
  static const String streamError = 'transport_stream_error';
}

/// One well-formed frame of the tutor streaming protocol (ADR 0142).
///
/// Every frame type shares one monotonic, zero-based sequence.
@immutable
sealed class TutorStreamFrame {
  const TutorStreamFrame({required this.seq});

  /// Zero-based position of this frame within the stream.
  final int seq;
}

/// Control frame: the stream has started. Not surfaced as a model event.
@immutable
final class TutorStreamStarted extends TutorStreamFrame {
  const TutorStreamStarted({required super.seq});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TutorStreamStarted && other.seq == seq;

  @override
  int get hashCode => Object.hash(TutorStreamStarted, seq);
}

/// A text-chunk frame.
@immutable
final class TutorStreamDelta extends TutorStreamFrame {
  const TutorStreamDelta({required super.seq, required this.text});

  /// The incremental text fragment.
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorStreamDelta && other.seq == seq && other.text == text;

  @override
  int get hashCode => Object.hash(TutorStreamDelta, seq, text);
}

/// A tool-invocation request frame.
@immutable
final class TutorStreamToolCall extends TutorStreamFrame {
  const TutorStreamToolCall({
    required super.seq,
    required this.toolCallId,
    required this.name,
    required this.arguments,
  });

  /// Opaque identifier assigned by the model; correlates the result.
  final String toolCallId;

  /// The registered tool name.
  final String name;

  /// Raw JSON-encoded arguments; the consumer decodes them.
  final String arguments;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorStreamToolCall &&
          other.seq == seq &&
          other.toolCallId == toolCallId &&
          other.name == name &&
          other.arguments == arguments;

  @override
  int get hashCode =>
      Object.hash(TutorStreamToolCall, seq, toolCallId, name, arguments);
}

/// Control frame: token usage for the turn. Not surfaced as a model event.
@immutable
final class TutorStreamUsage extends TutorStreamFrame {
  const TutorStreamUsage({required super.seq, required this.tokens});

  /// Token count reported by the provider.
  final int tokens;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorStreamUsage && other.seq == seq && other.tokens == tokens;

  @override
  int get hashCode => Object.hash(TutorStreamUsage, seq, tokens);
}

/// Terminal frame: the turn completed successfully.
@immutable
final class TutorStreamComplete extends TutorStreamFrame {
  const TutorStreamComplete({required super.seq});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorStreamComplete && other.seq == seq;

  @override
  int get hashCode => Object.hash(TutorStreamComplete, seq);
}

/// Terminal frame: the turn failed on the server side.
@immutable
final class TutorStreamFailure extends TutorStreamFrame {
  const TutorStreamFailure({
    required super.seq,
    required this.code,
    required this.message,
  });

  /// Server-provided error code; surfaces verbatim as the model error code.
  final String code;

  /// Server-provided description; not for direct display.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorStreamFailure &&
          other.seq == seq &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(TutorStreamFailure, seq, code, message);
}

/// The outcome of parsing one frame payload.
@immutable
sealed class TutorFrameOutcome {
  const TutorFrameOutcome();
}

/// The frame was well-formed, correctly sequenced and accepted.
@immutable
final class TutorFrameAccepted extends TutorFrameOutcome {
  const TutorFrameAccepted(this.frame);

  /// The parsed frame.
  final TutorStreamFrame frame;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorFrameAccepted && other.frame == frame;

  @override
  int get hashCode => Object.hash(TutorFrameAccepted, frame);
}

/// The frame broke the protocol; the stream is unrecoverable.
@immutable
final class TutorFrameRejected extends TutorFrameOutcome {
  const TutorFrameRejected(this.code);

  /// One of the [TutorTransportErrorCode] values.
  final String code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorFrameRejected && other.code == code;

  @override
  int get hashCode => Object.hash(TutorFrameRejected, code);
}

/// The frame was ignored without breaking the stream: an idempotent duplicate
/// of the previous frame, or any frame after the stream already closed.
@immutable
final class TutorFrameDropped extends TutorFrameOutcome {
  const TutorFrameDropped();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TutorFrameDropped;

  @override
  int get hashCode => Object.hash(TutorFrameDropped, 0);
}

/// Validates and sequences tutor stream frames (ADR 0142).
///
/// The parser accepts frames whose `seq` equals [nextSequence] (starting at
/// zero) and advances. An exact duplicate of the previous frame is dropped
/// idempotently. Every other deviation — gap, out-of-order, malformed or
/// oversized payload — rejects the frame and closes the parser; frames
/// arriving after a terminal frame or a rejection are dropped.
final class TutorStreamFrameParser {
  TutorStreamFrameParser({this.maxFrameBytes = defaultTutorFrameBytesLimit});

  /// Maximum size of one frame payload in bytes.
  final int maxFrameBytes;

  int _nextSequence = 0;
  bool _closed = false;
  String? _lastAcceptedPayload;

  /// The sequence number the next accepted frame must carry.
  int get nextSequence => _nextSequence;

  /// Whether the parser stopped accepting frames — a terminal frame was seen
  /// or a frame was rejected.
  bool get isClosed => _closed;

  /// Parses one frame [payload]; never throws.
  TutorFrameOutcome parse(String payload) {
    if (_closed) {
      return const TutorFrameDropped();
    }
    if (utf8.encode(payload).length > maxFrameBytes) {
      return _reject(TutorTransportErrorCode.frameTooLarge);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return _reject(TutorTransportErrorCode.malformed);
    }
    if (decoded is! Map<String, Object?>) {
      return _reject(TutorTransportErrorCode.malformed);
    }
    final Object? type = decoded['type'];
    final Object? seq = decoded['seq'];
    if (type is! String || seq is! int || seq < 0) {
      return _reject(TutorTransportErrorCode.malformed);
    }
    if (seq != _nextSequence) {
      if (seq == _nextSequence - 1 && payload == _lastAcceptedPayload) {
        return const TutorFrameDropped();
      }
      return _reject(TutorTransportErrorCode.sequenceGap);
    }
    final TutorStreamFrame frame;
    switch (type) {
      case 'started':
        frame = TutorStreamStarted(seq: seq);
      case 'delta':
        final Object? text = decoded['text'];
        if (text is! String) {
          return _reject(TutorTransportErrorCode.malformed);
        }
        frame = TutorStreamDelta(seq: seq, text: text);
      case 'tool_call':
        final Object? toolCallId = decoded['tool_call_id'];
        final Object? name = decoded['name'];
        final Object? arguments = decoded['arguments'];
        if (toolCallId is! String || name is! String || arguments is! String) {
          return _reject(TutorTransportErrorCode.malformed);
        }
        frame = TutorStreamToolCall(
          seq: seq,
          toolCallId: toolCallId,
          name: name,
          arguments: arguments,
        );
      case 'usage':
        final Object? tokens = decoded['tokens'];
        if (tokens is! int) {
          return _reject(TutorTransportErrorCode.malformed);
        }
        frame = TutorStreamUsage(seq: seq, tokens: tokens);
      case 'complete':
        frame = TutorStreamComplete(seq: seq);
      case 'failure':
        final Object? code = decoded['code'];
        final Object? message = decoded['message'];
        if (code is! String || message is! String) {
          return _reject(TutorTransportErrorCode.malformed);
        }
        frame = TutorStreamFailure(seq: seq, code: code, message: message);
      default:
        return _reject(TutorTransportErrorCode.malformed);
    }
    _lastAcceptedPayload = payload;
    _nextSequence += 1;
    if (frame is TutorStreamComplete || frame is TutorStreamFailure) {
      _closed = true;
    }
    return TutorFrameAccepted(frame);
  }

  TutorFrameOutcome _reject(String code) {
    _closed = true;
    return TutorFrameRejected(code);
  }
}

/// Abstraction over the wire transport carrying one tutor turn's frame
/// payloads (ADR 0142).
///
/// The transport only opens the raw frame stream and reports its health;
/// protocol concerns (parsing, sequencing, normalization) belong to the
/// gateway.
abstract interface class TutorStreamTransport {
  /// Opens the frame stream for one turn.
  ///
  /// Returns the raw frame-payload stream on success, or a failure when the
  /// stream cannot be opened.
  Future<AppResult<Stream<String>>> openTurnStream({
    required String requestId,
    required int sequence,
    required String conversationId,
    required String message,
  });

  /// Aborts the currently open frame stream, if any.
  void cancelActiveStream();

  /// Checks whether the transport is operational.
  Future<AppResult<void>> health();
}
