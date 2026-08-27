/// Riverpod wiring for the Tutor Home + Chat presentation layer (E04-R18).
///
/// Every screen-level dependency the chat and home surfaces need is
/// exposed here. The screens are pure `ConsumerWidget`s — they read
/// state from the providers below and dispatch actions through
/// [TutorChatController] (one of the few mutable seams in the file).
///
/// The whole layer is fake-gateway-testable: widget tests override
/// [tutorChatControllerProvider] with a `FakeController` so the chat
/// screen is fully exercisable without spinning the real
/// [TutorOrchestrator]. The orchestrator itself is only built in
/// production code paths.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/key_value_store.dart';
import '../../application/context/context_purpose.dart';
import '../../application/context/tutor_context_assembler.dart';
import '../../application/context/tutor_context_snapshot.dart';
import '../../application/controller/tutor_command.dart';
import '../../application/controller/tutor_state.dart';
import '../../application/orchestration/tutor_action_validator.dart';
import '../../application/orchestration/tutor_orchestrator.dart';
import '../../application/prompts/prompt_template.dart';
import '../../application/prompts/tutor_prompt_builder.dart';
import '../../data/knowledge/knowledge_index.dart';
import '../../data/knowledge/knowledge_retriever.dart';
import '../../data/model_gateway/local_tutor_model_gateway_stub.dart';
import '../../data/repositories/local_tutor_conversation_repository.dart';
import '../../domain/models/tutor_action.dart';
import '../../domain/models/tutor_consent.dart';
import '../../domain/models/tutor_content_block.dart';
import '../../domain/models/tutor_ids.dart';
import '../../domain/models/tutor_message.dart';
import '../../domain/models/tutor_response_mode.dart';
import '../../domain/repositories/tutor_conversation_repository.dart';
import '../../domain/tools/tutor_tool.dart';
import '../../domain/tools/tutor_tool_request.dart';

// ---------------------------------------------------------------------------
// Banner taxonomy — kept here because the providers and the banner widget
// share it. The four cells are distinct (offline≠consent≠rate≠error) and
// the chat screen test asserts on the exact distinct semantics labels.
// ---------------------------------------------------------------------------

/// Banner categories the Chat screen renders above the message list.
enum TutorBannerKind {
  /// Local connectivity is unavailable.
  offline,

  /// Model use consent has not been granted.
  consent,

  /// Cloud tutor usage limit was reached (orchestrator surfaces this).
  rateLimit,

  /// Last turn failed and is not retrying on its own.
  error,

  /// Last turn was cancelled by the user.
  cancelled,
}

/// Immutable snapshot consumed by both the chat screen and the banners.
@immutable
class TutorChatState {
  const TutorChatState({
    required this.status,
    required this.responseText,
    required this.banners,
    required this.isOnline,
    this.draft = '',
    this.messages = const <TutorMessage>[],
  });

  final TutorTurnStatus status;
  final String responseText;
  final List<TutorBannerKind> banners;
  final bool isOnline;
  final String draft;
  final List<TutorMessage> messages;

  TutorChatState copyWith({
    TutorTurnStatus? status,
    String? responseText,
    List<TutorBannerKind>? banners,
    bool? isOnline,
    String? draft,
    List<TutorMessage>? messages,
  }) => TutorChatState(
    status: status ?? this.status,
    responseText: responseText ?? this.responseText,
    banners: banners ?? this.banners,
    isOnline: isOnline ?? this.isOnline,
    draft: draft ?? this.draft,
    messages: messages ?? this.messages,
  );
}

// ---------------------------------------------------------------------------
// Controller interface — the only mutable seam the chat screen uses.
// Implementations: [DefaultTutorChatController] (production), plus
// widget-test fakes that override [tutorChatControllerProvider].
// ---------------------------------------------------------------------------

abstract interface class TutorChatController {
  /// Current message history (user + tutor). Order is oldest-first.
  List<TutorMessage> get messages;

