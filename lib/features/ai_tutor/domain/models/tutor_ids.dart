/// Stable exception thrown when a typed tutor identifier is invalid.
class TutorIdValidationException implements Exception {
  TutorIdValidationException._(this.code);

  /// One of [TutorIdValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'TutorIdValidationException($code)';
}

/// Stable machine-readable codes emitted by tutor ID validation.
abstract final class TutorIdValidationCode {
  static const String empty = 'tutorId.empty';
  static const String tooLong = 'tutorId.tooLong';
}

/// The inclusive length limit shared by all typed tutor identifiers.
const int maxTutorIdLength = 128;

/// Shared immutable value contract for typed tutor identifiers.
sealed class TutorTypedId {
  TutorTypedId(String raw) : value = TutorIdValidator.normalize(raw);

  /// The trimmed identifier value.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorTypedId &&
          other.runtimeType == runtimeType &&
          other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$runtimeType($value)';
}

/// Identifies one tutor conversation.
final class TutorConversationId extends TutorTypedId {
  TutorConversationId(super.value);
}

/// Identifies one message within a tutor conversation.
final class TutorMessageId extends TutorTypedId {
  TutorMessageId(super.value);
}

/// Identifies one tutor turn.
final class TutorTurnId extends TutorTypedId {
  TutorTurnId(super.value);
}

/// Identifies one request to the tutor orchestration boundary.
final class TutorRequestId extends TutorTypedId {
  TutorRequestId(super.value);
}

/// Identifies one user-confirmable tutor action.
final class TutorActionId extends TutorTypedId {
  TutorActionId(super.value);
}

/// Normalizes and validates typed tutor identifiers.
abstract final class TutorIdValidator {
  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw TutorIdValidationException._(TutorIdValidationCode.empty);
    }
    if (trimmed.length > maxTutorIdLength) {
      throw TutorIdValidationException._(TutorIdValidationCode.tooLong);
    }
    return trimmed;
  }
}
