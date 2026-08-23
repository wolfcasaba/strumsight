/// Community post composer state machine (E09-R12, brief §5.1–§5.3,
/// A1 / A3 / A5 / A6 / A7).
///
/// The controller is the *only* place where the composer's mutable
/// state lives. It is a Riverpod ``AsyncNotifier`` so the screen can
/// reactively re-render on every text-field keystroke (the existing
/// ``CommunityRelationshipController`` precedent).
///
/// **State machine (brief §1):**
///
/// ``editing`` ─submit─▶ ``submitting`` ─ack─▶ ``success`` (and the
///                                   draft is cleared)
///                              │
///                              └─nack/exception─▶ ``failure`` (and
///                                                   the draft and
///                                                   body are
///                                                   preserved — A5).
///
/// **Stable mutation-ID (brief §5.2):** the controller generates the
/// idempotency key on the FIRST draft save, persists it with the
/// draft in [CommunityDraftStore], and re-uses it for every submit
/// attempt. The outbox keeps its own copy, so a kill between submit
/// and drain does not lose the key.
///
/// **No silent success (brief §5.1 / A1):** the controller never
/// publishes ``success`` before the outbox's drain report says so.
/// Offline / network failure flips the state to ``failure`` with the
/// user's draft body untouched.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../data/local/community_draft_store.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/post_repository.dart';
import '../outbox/community_outbox.dart';

/// The four discrete states the composer UI can be in. The
/// discriminated enum is the source of truth — UI code switches on
/// this directly, no flag combinations to misinterpret.
enum PostComposerStatus {
  /// User is actively editing the draft.
  editing,

  /// Submit is in flight — text-field is read-only, send button is
  /// disabled, a "Közzététel..." spinner is visible.
  submitting,

  /// Submit succeeded — the post is acknowledged server-side. The
  /// draft is cleared. UI surfaces a "Sikeresen közzétéve"
  /// confirmation.
  success,

  /// Submit failed — the draft is preserved exactly as the user left
  /// it (A5), the idempotency key is preserved for the retry, the
  /// error is surfaced for the user to read.
  failure,
}

/// Immutable snapshot of the composer's state. Every mutation emits
/// a fresh copy so Riverpod's reference-equality triggers the UI
/// rebuilds.
class PostComposerState {
  const PostComposerState({
    required this.body,
    required this.audience,
    required this.sharePreview,
    required this.sourceArtifactJson,
    required this.idempotencyKey,
    required this.status,
    required this.lastError,
    required this.lastSubmittedAt,
    required this.isSubmitting,
  });

  /// Build the initial composer state for a fresh composer session.
  factory PostComposerState.initial({
    required Map<String, Object?> sourceArtifactJson,
    CommunityAudience audience = CommunityAudience.followers,
    SharePreview sharePreview = const SharePreview(),
  }) {
    return PostComposerState(
      body: null,
      audience: audience,
      sharePreview: sharePreview,
      sourceArtifactJson: Map<String, Object?>.unmodifiable(sourceArtifactJson),
      idempotencyKey: null,
      status: PostComposerStatus.editing,
      lastError: null,
      lastSubmittedAt: null,
      isSubmitting: false,
    );
  }

  /// The post body the user is typing. Null when the body is empty
  /// (matches the [CommunityPost.body] nullable contract).
  final String? body;

  /// The audience the user has selected.
  final CommunityAudience audience;

  /// The field-level share toggles the user has flipped.
  final SharePreview sharePreview;

  /// The serialized source artifact the post will reference.
  final Map<String, Object?> sourceArtifactJson;

  /// The stable, client-generated idempotency key for this composer
  /// session. Null until the first save — a draft the user has not
  /// typed into yet has no key.
  final String? idempotencyKey;

  /// The discrete UI state.
  final PostComposerStatus status;

  /// The most recent submit failure. Null when the composer has not
  /// failed yet, or after a successful submit clears it.
  final AppFailure? lastError;

  /// Wall-clock timestamp of the last successful submit.
  final DateTime? lastSubmittedAt;