  /// Current orchestrator status; defaults to [TutorTurnStatus.idle].
  TutorTurnStatus get status;

  /// Raw streamed response text; reset on each new turn.
  String get responseText;

  /// Composer draft text.
  String get draft;

  /// Connectivity flag (true when online). Drives the offline banner.
  bool get isOnline;

  /// Currently-visible banners (may be empty).
  List<TutorBannerKind> get banners;

  /// Stream of snapshots for widgets that prefer `StreamBuilder`-style
  /// wiring (kept for parity with the orchestrator contract).
  Stream<TutorChatState> get states;

  void setDraft(String value);
  void send();
  void cancel();
  void retry();
  void setOnline(bool value);
  void setBanners(List<TutorBannerKind> value);
}

/// No-op — kept as a marker so the existing bubble switch arms
/// resolve. Streaming text uses [TutorTextBlock] directly; the bubble
/// already handles it.

// ---------------------------------------------------------------------------
// AI-mode exposure (E13-R29 §0.0/B6) — presentation-only derivation. Neither
// [TutorChatState] nor [TutorTurnStatus] carries a local/cloud/fallback
// signal today; this is the narrowest possible surface that makes ADR 0278
// §1's "AI-mode always visible" enforceable without touching
// `application/`/`domain/` (out of scope for this round). [isOnline] is the
// existing connectivity flag the offline banner already uses; [status] ==
// [TutorTurnStatus.fallback] is the existing terminal state the orchestrator
// already reaches when the cloud attempt failed and a local fallback
// answered instead.
// ---------------------------------------------------------------------------

/// Where the tutor's current/next reply is (or would be) computed.
enum TutorAiMode { local, cloud, fallback }

/// Derives the screen-visible AI mode from the two signals the presentation
/// layer already has. Never returns null — the caller can always render
/// something (ADR 0278 §1: AI-mode is never hidden for lack of a value).
TutorAiMode tutorAiModeFor({
  required TutorTurnStatus status,
  required bool isOnline,
}) {
  if (status == TutorTurnStatus.fallback) return TutorAiMode.fallback;
  return isOnline ? TutorAiMode.cloud : TutorAiMode.local;
}

// ---------------------------------------------------------------------------
// Local extension — the application layer exposes `isActive` on the
// [TutorState] envelope but the presentation layer only needs to check
// the bare status. Mirrors the upstream rule without reaching into the
// orchestrator's state object.
// ---------------------------------------------------------------------------
extension TutorTurnStatusActiveX on TutorTurnStatus {
  bool get isActive => switch (this) {
    TutorTurnStatus.idle ||
    TutorTurnStatus.completed ||
    TutorTurnStatus.fallback ||
    TutorTurnStatus.consentRevoked ||
    TutorTurnStatus.usageLimit ||
    TutorTurnStatus.failed ||
    TutorTurnStatus.cancelled => false,
    _ => true,
  };
}

// ---------------------------------------------------------------------------
// Production controller — owns a TutorOrchestrator supplied by the boot
// overrides. The orchestrator is shared with the gateway factory so a single
// turn maps to a single streaming session.
// ---------------------------------------------------------------------------

