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
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/i18n/effective_locale.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/logging/logger_provider.dart';
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
import '../../data/local/tutor_conversation_codec.dart';
import '../../data/model_gateway/local_tutor_model_gateway_stub.dart';
import '../../data/repositories/local_tutor_conversation_repository.dart';
import '../../domain/models/tutor_action.dart';
import '../../domain/models/tutor_consent.dart';
import '../../domain/models/tutor_content_block.dart';
import '../../domain/models/tutor_conversation.dart';
import '../../domain/models/tutor_ids.dart';
import '../../domain/models/tutor_message.dart';
import '../../domain/models/tutor_response_mode.dart';
import '../../domain/repositories/tutor_conversation_repository.dart';
import '../../domain/tools/tutor_tool.dart';
import '../../domain/tools/tutor_tool_request.dart';
import 'tutor_gateway_providers.dart';
import 'tutor_privacy_providers.dart';

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

// ---------------------------------------------------------------------------
// Consent gate on the request path (data-inventory MAJOR-3).
//
// Before this, `_previewTurnRequest` hardcoded `modelUseGranted: true`, so a
// revocation written by the privacy screen into
// `tutorConsentControllerProvider` was a value nothing in `lib/**` ever read
// back into a turn request. The producer below closes that: it reads the
// LIVE consent on every send and refuses to build a request at all when
// model use is not granted, so no gateway — local or cloud — is ever asked
// to start a turn for a revoked student.
// ---------------------------------------------------------------------------

/// Failure code for a turn refused because model-use consent is absent or
/// was revoked. The chat surface localises it through the
/// [TutorBannerKind.consent] banner; the code itself never reaches the user.
const String tutorModelUseConsentMissingCode =
    'tutor.consent.model_use_missing';

/// Builds the request for one turn, or refuses it with a typed failure.
typedef TutorTurnRequestProducer =
    AppResult<TutorTurnRequest> Function(String message);

/// The production turn-request producer: consent-gated by construction.
///
/// Returns a [Failure] carrying [tutorModelUseConsentMissingCode] when
/// [consent] does not grant model use — the request object is never even
/// built, so there is nothing for a caller to accidentally send.
AppResult<TutorTurnRequest> buildTutorTurnRequest({
  required String message,
  required TutorConsent consent,
}) {
  if (!consent.modelUseGranted) {
    return const AppResult<TutorTurnRequest>.failure(
      ValidationFailure(code: tutorModelUseConsentMissingCode),
    );
  }
  return AppResult<TutorTurnRequest>.success(
    _previewTurnRequest(message, consent),
  );
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
    this.failureCode,
  });

  final TutorTurnStatus status;
  final String responseText;
  final List<TutorBannerKind> banners;
  final bool isOnline;
  final String draft;
  final List<TutorMessage> messages;

  /// Stable failure code of the last refused/failed turn, or null. The UI
  /// localises by this code — it never carries user-facing English text.
  final String? failureCode;

  TutorChatState copyWith({
    TutorTurnStatus? status,
    String? responseText,
    List<TutorBannerKind>? banners,
    bool? isOnline,
    String? draft,
    List<TutorMessage>? messages,
    String? failureCode,
    bool clearFailureCode = false,
  }) => TutorChatState(
    status: status ?? this.status,
    responseText: responseText ?? this.responseText,
    banners: banners ?? this.banners,
    isOnline: isOnline ?? this.isOnline,
    draft: draft ?? this.draft,
    messages: messages ?? this.messages,
    failureCode: clearFailureCode ? null : (failureCode ?? this.failureCode),
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
// The answer itself (E-R29a). The orchestrator streams the model's raw
// output into `TutorState.responseText` and, once
// `TutorOutputValidator` accepts it, reaches `TutorTurnStatus.completed`.
// Nothing then turned that text into a message, so the reply vanished with
// the streaming bubble. This is the narrowest decoder that makes it stay.
// ---------------------------------------------------------------------------

/// Decodes one validated model turn into the blocks the chat bubble renders.
///
/// [output] is the v1 output envelope (`answerBlocks`, `claims`, … — see
/// `tutor_output_schema.dart`). Only the three block shapes the schema's own
/// `answerBlocks` uses are mapped structurally; anything else is preserved
/// as a [TutorUnknownContentBlock], which the bubble already renders
/// verbatim rather than dropping. A payload that is not the envelope at all
/// (a provider that answered in plain prose) becomes a single text block, so
/// the student still reads the answer instead of nothing.
///
/// Returns an empty list when there is nothing to show — an empty
/// `answerBlocks` appends no message rather than an empty bubble.
List<TutorContentBlock> tutorAnswerBlocksFrom(String output) {
  final trimmed = output.trim();
  if (trimmed.isEmpty) return const <TutorContentBlock>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return <TutorContentBlock>[TutorTextBlock(text: trimmed)];
  }
  if (decoded is! Map<String, Object?>) {
    return <TutorContentBlock>[TutorTextBlock(text: trimmed)];
  }
  final raw = decoded['answerBlocks'];
  if (raw is! List) return const <TutorContentBlock>[];
  final blocks = <TutorContentBlock>[];
  for (final entry in raw) {
    final block = _answerBlockFrom(entry);
    if (block != null) blocks.add(block);
  }
  return List<TutorContentBlock>.unmodifiable(blocks);
}

