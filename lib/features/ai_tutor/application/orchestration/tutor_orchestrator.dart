import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import '../../../../core/foundation/app_result.dart';
import '../../data/knowledge/knowledge_retriever.dart';
import '../../data/model_gateway/tutor_model_event.dart';
import '../../data/model_gateway/tutor_model_gateway.dart';
import '../../data/model_gateway/tutor_model_request.dart';
import '../../domain/models/tutor_ids.dart';
import '../../domain/tools/tutor_tool.dart';
import '../../domain/tools/tutor_tool_request.dart';
import '../context/tutor_context_assembler.dart';
import '../context/tutor_context_snapshot.dart';
import '../controller/tutor_command.dart';
import '../controller/tutor_effect.dart';
import '../controller/tutor_state.dart';
import '../prompts/tutor_prompt_builder.dart';
import '../tools/read_only_tutor_tools.dart';
import 'tutor_output_validator.dart';

/// Code emitted by the model gateway when the turn quota is exhausted.
const String tutorUsageLimitCode = 'tutor.usage_limit';

/// Pure state-transition result for one tutor input.
@immutable
final class TutorTransition {
  TutorTransition({
    required this.state,
    Iterable<TutorEffect> effects = const <TutorEffect>[],
    this.isRejected = false,
  }) : effects = List<TutorEffect>.unmodifiable(effects);

  final TutorState state;
  final List<TutorEffect> effects;
  final bool isRejected;
}

/// Pure transition matrix for a single tutor turn.
TutorTransition reduceTutorTurn(TutorState state, TutorInput input) {
  if (input is SendTutorMessage) {
    if (state.isActive) {
      return TutorTransition(state: state, isRejected: true);
    }
    final request = input.request;
    if (!request.consent.modelUseGranted) {
      return TutorTransition(
        state: TutorState(
          status: TutorTurnStatus.consentRevoked,
          requestId: request.requestId,
          conversationId: request.conversationId,
        ),
        effects: <TutorEffect>[TutorConsentRevoked(request.requestId)],
      );
    }
    return TutorTransition(
      state: TutorState(
        status: TutorTurnStatus.assemblingContext,
        requestId: request.requestId,
        conversationId: request.conversationId,
      ),
      effects: <TutorEffect>[BuildTutorContext(request.requestId)],
    );
  }
  if (input is CancelTutorTurn) {
    if (state.requestId != input.requestId || !state.isActive) {
      return TutorTransition(state: state, isRejected: true);
    }
    return TutorTransition(
      state: state.copyWith(status: TutorTurnStatus.cancelled),
      effects: <TutorEffect>[CancelTutorModel(input.requestId)],
    );
  }
  if (input is! TutorSignal ||
      state.requestId != input.requestId ||
      !state.isActive) {
    return TutorTransition(state: state);
  }
  if (input is TutorContextBuilt &&
      state.status == TutorTurnStatus.assemblingContext) {
    return TutorTransition(
      state: state.copyWith(status: TutorTurnStatus.retrievingKnowledge),
      effects: <TutorEffect>[RetrieveTutorKnowledge(input.requestId)],
    );
  }
  if (input is TutorKnowledgeRetrieved &&
      state.status == TutorTurnStatus.retrievingKnowledge) {
    return TutorTransition(
      state: state.copyWith(
        status: TutorTurnStatus.requestingModel,
        sources: input.sources,
      ),
      effects: <TutorEffect>[StartTutorModel(input.requestId, isRepair: false)],
    );
  }
  if (input is TutorModelStarted &&
      state.status == TutorTurnStatus.requestingModel) {
    return TutorTransition(
      state: state.copyWith(status: TutorTurnStatus.streaming),
    );
  }
  if (input is TutorModelEventReceived) {
    final event = input.event;
    if (event is TutorModelDelta && state.status == TutorTurnStatus.streaming) {
      return TutorTransition(
        state: state.copyWith(
          responseText: '${state.responseText}${event.delta}',
        ),
      );
    }
    if (event is TutorModelToolCall &&
        state.status == TutorTurnStatus.streaming) {
      return TutorTransition(
        state: state.copyWith(status: TutorTurnStatus.awaitingToolResult),
        effects: <TutorEffect>[
          ExecuteTutorTool(
            input.requestId,
            name: event.name,
            arguments: event.arguments,
          ),
        ],
      );
    }
    if (event is TutorModelDone && state.status == TutorTurnStatus.streaming) {
      return TutorTransition(
        state: state.copyWith(status: TutorTurnStatus.validatingOutput),
        effects: <TutorEffect>[ValidateTutorOutput(input.requestId)],
      );
    }
    if (event is TutorModelError) {
      if (event.code == tutorUsageLimitCode) {
        return TutorTransition(
          state: state.copyWith(
            status: TutorTurnStatus.usageLimit,
            failureCode: event.code,
          ),
          effects: <TutorEffect>[TutorUsageLimitReached(input.requestId)],
        );
      }
      return TutorTransition(
        state: state.copyWith(
          status: TutorTurnStatus.fallback,
          failureCode: event.code,
        ),
        effects: <TutorEffect>[TutorDeterministicFallback(input.requestId)],
      );
    }
  }
  if (input is TutorToolFinished &&
      state.status == TutorTurnStatus.awaitingToolResult) {
    return TutorTransition(
      state: state.copyWith(status: TutorTurnStatus.streaming),
    );
  }
  if (input is TutorOutputValidated &&
      state.status == TutorTurnStatus.validatingOutput) {
    if (input.result.isValid) {
      return TutorTransition(
        state: state.copyWith(status: TutorTurnStatus.completed),
        effects: <TutorEffect>[TutorTurnCompleted(input.requestId)],
      );
    }
    if (state.repairCount < 1) {
      return TutorTransition(
        state: state.copyWith(
          status: TutorTurnStatus.requestingModel,
          responseText: '',
          repairCount: state.repairCount + 1,
        ),
        effects: <TutorEffect>[
          StartTutorModel(input.requestId, isRepair: true),
        ],
      );
    }
    return TutorTransition(
      state: state.copyWith(status: TutorTurnStatus.fallback),
      effects: <TutorEffect>[TutorDeterministicFallback(input.requestId)],
    );
  }
  if (input is TutorPipelineFailed) {
    return TutorTransition(
      state: state.copyWith(
        status: TutorTurnStatus.failed,
        failureCode: input.code,
      ),
    );
  }
  return TutorTransition(state: state);
}