class DefaultTutorChatController extends ChangeNotifier
    implements TutorChatController {
  DefaultTutorChatController({
    required this.orchestrator,
    required this.repository,
    required this.conversationId,
    required this.requestIdFactory,
    required this.turnRequestFactory,
    required this.onChanged,
  });

  /// Called whenever the controller's visible state changes — wired
  /// to `TutorChatNotifier.state = state` so Riverpod rebuilds.
  final void Function(TutorChatState next) onChanged;

  final TutorOrchestrator orchestrator;
  final TutorConversationRepository repository;
  final TutorConversationId conversationId;
  final TutorRequestId Function() requestIdFactory;
  final TutorTurnRequest Function(String message) turnRequestFactory;

  final List<TutorMessage> _messages = <TutorMessage>[];
  final StreamController<TutorChatState> _statesController =
      StreamController<TutorChatState>.broadcast();
  StreamSubscription<TutorState>? _stateSubscription;

  @override
  List<TutorMessage> get messages => List<TutorMessage>.unmodifiable(_messages);

  @override
  TutorTurnStatus status = TutorTurnStatus.idle;

  @override
  String responseText = '';

  @override
  String draft = '';

  @override
  bool isOnline = true;

  @override
  List<TutorBannerKind> banners = const <TutorBannerKind>[];

  @override
  Stream<TutorChatState> get states => _statesController.stream;

  void _emit() {
    final snapshot = TutorChatState(
      status: status,
      responseText: responseText,
      banners: banners,
      isOnline: isOnline,
      draft: draft,
      messages: List<TutorMessage>.unmodifiable(_messages),
    );
    _statesController.add(snapshot);
    onChanged(snapshot);
    notifyListeners();
  }

  void _consume(TutorState next) {
    status = next.status;
    responseText = next.responseText;
    final nextBanners = <TutorBannerKind>[];
    if (!isOnline) nextBanners.add(TutorBannerKind.offline);
    switch (next.status) {
      case TutorTurnStatus.consentRevoked:
        nextBanners.add(TutorBannerKind.consent);
      case TutorTurnStatus.usageLimit:
        nextBanners.add(TutorBannerKind.rateLimit);
      case TutorTurnStatus.failed:
      case TutorTurnStatus.fallback:
        nextBanners.add(TutorBannerKind.error);
      case TutorTurnStatus.cancelled:
        nextBanners.add(TutorBannerKind.cancelled);
      case _:
        break;
    }
    banners = List<TutorBannerKind>.unmodifiable(nextBanners);
    _emit();
  }

  /// Initialize streams on first build. Idempotent — safe to call from
  /// `ref.onAddListener` or directly.
  void attach() {
    _stateSubscription ??= orchestrator.states.listen(_consume);
  }

  @override
  void setDraft(String value) {
    if (draft == value) return;
    draft = value;
    _emit();
  }

  @override
  void send() {
    final text = draft.trim();
    if (text.isEmpty) return;
    final userMessage = _userMessage(text);
    _messages.add(userMessage);
    draft = '';
    status = TutorTurnStatus.assemblingContext;
    responseText = '';
    _emit();
    unawaited(
      orchestrator.dispatch(SendTutorMessage(turnRequestFactory(text))),
    );
  }

  @override
  void cancel() {
    if (!status.isActive) return;
    final requestId = orchestrator.state.requestId;
    if (requestId == null) return;
    unawaited(orchestrator.dispatch(CancelTutorTurn(requestId)));
  }

  @override
  void retry() {
    if (status.isTerminal || status == TutorTurnStatus.idle) {
      send();
      return;
    }
    cancel();
    Future<void>.delayed(Duration.zero, send);
  }

  @override
  void setOnline(bool value) {
    if (isOnline == value) return;
    isOnline = value;
    _consume(orchestrator.state);
  }

  @override
  void setBanners(List<TutorBannerKind> value) {
    banners = List<TutorBannerKind>.unmodifiable(value);
    _emit();
  }

  TutorMessage _userMessage(String text) {
    final createdAt = DateTime.now().toUtc();
    return TutorMessage(
      id: TutorMessageId('m-${createdAt.microsecondsSinceEpoch}'),
      role: TutorMessageRole.user,
      createdAt: createdAt,
      sequence: _messages.length,
      deliveryState: TutorMessageDeliveryState.complete,
      blocks: <TutorContentBlock>[TutorTextBlock(text: text)],
    );
  }

  @override
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _statesController.close();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider wiring
// ---------------------------------------------------------------------------

/// Constructs the production tutor orchestrator for the boot composition.
///
/// The local model gateway stub is intentional: it reports a controlled
/// unavailable error until the real provider adapter is shipped. Tests can
/// still override the provider with their own controller or orchestrator.
TutorOrchestrator createProductionTutorOrchestrator({
  required KnowledgeRetriever knowledgeRetriever,
}) => TutorOrchestrator(
  contextAssembler: const TutorContextAssembler(),
  knowledgeRetriever: knowledgeRetriever,
  promptBuilder: TutorPromptBuilder(
    templateLoader: AssetPromptTemplateLoader(assetBundle: rootBundle),
  ),
  gatewayForAttempt: (_) => LocalTutorModelGatewayStub(),
);

/// Constructs the production local conversation repository.
TutorConversationRepository createProductionTutorConversationRepository({
  required KeyValueStore keyValueStore,
}) => LocalTutorConversationRepository(keyValueStore: keyValueStore);

/// Overridable production seam. The app boot injects the concrete instance;
/// tests override it with their own controller or orchestrator.
final tutorOrchestratorProvider = Provider<TutorOrchestrator>((ref) {
  throw UnimplementedError(
    'tutorOrchestratorProvider must be overridden in tests; '
    'production wires it from the boot layer.',
  );
});

/// Overridable repository seam for the conversation list — Home screen reads
/// from this. Production boot injects a local repository.
final tutorConversationRepositoryProvider =
    Provider<TutorConversationRepository>((ref) {
      throw UnimplementedError(
        'tutorConversationRepositoryProvider must be overridden in tests.',
      );
    });

/// Default chat state — owned by a regular Riverpod provider that
/// returns the [TutorChatController]. Widgets read the visible state
/// from the controller's [TutorChatController.states] stream (see
/// [tutorChatStateProvider]) so they rebuild on every mutation.
final tutorChatControllerProvider = Provider<TutorChatController>((ref) {
  final orchestrator = ref.watch(tutorOrchestratorProvider);
  final repository = ref.watch(tutorConversationRepositoryProvider);
  final controller = DefaultTutorChatController(
    orchestrator: orchestrator,
    repository: repository,
    conversationId: TutorConversationId('preview'),
    requestIdFactory: _defaultRequestId,
    turnRequestFactory: (text) => _previewTurnRequest(text),
    onChanged: (_) {},
  );
  controller.attach();
  ref.onDispose(controller.dispose);
  return controller;
});

/// The chat's currently visible state, derived from the controller's
/// stream. Widgets that need to rebuild on banner / draft / streaming
/// changes watch this provider instead of the controller identity.
final tutorChatStateProvider = StreamProvider<TutorChatState>((ref) {
  final controller = ref.watch(tutorChatControllerProvider);
  return controller.states;
});

TutorRequestId _defaultRequestId() =>
    TutorRequestId('r-${DateTime.now().microsecondsSinceEpoch}');

TutorTurnRequest _previewTurnRequest(String text) => TutorTurnRequest(
  requestId: _defaultRequestId(),
  conversationId: TutorConversationId('preview'),
  message: text,
  createdAt: DateTime.now().toUtc(),
  consent: const TutorConsent(modelUseGranted: true),
  purpose: ContextPurpose.generalQuestion,
  contextFields: const <TutorContextField>[],
  retrievalQuery: KnowledgeRetrievalQuery(queryText: text, locale: 'en'),
  responseLocale: 'en',
  responseMode: TutorResponseMode.concise,
  toolPolicy: TutorToolTurnPolicy(
    allowedToolNames: const <String>{'getContextField'},
    allowedPermissions: const <TutorToolPermission>[],
  ),
  actionContext: TutorActionValidationContext(
    now: DateTime.now().toUtc(),
    availableCapabilities: const <TutorActionCapability>[],
    activeSessionIds: const <String>[],
    songRevisions: const <String, TutorActionRevisionToken>{},
  ),
);

/// Build a `TutorContextAssembler` for the preview conversation. The
/// fields list is empty — the preview path does not surface real
/// student context.
TutorContextAssembler buildPreviewAssembler() => const TutorContextAssembler();

/// Build a knowledge retriever backed by the empty index (preview only).
KnowledgeRetriever buildPreviewRetriever() =>
    KnowledgeRetriever(index: const KnowledgeIndex.empty());