TutorContentBlock? _answerBlockFrom(Object? entry) {
  if (entry is String) {
    return entry.trim().isEmpty ? null : TutorTextBlock(text: entry);
  }
  if (entry is! Map<String, Object?>) return null;
  final type = entry['type'];
  final text = entry['text'];
  if (type == 'text' && text is String && text.trim().isNotEmpty) {
    return TutorTextBlock(text: text);
  }
  final level = entry['level'];
  if (type == 'heading' &&
      text is String &&
      text.trim().isNotEmpty &&
      level is int &&
      level >= 1 &&
      level <= 6) {
    return TutorHeadingBlock(text: text, level: level);
  }
  final items = entry['items'];
  if (type == 'bulletList' &&
      items is List &&
      items.isNotEmpty &&
      items.every((item) => item is String && item.trim().isNotEmpty)) {
    return TutorBulletListBlock(items: items.cast<String>());
  }
  if (type is! String || type.trim().isEmpty) return null;
  try {
    return TutorUnknownContentBlock(originalType: type, rawJson: entry);
  } on TutorContentBlockValidationException {
    return null;
  }
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
    this.localeTag = 'und',
    this.logger = const NoopAppLogger(),
  });

  /// Called whenever the controller's visible state changes — wired
  /// to `TutorChatNotifier.state = state` so Riverpod rebuilds.
  final void Function(TutorChatState next) onChanged;

  final TutorOrchestrator orchestrator;
  final TutorConversationRepository repository;
  final TutorConversationId conversationId;
  final TutorRequestId Function() requestIdFactory;

  /// BCP-47 language tag written onto a NEW persisted conversation
  /// envelope (N1, R33). A restored conversation keeps the tag it was
  /// stored with — the envelope records the language the conversation
  /// was HELD in, and re-stamping it on every save would rewrite that
  /// history. `und` (BCP-47 "undetermined") is the honest default for a
  /// controller built without one.
  final String localeTag;

  /// Where a persistence failure is reported. Storage is best-effort:
  /// a refused write must not take the chat down, and it must never be
  /// silent either. Only METADATA is logged — an id, a failure code and
  /// a message COUNT; never a line of the conversation.
  final AppLogger logger;

  /// Consent-gated request producer. A [Failure] here means the turn is
  /// refused before anything is sent — see [buildTutorTurnRequest].
  final TutorTurnRequestProducer turnRequestFactory;

  final List<TutorMessage> _messages = <TutorMessage>[];
  final StreamController<TutorChatState> _statesController =
      StreamController<TutorChatState>.broadcast();
  StreamSubscription<TutorState>? _stateSubscription;

  /// The text of the last turn the student actually submitted.
  ///
  /// [send] clears [draft] the moment a turn is dispatched, so by the time
  /// the error banner appears there is nothing left to re-send — that is
  /// exactly why the banner's "Retry" was a silent no-op (2026-09-08
  /// re-audit, MAJOR M2). Keeping the submitted text here is what makes
  /// [retry] able to do the thing its label promises.
  String _lastSubmittedText = '';

  /// Whether the current turn's answer has already been appended, so a
  /// re-emission of the same terminal state (e.g. [setOnline] replaying the
  /// orchestrator's state) cannot append the tutor's reply twice.
  bool _answerAppended = false;

  /// N1 (R33) — the persisted envelope's `createdAt`, kept so repeated
  /// saves of the SAME conversation do not keep moving its birth date.
  /// Null until the first save or a successful restore.
  DateTime? _conversationCreatedAt;

  /// The locale a restored conversation was stored with, if any.
  String? _restoredLocaleTag;

  /// Guards [restore] against a second [attach].
  bool _restoreStarted = false;

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

  /// Stable code of the last refused/failed turn, mirrored into
  /// [TutorChatState.failureCode]. Null once a turn is accepted again.
  String? failureCode;

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
      failureCode: failureCode,
    );
    _statesController.add(snapshot);
    onChanged(snapshot);
    notifyListeners();
  }

  void _consume(TutorState next) {
    status = next.status;
    responseText = next.responseText;
    failureCode = next.failureCode;
    // The answer itself. Until E-R29a the streaming bubble was the ONLY
    // place a reply was ever rendered, and it is built from
    // `TutorTurnStatus.streaming` alone — so the moment the turn completed
    // the tutor's answer disappeared from the screen and the conversation
    // held nothing but the student's own question. Appending it here is
    // what makes a completed cloud turn actually readable.
    if (next.status == TutorTurnStatus.completed && !_answerAppended) {
      final blocks = tutorAnswerBlocksFrom(next.responseText);
      if (blocks.isNotEmpty) _messages.add(_tutorMessage(blocks));
      _answerAppended = true;
      // N1 — the turn is over, so the conversation is worth keeping.
      // Fire-and-forget: the write must not block the frame that shows
      // the answer, and a refusal is logged, not surfaced as a failed
      // turn (the turn itself succeeded).
      unawaited(persist());
    }
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
    unawaited(restore());
  }

  /// N1 (R33) — load the stored conversation for [conversationId].
  ///
  /// The repository was a constructor parameter this controller never
  /// read: every turn was written to a screen and to nothing else, so
  /// leaving the chat threw the conversation away. This is the read
  /// half.
  ///
  /// A failed read leaves the chat EMPTY and logs metadata — a broken
  /// or half-written local document must not make the tutor
  /// unopenable. Idempotent, and it never overwrites messages a turn
  /// already produced while the read was in flight.
  Future<void> restore() async {
    if (_restoreStarted) return;
    _restoreStarted = true;
    final result = await repository.get(conversationId);
    final TutorConversation? conversation = switch (result) {
      Success(:final value) => value,
      Failure(:final error) => _onRestoreFailure(error),
    };
    if (conversation == null) return;
    _conversationCreatedAt = conversation.createdAt;
    _restoredLocaleTag = conversation.locale;
    if (_messages.isNotEmpty) return;
    _messages.addAll(conversation.messages);
    _emit();
  }

  /// N1 (R33) — write the current messages to the local store.
  ///
  /// Only what [TutorConversation] already models is written: the id,
  /// the two timestamps, the locale, the status and the messages. The
  /// optional `title` stays null on purpose — deriving one from the
  /// student's first line would copy message text into a summary field
  /// the chat never asked for.
  Future<void> persist() async {
    final now = DateTime.now().toUtc();
    final createdAt = _conversationCreatedAt ??= now;
    final result = await repository.save(
      TutorConversation(
        schemaVersion: TutorConversationCodec.supportedSchemaVersion,
        id: conversationId,
        createdAt: createdAt,
        updatedAt: now,
        locale: _restoredLocaleTag ?? localeTag,
        status: TutorConversationStatus.active,
        messages: List<TutorMessage>.unmodifiable(_messages),
      ),
    );
    if (result case Failure(:final error)) {
      logger.warning(
        'tutor.conversation.persist_failed',
        fields: <String, Object?>{
          'conversation_id': conversationId.value,
          'failure_code': error.code,
          'message_count': _messages.length,
        },
      );
    }
  }

  TutorConversation? _onRestoreFailure(AppFailure failure) {
    logger.warning(
      'tutor.conversation.restore_failed',
      fields: <String, Object?>{
        'conversation_id': conversationId.value,
        'failure_code': failure.code,
      },
    );
    return null;
  }

  @override
  void setDraft(String value) {
    if (draft == value) return;
    draft = value;
    _emit();
  }

  @override
  void send() => _submit(draft.trim());

  /// Dispatches one turn for [text], remembering it so [retry] can re-send
  /// the same question after the draft has been cleared.
  void _submit(String text) {
    if (text.isEmpty) return;
    _lastSubmittedText = text;
    final produced = turnRequestFactory(text);
    if (produced case Failure<TutorTurnRequest>(:final error)) {
      // Refused on the request path: nothing is dispatched, so the
      // orchestrator never creates a gateway. The draft is kept on
      // purpose — the student can grant consent and resend the text.
      _refuse(error.code);
      return;
    }
    final request = produced.valueOrNull!;
    final userMessage = _userMessage(text);
    _messages.add(userMessage);
    draft = '';
    status = TutorTurnStatus.assemblingContext;
    responseText = '';
    failureCode = null;
    _answerAppended = false;
    _emit();
    unawaited(orchestrator.dispatch(SendTutorMessage(request)));
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
      _resend();
      return;
    }
    cancel();
    Future<void>.delayed(Duration.zero, _resend);
  }

  /// What "Retry" re-sends: whatever the student has typed since the
  /// failure, and otherwise the question that failed.
  ///
  /// The second half is the fix for MAJOR M2 — every terminal status is a
  /// state in which [draft] has already been cleared by [_submit], so the
  /// old `send()` fell straight through its own `text.isEmpty` guard and
  /// the button did nothing, said nothing, forever.
  void _resend() {
    final typed = draft.trim();
    _submit(typed.isEmpty ? _lastSubmittedText : typed);
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

  /// Surfaces a request-path refusal ([turnRequestFactory] returned a
  /// [Failure]) as terminal, localisable state. The orchestrator is never
  /// touched, because nothing was — or could be — sent.
  void _refuse(String code) {
    final isConsent = code == tutorModelUseConsentMissingCode;
    final kind = isConsent ? TutorBannerKind.consent : TutorBannerKind.error;
    if (isConsent) {
      status = TutorTurnStatus.consentRevoked;
    } else {
      status = TutorTurnStatus.failed;
    }
    responseText = '';
    failureCode = code;
    final nextBanners = <TutorBannerKind>[];
    if (!isOnline) nextBanners.add(TutorBannerKind.offline);
    nextBanners.add(kind);
    banners = List<TutorBannerKind>.unmodifiable(nextBanners);
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

  TutorMessage _tutorMessage(List<TutorContentBlock> blocks) {
    final createdAt = DateTime.now().toUtc();
    return TutorMessage(
      id: TutorMessageId('t-${createdAt.microsecondsSinceEpoch}'),
      role: TutorMessageRole.tutor,
      createdAt: createdAt,
      sequence: _messages.length,
      deliveryState: TutorMessageDeliveryState.complete,
      blocks: blocks,
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
  // NOT `tutorOrchestratorProvider` (the boot value, whose gateway factory
  // is the local stub): the turn orchestrator re-composes the same pipeline
  // with the consent- and account-aware gateway selection (R9/2).
  final orchestrator = ref.watch(tutorTurnOrchestratorProvider);
  final repository = ref.watch(tutorConversationRepositoryProvider);
  final controller = DefaultTutorChatController(
    orchestrator: orchestrator,
    repository: repository,
    conversationId: TutorConversationId('preview'),
    requestIdFactory: _defaultRequestId,
    // `ref.read`, not `ref.watch`: the consent value is re-read on EVERY
    // send, so a revocation made mid-session takes effect on the next turn
    // without rebuilding the controller (and losing the conversation).
    turnRequestFactory: (text) => buildTutorTurnRequest(
      message: text,
      consent: ref.read(tutorConsentControllerProvider),
    ),
    onChanged: (_) {},
    // `ref.read`, for the same reason the consent value is read late:
    // a language change must not rebuild the controller and drop the
    // conversation. The tag is only stamped on a NEW envelope anyway.
    localeTag: ref.read(effectiveLocaleProvider).languageCode,
    logger: ref.read(appLoggerProvider),
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

/// Builds the preview conversation's turn request with the CALLER's consent
/// value. It is deliberately private and only reachable through
/// [buildTutorTurnRequest], so no call site can construct a turn request
/// with a consent value the student did not actually give.
TutorTurnRequest _previewTurnRequest(String text, TutorConsent consent) {
  return TutorTurnRequest(
    requestId: _defaultRequestId(),
    conversationId: TutorConversationId('preview'),
    message: text,
    createdAt: DateTime.now().toUtc(),
    consent: consent,
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
}

/// Build a `TutorContextAssembler` for the preview conversation. The
/// fields list is empty — the preview path does not surface real
/// student context.
TutorContextAssembler buildPreviewAssembler() => const TutorContextAssembler();

/// Build a knowledge retriever backed by the empty index (preview only).
KnowledgeRetriever buildPreviewRetriever() =>
    KnowledgeRetriever(index: const KnowledgeIndex.empty());