/// Wires the bounded tutor state machine to context, retrieval, prompt, model and tools.
final class TutorOrchestrator {
  TutorOrchestrator({
    required this.contextAssembler,
    required this.knowledgeRetriever,
    required this.promptBuilder,
    required this.gatewayForAttempt,
    this.outputValidator = const TutorOutputValidator(),
  });

  final TutorContextAssembler contextAssembler;
  final KnowledgeRetriever knowledgeRetriever;
  final TutorPromptBuilder promptBuilder;
  final TutorModelGateway Function(int repairCount) gatewayForAttempt;
  final TutorOutputValidator outputValidator;

  final StreamController<TutorState> _states =
      StreamController<TutorState>.broadcast();
  final StreamController<TutorEffect> _effects =
      StreamController<TutorEffect>.broadcast();
  TutorState _state = TutorState.initial;
  TutorTurnRequest? _request;
  TutorContextSnapshot? _snapshot;
  TutorPrompt? _prompt;
  TutorModelGateway? _gateway;
  StreamSubscription<TutorModelEvent>? _subscription;
  bool _disposed = false;

  TutorState get state => _state;
  Stream<TutorState> get states => _states.stream;
  Stream<TutorEffect> get effects => _effects.stream;

  Future<TutorTransition> dispatch(TutorInput input) async {
    if (_disposed) {
      return TutorTransition(state: _state, isRejected: true);
    }
    final transition = reduceTutorTurn(_state, input);
    if (transition.isRejected) {
      return transition;
    }
    if (input is SendTutorMessage) {
      _request = input.request;
    }
    _state = transition.state;
    _states.add(_state);
    for (final effect in transition.effects) {
      _effects.add(effect);
      await _apply(effect);
    }
    return transition;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _gateway?.cancel();
    await _states.close();
    await _effects.close();
  }

