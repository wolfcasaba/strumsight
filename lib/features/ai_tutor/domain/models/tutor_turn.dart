import 'tutor_ids.dart';
import 'tutor_response_mode.dart';

/// Immutable correlation data for one learner request and tutor response.
final class TutorTurn {
  TutorTurn({
    required this.id,
    required this.conversationId,
    required this.requestId,
    required this.userMessageId,
    required this.requestedResponseMode,
    required DateTime createdAt,
    this.actionId,
  }) : createdAt = createdAt.toUtc();

  final TutorTurnId id;
  final TutorConversationId conversationId;
  final TutorRequestId requestId;
  final TutorMessageId userMessageId;
  final TutorActionId? actionId;
  final TutorResponseMode requestedResponseMode;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorTurn &&
          other.id == id &&
          other.conversationId == conversationId &&
          other.requestId == requestId &&
          other.userMessageId == userMessageId &&
          other.actionId == actionId &&
          other.requestedResponseMode == requestedResponseMode &&
          other.createdAt.microsecondsSinceEpoch ==
              createdAt.microsecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    requestId,
    userMessageId,
    actionId,
    requestedResponseMode,
    createdAt.microsecondsSinceEpoch,
  );
}
