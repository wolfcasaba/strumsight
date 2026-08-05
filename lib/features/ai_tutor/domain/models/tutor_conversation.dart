import 'tutor_ids.dart';
import 'tutor_message.dart';

/// Lifecycle of a tutor conversation.
enum TutorConversationStatus { active, archived, deleted }

/// Stable exception thrown when a [TutorConversation] is invalid.
class TutorConversationValidationException implements Exception {
  TutorConversationValidationException._(this.code);

  /// One of [TutorConversationValidationCode]'s constants.
  final String code;

  @override
  String toString() => 'TutorConversationValidationException($code)';
}

/// Stable machine-readable codes emitted by conversation validation.
abstract final class TutorConversationValidationCode {
  static const String schemaVersionOutOfRange =
      'tutorConversation.schemaVersion.outOfRange';
  static const String createdAtAfterUpdatedAt =
      'tutorConversation.createdAt.afterUpdatedAt';
  static const String localeEmpty = 'tutorConversation.locale.empty';
}

/// Immutable, versioned conversation envelope with stable message ordering.
final class TutorConversation {
  TutorConversation({
    required this.schemaVersion,
    required this.id,
    required DateTime createdAt,
    required DateTime updatedAt,
    required String locale,
    required this.status,
    required List<TutorMessage> messages,
    this.title,
  }) : createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       locale = locale.trim() {
    if (schemaVersion < 1) {
      throw TutorConversationValidationException._(
        TutorConversationValidationCode.schemaVersionOutOfRange,
      );
    }
    if (this.createdAt.isAfter(this.updatedAt)) {
      throw TutorConversationValidationException._(
        TutorConversationValidationCode.createdAtAfterUpdatedAt,
      );
    }
    if (this.locale.isEmpty) {
      throw TutorConversationValidationException._(
        TutorConversationValidationCode.localeEmpty,
      );
    }
    this.messages = List<TutorMessage>.unmodifiable(_orderMessages(messages));
  }

  final int schemaVersion;
  final TutorConversationId id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String locale;
  final TutorConversationStatus status;
  final String? title;
  late final List<TutorMessage> messages;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorConversation &&
          other.schemaVersion == schemaVersion &&
          other.id == id &&
          other.createdAt.microsecondsSinceEpoch ==
              createdAt.microsecondsSinceEpoch &&
          other.updatedAt.microsecondsSinceEpoch ==
              updatedAt.microsecondsSinceEpoch &&
          other.locale == locale &&
          other.status == status &&
          other.title == title &&
          _listEquals(other.messages, messages);

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    id,
    createdAt.microsecondsSinceEpoch,
    updatedAt.microsecondsSinceEpoch,
    locale,
    status,
    title,
    Object.hashAll(messages),
  );
}

List<TutorMessage> _orderMessages(List<TutorMessage> messages) {
  final indexed = messages.indexed.toList()
    ..sort((left, right) {
      final sequenceOrder = left.$2.sequence.compareTo(right.$2.sequence);
      return sequenceOrder != 0 ? sequenceOrder : left.$1.compareTo(right.$1);
    });
  return <TutorMessage>[for (final entry in indexed) entry.$2];
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
