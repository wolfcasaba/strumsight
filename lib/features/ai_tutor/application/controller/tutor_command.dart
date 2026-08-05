import '../../data/model_gateway/tutor_model_event.dart';
import '../../data/knowledge/knowledge_retriever.dart';
import '../../domain/models/tutor_action.dart';
import '../../domain/models/tutor_consent.dart';
import '../../domain/models/tutor_ids.dart';
import '../../domain/models/tutor_response_mode.dart';
import '../../domain/models/tutor_source_ref.dart';
import '../../domain/tools/tutor_tool_request.dart';
import '../context/context_purpose.dart';
import '../context/tutor_context_snapshot.dart';
import '../orchestration/tutor_action_validator.dart';
import '../orchestration/tutor_output_validator.dart';

/// Immutable caller input for the entire deterministic tutor turn pipeline.
final class TutorTurnRequest {
  TutorTurnRequest({
    required this.requestId,
    required this.conversationId,
    required this.message,
    required this.createdAt,
    required this.consent,
    required this.purpose,
    required Iterable<TutorContextField> contextFields,
    required this.retrievalQuery,
    required this.responseLocale,
    required this.responseMode,
    required this.toolPolicy,
    required this.actionContext,
    Iterable<TutorActionProposal> actionProposals =
        const <TutorActionProposal>[],
  }) : contextFields = List<TutorContextField>.unmodifiable(contextFields),
       actionProposals = List<TutorActionProposal>.unmodifiable(
         actionProposals,
       );

  final TutorRequestId requestId;
  final TutorConversationId conversationId;
  final String message;
  final DateTime createdAt;
  final TutorConsent consent;
  final ContextPurpose purpose;
  final List<TutorContextField> contextFields;
  final KnowledgeRetrievalQuery retrievalQuery;
  final String responseLocale;
  final TutorResponseMode responseMode;
  final TutorToolTurnPolicy toolPolicy;
  final TutorActionValidationContext actionContext;
  final List<TutorActionProposal> actionProposals;
}

/// A reducer input is either a caller command or a correlated pipeline signal.
sealed class TutorInput {
  const TutorInput();
}

sealed class TutorCommand extends TutorInput {
  const TutorCommand();
}

final class SendTutorMessage extends TutorCommand {
  const SendTutorMessage(this.request);

  final TutorTurnRequest request;
}

final class CancelTutorTurn extends TutorCommand {
  const CancelTutorTurn(this.requestId);

  final TutorRequestId requestId;
}

sealed class TutorSignal extends TutorInput {
  const TutorSignal(this.requestId);

  final TutorRequestId requestId;
}

final class TutorContextBuilt extends TutorSignal {
  const TutorContextBuilt(super.requestId);
}

final class TutorKnowledgeRetrieved extends TutorSignal {
  TutorKnowledgeRetrieved(super.requestId, Iterable<TutorSourceRef> sources)
    : sources = List<TutorSourceRef>.unmodifiable(sources);

  final List<TutorSourceRef> sources;
}

final class TutorModelStarted extends TutorSignal {
  const TutorModelStarted(super.requestId);
}

final class TutorModelEventReceived extends TutorSignal {
  const TutorModelEventReceived(super.requestId, this.event);

  final TutorModelEvent event;
}

final class TutorToolFinished extends TutorSignal {
  const TutorToolFinished(super.requestId);
}

final class TutorOutputValidated extends TutorSignal {
  const TutorOutputValidated(super.requestId, this.result);

  final TutorOutputValidationResult result;
}

final class TutorPipelineFailed extends TutorSignal {
  const TutorPipelineFailed(super.requestId, this.code);

  final String code;
}
