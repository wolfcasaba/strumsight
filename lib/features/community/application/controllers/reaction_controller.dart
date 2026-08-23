/// Community post reactions controller (E09-R15, brief §1 / §5 / §6).
///
/// The controller is the *only* place where the caller's per-post
/// reaction state is mutated. It is a Riverpod ``Notifier`` so the
/// screen can reactively re-render on every state transition.
///
/// **Toggle semantics (§5.2):** tapping the reaction the viewer
/// already holds clears it; tapping a different reaction switches
/// to it; tapping a new reaction sets it. The toggle is computed
/// from the EFFECTIVE state (optimistic wins over server), so a
/// rapid double-tap cannot leave the UI in a contradictory state.
///
/// **Optimistic update + rollback (A6):** the caller's intent is
/// published synchronously to the controller state BEFORE the
/// repository call. On success, the optimistic value is committed
/// as the new server-confirmed value. On failure, the optimistic
/// override is cleared and the previous server value is restored.
///
/// **Last-intent-wins (§6 A4):** a mutation ID counter per
/// ``ContentId`` tracks the latest intent the user has expressed.
/// A stale network response (one whose mutation ID is no longer
/// the latest) is dropped — its result cannot overwrite the
/// newer intent. The brief §6.1 "real-user-intent" cell is the
/// steady-state, not which-tx-wins: this rule keeps the
/// rapid-double-tap scenario consistent with what the user
/// actually wanted.
///
/// **Idempotency key (§5.2):** each mutation gets a fresh
/// client-side key — the (post, viewer) UNIQUE constraint is the
/// canonical idempotency surface server-side (the Kör 5 contract),
/// the client-side key is for the wire audit log.
///
/// **No learning reward event (§6 A7):** the controller has no
/// call into the gamification module — the cross-feature adapter
/// boundary is the same E08-R26 invariant the post-create /
/// follow / unfollow paths respect.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/logging/logger_provider.dart';
import '../../domain/entities/community_reaction.dart';
import '../../domain/repositories/post_repository.dart';
import '../../domain/value_objects/content_id.dart';
// The post-repository provider lives in the post-composer
// controller — the Kör 5 contract owner. This round adds a
// SECOND consumer (the reaction controller); the wiring stays in
// one place to avoid the same provider being defined twice.
import 'post_composer_controller.dart' show communityPostRepositoryProvider;

/// The per-post reaction view the controller holds.
///
/// Mirrors the Kör 6 ``RelationshipView`` shape: ``server`` is the
/// value the most recent refetch confirmed, ``optimistic`` is the
/// value the controller has just emitted (BEFORE the network
/// call), and ``effective`` is what the UI should display.
class ReactionView {
  const ReactionView({required this.server, this.optimistic});

  /// Build an empty view (the viewer has not reacted, the server
  /// has not reported a state). Used as the initial value when
  /// the controller is seeded with no server data yet.
  const ReactionView.empty() : server = null, optimistic = null;

  /// The reaction kind the server confirmed (the most recent
  /// ``seedReaction`` / post-fetch response).
  final ReactionKind? server;

  /// The optimistic override, if the controller has an in-flight
  /// mutation for this post. ``null`` means "trust the server
  /// value".
  final ReactionKind? optimistic;

  /// The reaction kind the UI should display — optimistic wins
  /// when present.
  ReactionKind? get effective => optimistic ?? server;

  /// True when the optimistic override differs from the server
  /// value (an in-flight mutation has not yet been committed).
  bool get isOptimistic => optimistic != null && optimistic != server;

  ReactionView copyWith({
    Object? server = _sentinel,
    Object? optimistic = _sentinel,
    bool clearOptimistic = false,
  }) {
    return ReactionView(
      server: identical(server, _sentinel)
          ? this.server
          : server as ReactionKind?,
      optimistic: clearOptimistic
          ? null
          : (identical(optimistic, _sentinel)
                ? this.optimistic
                : optimistic as ReactionKind?),
    );
  }
}

const Object _sentinel = Object();

/// Immutable snapshot of the controller's state. The map is keyed
/// by ``ContentId`` — one ``ReactionView`` per post the screen has
/// seeded. A missing key means "the controller has not seen this
/// post yet" — the screen can fall through to the post's own
/// ``viewerState.myReaction`` value as the fallback.
class ReactionState {
  const ReactionState({required this.reactionsByPost, required this.lastError});

  const ReactionState.initial()
    : reactionsByPost = const <ContentId, ReactionView>{},
      lastError = null;

