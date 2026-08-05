import 'package:meta/meta.dart';

import '../../domain/models/tutor_ids.dart';
import '../../domain/models/tutor_source_ref.dart';

/// Lifecycle states for one UI-independent tutor turn.
enum TutorTurnStatus {
  idle,
  assemblingContext,
  retrievingKnowledge,
  requestingModel,
  streaming,
  awaitingToolResult,
  validatingOutput,
  completed,
  fallback,
  consentRevoked,
  usageLimit,
  failed,
  cancelled,
}

extension TutorTurnStatusX on TutorTurnStatus {
  bool get isTerminal => switch (this) {
    TutorTurnStatus.completed ||
    TutorTurnStatus.fallback ||
    TutorTurnStatus.consentRevoked ||
    TutorTurnStatus.usageLimit ||
    TutorTurnStatus.failed ||
    TutorTurnStatus.cancelled => true,
    _ => false,
  };
}

/// Immutable state for the currently active tutor conversation turn.
@immutable
final class TutorState {
  TutorState({
    required this.status,
    this.requestId,
    this.conversationId,
    this.responseText = '',
    Iterable<TutorSourceRef> sources = const <TutorSourceRef>[],
    this.repairCount = 0,
    this.failureCode,
  }) : sources = List<TutorSourceRef>.unmodifiable(sources);

  static final TutorState initial = TutorState(status: TutorTurnStatus.idle);

  final TutorTurnStatus status;
  final TutorRequestId? requestId;
  final TutorConversationId? conversationId;
  final String responseText;
  final List<TutorSourceRef> sources;

  /// The state-owned repair cap counter. The orchestrator never exceeds one.
  final int repairCount;
  final String? failureCode;

  bool get isActive => !status.isTerminal && status != TutorTurnStatus.idle;

  TutorState copyWith({
    TutorTurnStatus? status,
    TutorRequestId? requestId,
    TutorConversationId? conversationId,
    String? responseText,
    List<TutorSourceRef>? sources,
    int? repairCount,
    String? failureCode,
    bool clearFailureCode = false,
  }) => TutorState(
    status: status ?? this.status,
    requestId: requestId ?? this.requestId,
    conversationId: conversationId ?? this.conversationId,
    responseText: responseText ?? this.responseText,
    sources: List<TutorSourceRef>.unmodifiable(sources ?? this.sources),
    repairCount: repairCount ?? this.repairCount,
    failureCode: clearFailureCode ? null : failureCode ?? this.failureCode,
  );
}
