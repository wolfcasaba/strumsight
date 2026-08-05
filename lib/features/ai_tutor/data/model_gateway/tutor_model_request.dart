import 'package:meta/meta.dart';

import '../../domain/models/tutor_ids.dart';

/// An immutable request to the tutor model gateway.
///
/// Each request carries a [TutorRequestId] and a monotonically increasing
/// [sequence] number (SDD §5 Epic 4 id-sequence rule).
@immutable
final class TutorModelRequest {
  const TutorModelRequest({
    required this.requestId,
    required this.sequence,
    required this.conversationId,
    required this.message,
  });

  /// Stable identifier for this request.
  final TutorRequestId requestId;

  /// Monotonically increasing sequence within the conversation.
  final int sequence;

  /// The conversation this request belongs to.
  final TutorConversationId conversationId;

  /// The user message text.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorModelRequest &&
          other.requestId == requestId &&
          other.sequence == sequence &&
          other.conversationId == conversationId &&
          other.message == message;

  @override
  int get hashCode => Object.hash(requestId, sequence, conversationId, message);

  @override
  String toString() =>
      'TutorModelRequest($requestId, seq: $sequence, conv: $conversationId)';
}