  /// Per-post reaction view, keyed by the post's ``ContentId``.
  final Map<ContentId, ReactionView> reactionsByPost;

  /// The most recent failure, surfaced for a banner / inline
  /// message. Cleared on the next successful mutation.
  final AppFailure? lastError;

  ReactionState copyWith({
    Map<ContentId, ReactionView>? reactionsByPost,
    Object? lastError = _sentinel,
  }) {
    return ReactionState(
      reactionsByPost: reactionsByPost ?? this.reactionsByPost,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as AppFailure?,
    );
  }
}

/// Discriminated outcome of a ``setReaction`` mutation.
sealed class ReactionSubmitResult {
  const ReactionSubmitResult();
  const factory ReactionSubmitResult.success() = ReactionSubmitSuccess;
  const factory ReactionSubmitResult.failure(AppFailure error) =
      ReactionSubmitFailure;
  const factory ReactionSubmitResult.superseded() = ReactionSubmitSuperseded;
}

class ReactionSubmitSuccess implements ReactionSubmitResult {
  const ReactionSubmitSuccess();
}

class ReactionSubmitFailure implements ReactionSubmitResult {
  const ReactionSubmitFailure(this.error);
  final AppFailure error;
}

/// A newer intent has superseded this mutation's intent — the
/// caller should NOT surface an error to the user because the
/// newer mutation is already in flight and the user has moved on.
/// This is the §6 A4 last-intent-wins path: the rapid double-tap
/// does NOT produce a stale error message after a stale network
/// failure.
class ReactionSubmitSuperseded implements ReactionSubmitResult {
  const ReactionSubmitSuperseded();
}

/// The reactions state machine. The state is keyed off the
/// ``CommunityPostRepository.setReaction`` method (the Kör 5 wire
/// contract); the controller does NOT duplicate the lifecycle logic
/// — the optimistic UI is a layer on top of the repository's
/// idempotency-aware contract.
class ReactionController extends Notifier<ReactionState> {
  CommunityPostRepository get _repo =>
      ref.read(communityPostRepositoryProvider);

  AppLogger get _logger => ref.read(appLoggerProvider);

  @override
  ReactionState build() {
    return const ReactionState.initial();
  }

  /// Counter for client-side mutation IDs. Per-post so a
  /// mutation on post A does not bump the ID for post B's
  /// in-flight mutation. The mutation ID is the §6 A4
  /// last-intent-wins guard: a response whose ID is no longer
  /// the latest for its post is dropped.
  final Map<ContentId, int> _mutationIdByPost = <ContentId, int>{};

  /// Idempotency-key counter (separate from the mutation-ID
  /// counter). The key is what the wire contract carries; the
  /// ID is the in-controller last-intent-wins guard. They are
  /// distinct because the wire key cannot collide across posts,
  /// but the mutation-ID-per-post only needs to be unique within
  /// a post.
  int _idempotencyCounter = 0;

