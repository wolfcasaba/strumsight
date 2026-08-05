import '../../domain/models/tutor_action.dart';
import 'tutor_action_validator.dart';

abstract interface class TutorActionExecutor {
  Future<void> execute(TutorAction action);
}

enum ActionConfirmationState {
  pendingConfirmation,
  confirmed,
  rejected,
  blocked,
}

final class ActionConfirmation {
  ActionConfirmation._({
    required this.state,
    this.action,
    this.preview,
    Iterable<TutorActionValidationIssue> validationIssues =
        const <TutorActionValidationIssue>[],
  }) : validationIssues = List<TutorActionValidationIssue>.unmodifiable(
         validationIssues,
       );

  factory ActionConfirmation.pending(TutorAction action) =>
      ActionConfirmation._(
        state: ActionConfirmationState.pendingConfirmation,
        action: action,
        preview: action.preview,
      );

  factory ActionConfirmation.confirmed(TutorAction action) =>
      ActionConfirmation._(
        state: ActionConfirmationState.confirmed,
        action: action,
        preview: action.preview,
      );

  factory ActionConfirmation.rejected(TutorAction action) =>
      ActionConfirmation._(
        state: ActionConfirmationState.rejected,
        action: action,
        preview: action.preview,
      );

  factory ActionConfirmation.blocked(
    Iterable<TutorActionValidationIssue> issues,
  ) => ActionConfirmation._(
    state: ActionConfirmationState.blocked,
    validationIssues: issues,
  );

  final ActionConfirmationState state;
  final TutorAction? action;
  final TutorActionPreview? preview;
  final List<TutorActionValidationIssue> validationIssues;
}

final class ActionConfirmationService {
  ActionConfirmationService({
    required this.executor,
    this.validator = const TutorActionValidator(),
  });

  final TutorActionExecutor executor;
  final TutorActionValidator validator;
  final Set<String> _confirmedClientActionIds = <String>{};
  final Map<String, Future<ActionConfirmation>> _inFlightConfirmations =
      <String, Future<ActionConfirmation>>{};

  ActionConfirmation propose(
    TutorActionProposal proposal, {
    required TutorActionValidationContext context,
  }) {
    final validation = validator.validate(proposal, context: context);
    if (!validation.isValid) {
      return ActionConfirmation.blocked(validation.issues);
    }
    if (proposal is! TutorAction) {
      return ActionConfirmation.blocked(const <TutorActionValidationIssue>[
        TutorActionValidationIssue.unknownAction,
      ]);
    }
    return ActionConfirmation.pending(proposal);
  }

  ActionConfirmation reject(ActionConfirmation confirmation) {
    final action = confirmation.action;
    if (confirmation.state != ActionConfirmationState.pendingConfirmation ||
        action == null) {
      return confirmation;
    }
    return ActionConfirmation.rejected(action);
  }

  Future<ActionConfirmation> confirm(
    ActionConfirmation confirmation, {
    required TutorActionValidationContext context,
  }) {
    final action = confirmation.action;
    if (confirmation.state != ActionConfirmationState.pendingConfirmation ||
        action == null) {
      return Future<ActionConfirmation>.value(confirmation);
    }

    final clientActionId = action.metadata.clientActionId;
    if (_confirmedClientActionIds.contains(clientActionId)) {
      return Future<ActionConfirmation>.value(
        ActionConfirmation.confirmed(action),
      );
    }
    final inFlight = _inFlightConfirmations[clientActionId];
    if (inFlight != null) return inFlight;

    final confirmationFuture = _confirmOnce(action, context: context);
    _inFlightConfirmations[clientActionId] = confirmationFuture;
    return confirmationFuture.whenComplete(
      () => _inFlightConfirmations.remove(clientActionId),
    );
  }

  Future<ActionConfirmation> _confirmOnce(
    TutorAction action, {
    required TutorActionValidationContext context,
  }) async {
    final validation = validator.validate(action, context: context);
    if (!validation.isValid) {
      return ActionConfirmation.blocked(validation.issues);
    }
    await executor.execute(action);
    _confirmedClientActionIds.add(action.metadata.clientActionId);
    return ActionConfirmation.confirmed(action);
  }
}
