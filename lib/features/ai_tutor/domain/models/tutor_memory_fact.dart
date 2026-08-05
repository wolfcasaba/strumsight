import 'tutor_ids.dart';

/// Stable validation errors for user-inspectable tutor memory.
class TutorMemoryFactValidationException implements Exception {
  TutorMemoryFactValidationException._(this.code);

  final String code;

  @override
  String toString() => 'TutorMemoryFactValidationException($code)';
}

abstract final class TutorMemoryFactValidationCode {
  static const String idEmpty = 'tutorMemoryFact.id.empty';
  static const String contentEmpty = 'tutorMemoryFact.content.empty';
  static const String updatedBeforeCreated =
      'tutorMemoryFact.updatedAt.beforeCreatedAt';
}

/// A candidate fact derived from a specific, inspectable tutor message.
///
/// It intentionally contains no provider-specific data or raw audio.
final class TutorMemoryCandidate {
  TutorMemoryCandidate({
    required String id,
    required String content,
    required this.conversationId,
    required this.messageId,
    required DateTime createdAt,
    DateTime? expiresAt,
  }) : id = _required(id, TutorMemoryFactValidationCode.idEmpty),
       content = _required(content, TutorMemoryFactValidationCode.contentEmpty),
       createdAt = createdAt.toUtc(),
       expiresAt = expiresAt?.toUtc();

  final String id;
  final String content;
  final TutorConversationId conversationId;
  final TutorMessageId messageId;
  final DateTime createdAt;
  final DateTime? expiresAt;
}

/// A local, user-viewable and user-editable tutor memory fact.
final class TutorMemoryFact {
  TutorMemoryFact({
    required String id,
    required String content,
    required this.conversationId,
    required this.messageId,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? expiresAt,
  }) : id = _required(id, TutorMemoryFactValidationCode.idEmpty),
       content = _required(content, TutorMemoryFactValidationCode.contentEmpty),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       expiresAt = expiresAt?.toUtc() {
    if (this.updatedAt.isBefore(this.createdAt)) {
      throw TutorMemoryFactValidationException._(
        TutorMemoryFactValidationCode.updatedBeforeCreated,
      );
    }
  }

  final String id;
  final String content;
  final TutorConversationId conversationId;
  final TutorMessageId messageId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now.toUtc());

  TutorMemoryFact copyWith({
    String? content,
    DateTime? updatedAt,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) => TutorMemoryFact(
    id: id,
    content: content ?? this.content,
    conversationId: conversationId,
    messageId: messageId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    expiresAt: clearExpiry ? null : (expiresAt ?? this.expiresAt),
  );

  @override
  bool operator ==(Object other) =>
      other is TutorMemoryFact &&
      other.id == id &&
      other.content == content &&
      other.conversationId == conversationId &&
      other.messageId == messageId &&
      other.createdAt.microsecondsSinceEpoch ==
          createdAt.microsecondsSinceEpoch &&
      other.updatedAt.microsecondsSinceEpoch ==
          updatedAt.microsecondsSinceEpoch &&
      other.expiresAt?.microsecondsSinceEpoch ==
          expiresAt?.microsecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
    id,
    content,
    conversationId,
    messageId,
    createdAt.microsecondsSinceEpoch,
    updatedAt.microsecondsSinceEpoch,
    expiresAt?.microsecondsSinceEpoch,
  );
}

String _required(String value, String code) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw TutorMemoryFactValidationException._(code);
  return normalized;
}