  String _newIdempotencyKey() {
    _idempotencyCounter += 1;
    return 'e09-r15-$_idempotencyCounter-${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Seed the server-confirmed reaction for a post. The Kör 13/14
  /// feed path or a future per-post-fetch calls this when it
  /// learns the server's view of the caller's reaction. The
  /// value is the server-confirmed ``ReactionKind?`` (null =
  /// no reaction).
  void seedReaction(ContentId postId, ReactionKind? serverValue) {
    final current = state;
    final existing = current.reactionsByPost[postId];
    final next = Map<ContentId, ReactionView>.from(current.reactionsByPost);
    // Preserving any in-flight optimistic override is the call-
    // site responsibility (a stale override would overwrite the
    // server value; clearing it here would undo an in-flight
    // user tap). When the controller has no override, this is a
    // pure seed.
    next[postId] = (existing ?? const ReactionView.empty()).copyWith(
      server: serverValue,
    );
    state = current.copyWith(reactionsByPost: next);
  }

  /// Toggle / set the viewer's reaction on [postId].
  ///
  /// The [kind] is the kind the user JUST tapped. The toggle
  /// semantics are:
  /// * tapping the kind the viewer ALREADY holds (effective)
  ///   clears the reaction (``null`` is sent);
  /// * tapping any other kind sets the reaction to that kind.
  ///
  /// Returns the discriminated outcome — the screen surfaces
  /// ``success`` silently (the optimistic UI is already
  /// visible), ``failure`` as a toast, and ``superseded``
  /// silently (a newer intent has taken over).
  Future<ReactionSubmitResult> setReaction(
    ContentId postId,
    ReactionKind kind,
  ) async {
    final current = state;
    final view = current.reactionsByPost[postId] ?? const ReactionView.empty();
    final effective = view.effective;
    // §5.2 toggle: tapping the kind the viewer already holds
    // (optimistic OR server) clears it. Otherwise the new kind
    // replaces it.
    final intent = effective == kind ? null : kind;

    // Bump the per-post mutation ID BEFORE the network call —
    // any in-flight response for this post is now stale.
    final myMutationId = (_mutationIdByPost[postId] ?? 0) + 1;
    _mutationIdByPost[postId] = myMutationId;

    // Publish the optimistic state synchronously — the UI
    // flips its reaction icon to the new kind immediately.
    _writeReaction(postId, view, optimistic: intent);
    state = state.copyWith(lastError: null);

    final idempotencyKey = _newIdempotencyKey();
    try {
      // The repository accepts ``kind: Object?`` (the Kör 5 wire
      // contract — the implementation passes a wire string);
      // here we hand it the enum directly so the fake / future
      // HTTP repo can decode it via the wire value.
      await _repo.setReaction(
        postId: postId,
        kind: intent,
        idempotencyKey: idempotencyKey,
      );
      // Last-intent-wins: if a newer mutation has landed since
      // we kicked off, our result is stale — drop it. The newer
      // mutation's network call is in flight and its outcome
      // is the source of truth for the UI.
      if (_mutationIdByPost[postId] != myMutationId) {
        // §6 A4: stale result is silently dropped — the user
        // has expressed a newer intent.
        return const ReactionSubmitSuperseded();
      }
      _commitReaction(postId, view, value: intent);
      return const ReactionSubmitSuccess();
    } on AppFailure catch (failure) {
      // Last-intent-wins: same guard for the failure path.
      if (_mutationIdByPost[postId] != myMutationId) {
        return const ReactionSubmitSuperseded();
      }
      _logger.warning(
        'community.reaction.setReaction.failure',
        fields: {'postId': postId.value},
      );
      _rollbackReaction(postId, view);
      state = state.copyWith(lastError: failure);
      return ReactionSubmitFailure(failure);
    } on Object catch (error, stackTrace) {
      if (_mutationIdByPost[postId] != myMutationId) {
        return const ReactionSubmitSuperseded();
      }
      _logger.error(
        'community.reaction.setReaction.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'postId': postId.value},
      );
      _rollbackReaction(postId, view);
      final failure = UnknownFailure(
        code: FailureCode.unknown,
        cause: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(lastError: failure);
      return ReactionSubmitFailure(failure);
    }
  }

  /// Drop the last error (the user dismissed the toast / banner).
  void clearError() {
    if (state.lastError == null) return;
    state = state.copyWith(lastError: null);
  }

  // ---- internal state mutations --------------------------------------

  void _writeReaction(
    ContentId postId,
    ReactionView view, {
    required ReactionKind? optimistic,
  }) {
    final current = state;
    final next = Map<ContentId, ReactionView>.from(current.reactionsByPost);
    next[postId] = view.copyWith(optimistic: optimistic);
    state = current.copyWith(reactionsByPost: next);
  }

  void _commitReaction(
    ContentId postId,
    ReactionView view, {
    required ReactionKind? value,
  }) {
    final current = state;
    final next = Map<ContentId, ReactionView>.from(current.reactionsByPost);
    // The optimistic value becomes the new server-confirmed
    // value. The override is cleared so a subsequent
    // ``effective`` read returns the committed state.
    next[postId] = ReactionView(server: value);
    state = current.copyWith(reactionsByPost: next);
  }

  void _rollbackReaction(ContentId postId, ReactionView view) {
    final current = state;
    final next = Map<ContentId, ReactionView>.from(current.reactionsByPost);
    // Restore the previous view exactly — server value back to
    // its prior state, optimistic override cleared.
    next[postId] = view.copyWith(clearOptimistic: true);
    state = current.copyWith(reactionsByPost: next);
  }
}

/// Provider for the [ReactionController]. The screen reads this
/// directly; the repository dependency is pulled from
/// [communityPostRepositoryProvider], which production wires to
/// the future Kör 16 ``HttpCommunityPostRepository`` (D6 deferral)
/// and tests override with a recording fake.
final reactionControllerProvider =
    NotifierProvider<ReactionController, ReactionState>(ReactionController.new);
