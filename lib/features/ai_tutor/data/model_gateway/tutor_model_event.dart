import 'package:meta/meta.dart';

/// A single event emitted by the tutor model streaming gateway.
///
/// The hierarchy is sealed so that every consumer can exhaustively pattern-match
/// on the event kind without a fallback branch.
@immutable
sealed class TutorModelEvent {
  const TutorModelEvent({required this.sequence});

  /// Zero-based position of this event within the originating request.
  ///
  /// Terminal events ([TutorModelDone], [TutorModelError]) carry the sequence
  /// of the last content event plus one, or zero when no content was produced.
  final int sequence;
}

/// A text-chunk fragment streamed from the model.
@immutable
final class TutorModelDelta extends TutorModelEvent {
  const TutorModelDelta({required super.sequence, required this.delta});

  /// The incremental text fragment. May be empty in edge cases (e.g. keep-alive
  /// pings from the transport); the consumer decides how to handle that.
  final String delta;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorModelDelta &&
          other.sequence == sequence &&
          other.delta == delta;

  @override
  int get hashCode => Object.hash(sequence, delta);

  @override
  String toString() => 'TutorModelDelta(sequence: $sequence, delta: "$delta")';
}

/// The model requests invocation of a registered tool.
@immutable
final class TutorModelToolCall extends TutorModelEvent {
  const TutorModelToolCall({
    required super.sequence,
    required this.toolCallId,
    required this.name,
    required this.arguments,
  });

  /// Opaque identifier assigned by the model; used to correlate the result.
  final String toolCallId;

  /// The registered tool name.
  final String name;

  /// Raw JSON-encoded arguments. The consumer is responsible for decoding.
  final String arguments;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorModelToolCall &&
          other.sequence == sequence &&
          other.toolCallId == toolCallId &&
          other.name == name &&
          other.arguments == arguments;

  @override
  int get hashCode => Object.hash(sequence, toolCallId, name, arguments);

  @override
  String toString() =>
      'TutorModelToolCall(sequence: $sequence, id: "$toolCallId", '
      'name: "$name")';
}

/// Terminal event signalling that the model completed the turn successfully.
///
/// Only the first terminal event in a stream is delivered; subsequent terminal
/// events (duplicate [TutorModelDone] or [TutorModelError]) are silently
/// dropped by the gateway.
@immutable
final class TutorModelDone extends TutorModelEvent {
  const TutorModelDone({required super.sequence});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorModelDone && other.sequence == sequence;

  @override
  int get hashCode => Object.hash(TutorModelDone, sequence);

  @override
  String toString() => 'TutorModelDone(sequence: $sequence)';
}

/// Terminal event signalling that the model stream ended with an error.
@immutable
final class TutorModelError extends TutorModelEvent {
  const TutorModelError({
    required super.sequence,
    required this.code,
    required this.message,
  });

  /// Stable machine-readable error code.
  final String code;

  /// Human-readable description. Not for display; the UI localises by [code].
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorModelError &&
          other.sequence == sequence &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(sequence, code, message);

  @override
  String toString() => 'TutorModelError(sequence: $sequence, code: "$code")';
}