  /// True while a submit is in flight. The screen disables its
  /// submit button while this is true — the §6.1 measure-matrix A3
  /// invariant.
  final bool isSubmitting;

  PostComposerState copyWith({
    Object? body = _sentinel,
    CommunityAudience? audience,
    SharePreview? sharePreview,
    Map<String, Object?>? sourceArtifactJson,
    Object? idempotencyKey = _sentinel,
    PostComposerStatus? status,
    Object? lastError = _sentinel,
    DateTime? lastSubmittedAt,
    bool? isSubmitting,
  }) {
    return PostComposerState(
      body: identical(body, _sentinel) ? this.body : body as String?,
      audience: audience ?? this.audience,
      sharePreview: sharePreview ?? this.sharePreview,
      sourceArtifactJson: sourceArtifactJson ?? this.sourceArtifactJson,
      idempotencyKey: identical(idempotencyKey, _sentinel)
          ? this.idempotencyKey
          : idempotencyKey as String?,
      status: status ?? this.status,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as AppFailure?,
      lastSubmittedAt: lastSubmittedAt ?? this.lastSubmittedAt,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

const Object _sentinel = Object();

/// The Community post composer state machine.
class PostComposerController extends AsyncNotifier<PostComposerState> {
  @override
  Future<PostComposerState> build() async {
    final sourceArtifactJson = ref.read(composerSourceArtifactProvider);
    final draft = ref.read(communityDraftStoreProvider).readDraft();
    if (draft == null) {
      return PostComposerState.initial(sourceArtifactJson: sourceArtifactJson);
    }
    // Restore the persisted draft — including its stable idempotency
    // key (brief §5.2, A4). A user who typed, killed the app, and
    // re-opened the composer sees the same body, audience, toggles
    // and the same key, so the next submit is the same mutation.
    return PostComposerState.initial(
      sourceArtifactJson: sourceArtifactJson,
    ).copyWith(
      body: draft.body,
      audience: draft.audience,
      sharePreview: draft.sharePreview,
      idempotencyKey: draft.idempotencyKey,
    );
  }

  /// Update the body the user is typing. Persists the new draft
  /// through the [CommunityDraftStore] — this is the §5.3 "user's
  /// text is never lost" invariant.
  Future<void> updateBody(String? body) async {
    final current = state.value;
    if (current == null) return;
    if (current.isSubmitting) return;
    final next = current.copyWith(body: body);
    state = AsyncData(next);
    await _persistDraft(next);
  }

  /// Update the audience. Persists through the [CommunityDraftStore].
  Future<void> updateAudience(CommunityAudience audience) async {
    final current = state.value;
    if (current == null) return;
    if (current.isSubmitting) return;
    final next = current.copyWith(audience: audience);
    state = AsyncData(next);
    await _persistDraft(next);
  }

  /// Flip a single [SharePreview] flag. Persists through the
  /// [CommunityDraftStore].
  Future<void> setSharePreviewFlag({
    required bool includeChordTimeline,
    required bool includeStrumPattern,
    required bool includeTempo,
    required bool includeStreakDays,
    required bool includeBestScore,
  }) async {
    final current = state.value;
    if (current == null) return;
    if (current.isSubmitting) return;
    final next = current.copyWith(
      sharePreview: SharePreview(
        includeChordTimeline: includeChordTimeline,
        includeStrumPattern: includeStrumPattern,
        includeTempo: includeTempo,
        includeStreakDays: includeStreakDays,
        includeBestScore: includeBestScore,
      ),
    );
    state = AsyncData(next);
    await _persistDraft(next);
  }

  /// Submit the draft. The composer's "publish" path:
  ///
  /// 1. If a submit is in flight, the call is a no-op (A3 — double-
  ///    tap does not fire two mutations).
  /// 2. Enqueue the draft into the outbox (the draft's stable key
  ///    is the mutation key, brief §5.2).
  /// 3. Drain the outbox — this is the single network attempt.
  /// 4. On acknowledged → state = success, draft cleared.
  /// 5. On exception / not-acknowledged → state = failure, draft
  ///    preserved (A5).
  Future<void> submit() async {
    final current = state.value;
    if (current == null) return;
    if (current.isSubmitting) return;
    final draft = _draftFromState(current);
    if (draft == null) return;

    state = AsyncData(
      current.copyWith(
        status: PostComposerStatus.submitting,
        isSubmitting: true,
        lastError: null,
      ),
    );

    try {
      await ref.read(communityOutboxProvider).enqueue(draft: draft);
      final report = await ref.read(communityOutboxProvider).drain();
      final next = state.value;
      if (next == null) return;
      if (report.acknowledged.contains(draft.idempotencyKey)) {
        // Brief §5.1 — server confirmed. The post is live. Drop the
        // draft so a fresh composer session starts blank.
        await ref.read(communityDraftStoreProvider).clearDraft();
        state = AsyncData(
          PostComposerState.initial(
            sourceArtifactJson: next.sourceArtifactJson,
          ).copyWith(
            status: PostComposerStatus.success,
            lastSubmittedAt: DateTime.now(),
          ),
        );
        return;
      }
      // The drain did NOT acknowledge this post — it left the record
      // in the pending queue. Surface a failure so the user knows
      // the post is NOT yet live (no false success, brief §5.1).
      state = AsyncData(
        next.copyWith(
          status: PostComposerStatus.failure,
          isSubmitting: false,
          lastError: const AppFailure(
            code: FailureCode.networkUnavailable,
            message: 'A poszt nem került elküldésre — próbáld újra.',
          ),
        ),
      );
    } on AppFailure catch (failure) {
      // A network-class failure left the post in pending with its
      // idempotency key intact; the next drain will retry it. A5 —
      // the user's text is preserved.
      final next = state.value;
      if (next == null) return;
      state = AsyncData(
        next.copyWith(
          status: PostComposerStatus.failure,
          isSubmitting: false,
          lastError: failure,
        ),
      );
    } on Object catch (error, stackTrace) {
      final next = state.value;
      if (next == null) return;
      state = AsyncData(
        next.copyWith(
          status: PostComposerStatus.failure,
          isSubmitting: false,
          lastError: AppFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Drop the in-progress draft (the "discard" affordance). The
  /// next [build] returns a fresh initial state.
  Future<void> discard() async {
    final current = state.value;
    if (current == null) return;
    if (current.isSubmitting) return;
    await ref.read(communityDraftStoreProvider).clearDraft();
    state = AsyncData(
      PostComposerState.initial(sourceArtifactJson: current.sourceArtifactJson),
    );
  }

  // ---- internal helpers ------------------------------------------------

  /// Build a [CommunityDraft] from the current state, generating the
  /// idempotency key on the first save (brief §5.2). Returns ``null``
  /// when the body is empty AND the source artifact is not sufficient
  /// on its own — the composer never enqueues an empty post.
  CommunityDraft? _draftFromState(PostComposerState current) {
    final sourceArtifactJson = current.sourceArtifactJson;
    if (current.body == null && _isEmptyArtifact(sourceArtifactJson)) {
      return null;
    }
    final existingKey = current.idempotencyKey;
    final now = DateTime.now();
    if (existingKey != null) {
      return CommunityDraft(
        idempotencyKey: existingKey,
        body: current.body,
        audience: current.audience,
        sourceArtifactJson: sourceArtifactJson,
        sharePreview: current.sharePreview,
        lastEditedAt: now,
      );
    }
    return CommunityDraft.fresh(
      body: current.body ?? '',
      audience: current.audience,
      sourceArtifactJson: sourceArtifactJson,
      sharePreview: current.sharePreview,
      now: now,
    );
  }

  bool _isEmptyArtifact(Map<String, Object?> artifact) {
    if (artifact.isEmpty) return true;
    // An artifact with a real schemaVersion or type discriminator
    // is "non-empty" — it carries the source identity even without
    // a body.
    return artifact['schemaVersion'] is! int && artifact['type'] is! String;
  }

  Future<void> _persistDraft(PostComposerState current) async {
    final draft = _draftFromState(current);
    if (draft == null) {
      // Empty body + empty artifact — nothing to persist.
      await ref.read(communityDraftStoreProvider).clearDraft();
      return;
    }
    // Refresh the persisted key on the first save (the controller
    // didn't have one yet) so subsequent reads find the same draft.
    if (current.idempotencyKey == null) {
      state = AsyncData(current.copyWith(idempotencyKey: draft.idempotencyKey));
    }
    await ref.read(communityDraftStoreProvider).saveDraft(draft);
  }
}

/// Provider for the per-user Community draft store.
///
/// The provider re-builds on auth changes — a fresh
/// [CommunityDraftStore] is bound to the new user's storage key on
/// sign-in, and the previous user's draft stays in their own key
/// (the §10 logout-policy decision: same user, same draft; different
/// user, different draft).
final communityDraftStoreProvider = Provider<CommunityDraftStore>((ref) {
  final user = ref.watch(authControllerProvider).value;
  if (user == null) {
    // The composer should never be on screen while logged out — the
    // screen is gated on `isSignedInProvider`. The fallback is a
    // store bound to userId 0; writes go to a never-read partition
    // and reads return null. The controller treats null the same way
    // it treats a fresh install.
    return CommunityDraftStore.open(
      store: ref.read(communityKeyValueStoreProvider),
      logger: ref.read(communityLoggerProvider),
      userId: 0,
    );
  }
  return CommunityDraftStore.open(
    store: ref.read(communityKeyValueStoreProvider),
    logger: ref.read(communityLoggerProvider),
    userId: user.id,
  );
});

/// Provider for the Community outbox. Production wires
/// [LocalCommunityOutbox]; tests override with a fake.
final communityOutboxProvider = Provider<CommunityOutbox>((ref) {
  final repo = ref.read(communityPostRepositoryProvider);
  return LocalCommunityOutbox(
    repository: repo,
    store: ref.read(communityKeyValueStoreProvider),
    logger: ref.read(communityLoggerProvider),
  );
});

/// Provider for the post composer controller. The source artifact
/// the post will reference is passed in by the entry-point that
/// pushes the composer route.
final postComposerControllerProvider =
    AsyncNotifierProvider.autoDispose<
      PostComposerController,
      PostComposerState
    >(PostComposerController.new);

/// Provider for the source artifact the composer is editing. The
/// entry-point route (future Kör 14 feed card action) overrides this
/// with the [ShareArtifact.toJson] of the artifact the user picked.
/// The default below is an empty map.
final composerSourceArtifactProvider = Provider<Map<String, Object?>>(
  (ref) => const <String, Object?>{},
);

/// Provider for the [CommunityPostRepository] — overridden in tests
/// with a fake; production wires the Kör 11
/// ``HttpCommunityPostRepository`` (not yet on disk).
final communityPostRepositoryProvider = Provider<CommunityPostRepository>((
  ref,
) {
  throw StateError(
    'communityPostRepositoryProvider must be overridden in production '
    'with the Kör 11 HttpCommunityPostRepository; tests inject a fake '
    'via dependency_overrides.',
  );
});

/// Provider for the shared [KeyValueStore] — overridden in tests
/// with an in-memory implementation; production wires the platform
/// SharedPreferences-backed store.
final communityKeyValueStoreProvider = Provider<KeyValueStore>((ref) {
  throw StateError(
    'communityKeyValueStoreProvider must be overridden in production '
    'with the platform SharedPreferences-backed store; tests inject an '
    'in-memory implementation via dependency_overrides.',
  );
});

/// Provider for the [AppLogger] used by the draft store and outbox.
final communityLoggerProvider = Provider<AppLogger>((ref) {
  throw StateError(
    'communityLoggerProvider must be overridden in production with the '
    'shared AppLogger; tests inject a recording implementation via '
    'dependency_overrides.',
  );
});
