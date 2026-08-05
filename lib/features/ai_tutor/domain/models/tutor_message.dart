import 'tutor_content_block.dart';
import 'tutor_ids.dart';

/// Role of a user-visible tutor message.
enum TutorMessageRole { user, tutor, tool, systemNotice }

/// Delivery lifecycle of a tutor message.
enum TutorMessageDeliveryState {
  pending,
  streaming,
  complete,
  failed,
  cancelled,
}

/// Stable exception thrown when a [TutorMessage] is invalid.
class TutorMessageValidationException implements Exception {
  TutorMessageValidationException._(this.code);

  /// One of [TutorMessageValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'TutorMessageValidationException($code)';
}

/// Stable machine-readable codes emitted by message validation.
abstract final class TutorMessageValidationCode {
  static const String sequenceNegative = 'tutorMessage.sequence.negative';
}

/// Immutable, ordered, user-visible message in a tutor conversation.
final class TutorMessage {
  TutorMessage({
    required this.id,
    required this.role,
    required DateTime createdAt,
    required this.sequence,
    required this.deliveryState,
    required List<TutorContentBlock> blocks,
    this.replyTo,
  }) : createdAt = createdAt.toUtc(),
       blocks = List<TutorContentBlock>.unmodifiable(blocks) {
    if (sequence < 0) {
      throw TutorMessageValidationException._(
        TutorMessageValidationCode.sequenceNegative,
      );
    }
  }

  final TutorMessageId id;
  final TutorMessageRole role;
  final DateTime createdAt;
  final int sequence;
  final TutorMessageDeliveryState deliveryState;
  final List<TutorContentBlock> blocks;
  final TutorMessageId? replyTo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorMessage &&
          other.id == id &&
          other.role == role &&
          other.createdAt.microsecondsSinceEpoch ==
              createdAt.microsecondsSinceEpoch &&
          other.sequence == sequence &&
          other.deliveryState == deliveryState &&
          _listEquals(other.blocks, blocks) &&
          other.replyTo == replyTo;

  @override
  int get hashCode => Object.hash(
    id,
    role,
    createdAt.microsecondsSinceEpoch,
    sequence,
    deliveryState,
    Object.hashAll(blocks),
    replyTo,
  );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
