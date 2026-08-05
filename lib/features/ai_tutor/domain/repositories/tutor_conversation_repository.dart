import '../../../../core/foundation/app_result.dart';
import '../models/tutor_conversation.dart';
import '../models/tutor_ids.dart';
import '../models/tutor_message.dart';

/// Paginated local conversation index, ordered by latest update first.
final class TutorConversationPage {
  TutorConversationPage({
    required List<TutorConversation> items,
    required this.offset,
    required this.total,
  }) : items = List<TutorConversation>.unmodifiable(items);

  final List<TutorConversation> items;
  final int offset;
  final int total;

  bool get hasMore => offset + items.length < total;
}

/// A message reference retained by a conversation summary.
final class TutorMessageProvenance {
  const TutorMessageProvenance({
    required this.messageId,
    required this.role,
    required this.sequence,
  });

  final TutorMessageId messageId;
  final TutorMessageRole role;
  final int sequence;
}

/// Inspectable structured conversation summary without copied message content.
final class TutorConversationSummary {
  TutorConversationSummary({
    required this.conversationId,
    required this.messageCount,
    required List<TutorMessageProvenance> messageProvenance,
  }) : messageProvenance = List<TutorMessageProvenance>.unmodifiable(
         messageProvenance,
       );

  final TutorConversationId conversationId;
  final int messageCount;
  final List<TutorMessageProvenance> messageProvenance;
}

/// Local-first persistence boundary for tutor conversations.
abstract interface class TutorConversationRepository {
  Future<AppResult<void>> save(TutorConversation conversation);

  Future<AppResult<TutorConversation?>> get(TutorConversationId id);

  Future<AppResult<TutorConversationPage>> list({
    int offset = 0,
    int limit = 20,
  });

  Future<AppResult<TutorConversationSummary?>> summary(TutorConversationId id);

  Future<AppResult<void>> delete(TutorConversationId id);
}