  Future<void> _apply(TutorEffect effect) async {
    final request = _request;
    if (request == null || _state.requestId != effect.requestId) {
      return;
    }
    try {
      switch (effect) {
        case BuildTutorContext():
          _snapshot = contextAssembler.assemble(
            requestId: request.requestId.value,
            createdAt: request.createdAt,
            purpose: request.purpose,
            fields: request.contextFields,
          );
          await dispatch(TutorContextBuilt(effect.requestId));
        case RetrieveTutorKnowledge():
          final sources = knowledgeRetriever.retrieve(request.retrievalQuery);
          await dispatch(TutorKnowledgeRetrieved(effect.requestId, sources));
        case StartTutorModel(:final isRepair):
          await _startModel(effect.requestId, request, isRepair: isRepair);
        case ExecuteTutorTool(:final name, :final arguments):
          await _executeTool(effect.requestId, request, name, arguments);
        case ValidateTutorOutput():
          await dispatch(
            TutorOutputValidated(
              effect.requestId,
              outputValidator.validate(
                TutorOutputValidationRequest(
                  output: _state.responseText,
                  trustedSources: _state.sources,
                  actions: request.actionProposals,
                  actionContext: request.actionContext,
                ),
              ),
            ),
          );
        case CancelTutorModel():
          await _subscription?.cancel();
          _subscription = null;
          _gateway?.cancel();
        case TutorTurnCompleted() ||
            TutorDeterministicFallback() ||
            TutorConsentRevoked() ||
            TutorUsageLimitReached():
          await _subscription?.cancel();
          _subscription = null;
          _gateway?.cancel();
      }
    } catch (_) {
      await dispatch(
        TutorPipelineFailed(effect.requestId, 'tutor.pipeline.failed'),
      );
    }
  }

  Future<void> _startModel(
    TutorRequestId requestId,
    TutorTurnRequest request, {
    required bool isRepair,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      throw StateError('Context must be built before model start.');
    }
    final registry = ReadOnlyTutorTools.registryFor(snapshot: snapshot);
    _prompt ??= await promptBuilder.build(
      TutorPromptRequest(
        context: snapshot,
        responseLocale: request.responseLocale,
        responseMode: request.responseMode,
        toolRegistry: registry,
        toolPolicy: request.toolPolicy,
        trustedSources: _state.sources,
        userRequest: request.message,
      ),
    );
    _gateway = gatewayForAttempt(_state.repairCount);
    final message = isRepair
        ? '${_prompt!.text}\nRepair the previous response to match the required output schema.'
        : _prompt!.text;
    final started = await _gateway!.start(
      TutorModelRequest(
        requestId: requestId,
        sequence: _state.repairCount,
        conversationId: request.conversationId,
        message: message,
      ),
    );
    switch (started) {
      case Failure(:final error):
        await dispatch(
          TutorModelEventReceived(
            requestId,
            TutorModelError(
              sequence: _state.repairCount,
              code: error.code,
              message: '',
            ),
          ),
        );
      case Success(:final value):
        await dispatch(TutorModelStarted(requestId));
        _subscription = value.listen(
          (event) =>
              unawaited(dispatch(TutorModelEventReceived(requestId, event))),
          onError: (_, _) => unawaited(
            dispatch(TutorPipelineFailed(requestId, 'tutor.model.stream')),
          ),
        );
    }
  }

  Future<void> _executeTool(
    TutorRequestId requestId,
    TutorTurnRequest request,
    String name,
    String rawArguments,
  ) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      throw StateError('Context must be built before tool execution.');
    }
    final decoded = jsonDecode(rawArguments);
    if (decoded is! Map) {
      throw const FormatException('Tool arguments must be an object.');
    }
    final arguments = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException('Tool argument key must be a string.');
      }
      arguments[entry.key as String] = entry.value;
    }
    final result = await ReadOnlyTutorTools.registryFor(snapshot: snapshot)
        .execute(
          TutorToolRequest(
            toolName: name,
            input: TutorToolInput(arguments),
            policy: request.toolPolicy,
            timeout: const Duration(seconds: 1),
          ),
        );
    if (result is Failure) {
      await dispatch(TutorPipelineFailed(requestId, 'tutor.tool.failed'));
      return;
    }
    await dispatch(TutorToolFinished(requestId));
  }
}
