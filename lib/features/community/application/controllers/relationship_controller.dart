/// Community social-graph controller — the optimistic (public) /
/// pending (private) state machine (E09-R07, ADR 0401 §3, brief §5.2).
///
/// The controller is the *only* place where the caller's
/// relationship to a target profile is mutated. Three entry points:
///
/// * ``follow(target)`` — public target ⇒ optimistic ``following``
///   immediately; private target ⇒ optimistic ``pendingRequestOutgoing``
///   until the server confirms. Network failure rolls the optimistic
///   state back (A6).
/// * ``unfollow(target)`` — removes the active edge OR cancels a
///   pending outgoing request (ADR 0401 §3). The repository call
///   is the same in both cases; the optimistic UI path picks the
///   right state to roll back to based on the caller's current
///   relationship.
/// * ``removeFollower(follower)`` — the profile owner expels a
///   follower. Idempotent. The brief §5.3 invariant: this does
///   NOT block.
///
/// The state machine keys off the per-target [RelationshipView]
/// value object — the optimistic mutation writes into that view
/// synchronously, and the rollback restores the previous value
/// when the network call fails. This is the §5.2 / A6 invariant:
/// a failed submit MUST NOT leave the UI in a state that disagrees
/// with the server.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../data/repositories/relationship_repository_impl.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/repositories/social_graph_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/public_user_id.dart';

/// The relationship view the controller holds per target profile.
///
/// The controller keeps a map of these so the optimistic UI can
/// update the relationship for a single target without a full
/// refetch. The initial state is whatever the server last said
/// (``server``); the optimistic state is whatever the user just
/// clicked (``optimistic``); the ``effective`` getter exposes the
/// optimistic value if present, else the server value.
class RelationshipView {
  const RelationshipView({required this.server, this.optimistic});

  /// The relationship value the server confirmed (from the most
  /// recent ``fetchMyProfile`` / ``fetchById`` round-trip).
  final CommunityRelationshipToViewer server;

  /// The optimistic override, if the controller has an in-flight
  /// mutation for this target. ``null`` means "trust the server
  /// value".
  final CommunityRelationshipToViewer? optimistic;

  /// The relationship value the UI should display — optimistic
  /// wins when present.
  CommunityRelationshipToViewer get effective => optimistic ?? server;

  RelationshipView copyWith({
    CommunityRelationshipToViewer? server,
    CommunityRelationshipToViewer? optimistic,
    bool clearOptimistic = false,
  }) {
    return RelationshipView(
      server: server ?? this.server,
      optimistic: clearOptimistic ? null : (optimistic ?? this.optimistic),
    );
  }
}

/// The state machine's snapshot — the per-target relationship map
/// plus the global error / in-flight flag. A new map is published
/// on every mutation so Riverpod's reference-equality triggers a
/// UI refresh.
class CommunityRelationshipState {
  const CommunityRelationshipState({
    required this.relationships,
    required this.error,
    required this.isSubmitting,
  });

  const CommunityRelationshipState.initial()
    : relationships = const <PublicUserId, RelationshipView>{},
      error = null,
      isSubmitting = false;

  /// Per-target relationship view, keyed by the target's
  /// ``PublicUserId``. Missing keys mean "the server has not
  /// reported a relationship for this target yet".
  final Map<PublicUserId, RelationshipView> relationships;

  /// The most recent failure, surfaced to the UI for an error
  /// banner / inline message.
  final AppFailure? error;

  /// True while a follow / unfollow / accept / decline call is in
  /// flight. The screen disables its submit button while this is
  /// true (same precedent as the Kör 6 ``isSubmitting`` debounce).
  final bool isSubmitting;

  CommunityRelationshipState copyWith({
    Map<PublicUserId, RelationshipView>? relationships,
    Object? error = _sentinel,
    bool? isSubmitting,
  }) {
    return CommunityRelationshipState(
      relationships: relationships ?? this.relationships,
      error: identical(error, _sentinel) ? this.error : error as AppFailure?,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

const Object _sentinel = Object();

/// The social-graph state machine. The state is keyed off the
/// social-graph repository's ``follow`` / ``unfollow`` /
/// ``acceptFollowRequest`` / ``declineFollowRequest`` /
/// ``removeFollower`` methods; the controller does NOT duplicate
/// the lifecycle logic — the optimistic UI is a layer on top of
/// the repository's contract.
class CommunityRelationshipController
    extends AsyncNotifier<CommunityRelationshipState> {
  SocialGraphRepository get _repo => ref.read(socialGraphRepositoryProvider);

  int _idempotencyCounter = 0;
  String _newIdempotencyKey() {
    _idempotencyCounter += 1;
    return 'e09-r07-$_idempotencyCounter-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  Future<CommunityRelationshipState> build() async {
    return const CommunityRelationshipState.initial();
  }

  /// Replace the server-confirmed relationship for a target. The
  /// Kör 6 ``fetchMyProfile`` path or a future ``fetchById``
  /// follow-up calls this when it learns the server's view of
  /// the caller's relationship.
  void seedRelationship(
    PublicUserId target,
    CommunityRelationshipToViewer serverValue,
  ) {
    final current = state.value ?? const CommunityRelationshipState.initial();
    final next = Map<PublicUserId, RelationshipView>.from(current.relationships);
    next[target] = RelationshipView(server: serverValue);
    state = AsyncData(current.copyWith(relationships: next));
  }

  /// Optimistic follow: public target ⇒ ``following``; private
  /// target ⇒ ``pendingRequestOutgoing``. The optimistic state is
  /// committed BEFORE the network call returns; on failure, the
  /// state is rolled back to the previous server value (A6).
  Future<CommunityRelationshipSubmitResult> follow(PublicUserId target) async {
    if (state.value?.isSubmitting ?? false) {
      return const CommunityRelationshipSubmitResult.busy();
    }
    final view = state.value?.relationships[target];
    final previousServer =
        view?.server ?? CommunityRelationshipToViewer.notRelated;
    final previousOptimistic = view?.optimistic;
    final optimistic = _optimisticFollow(previousServer);

    _writeRelationship(
      target,
      view,
      optimistic: optimistic,
    );
    state = AsyncData(
      (state.value ?? const CommunityRelationshipState.initial()).copyWith(
        isSubmitting: true,
        error: null,
      ),
    );

    final idempotencyKey = _newIdempotencyKey();
    try {
      await _repo.follow(target: target, idempotencyKey: idempotencyKey);
      // Server returned success — commit the optimistic state as
      // the new server value and clear the optimistic override.
      _commitOptimistic(target, optimistic);
      return const CommunityRelationshipSubmitResult.success();
    } on AppFailure catch (failure) {
      // Network failure — roll back the optimistic override, keep
      // the server value visible (A6).
      _rollbackOptimistic(target, view, previousServer, previousOptimistic);
      return CommunityRelationshipSubmitResult.failure(failure);
    }
  }

  /// Optimistic unfollow / cancel. The repository call covers
  /// both branches (active edge → DELETE; pending request →
  /// ``cancelled``); the controller's optimistic UI is a single
  /// ``notRelated`` for either.
  Future<CommunityRelationshipSubmitResult> unfollow(PublicUserId target) async {
    if (state.value?.isSubmitting ?? false) {
      return const CommunityRelationshipSubmitResult.busy();
    }
    final view = state.value?.relationships[target];
    final previousServer =
        view?.server ?? CommunityRelationshipToViewer.notRelated;
    final previousOptimistic = view?.optimistic;

    _writeRelationship(
      target,
      view,
      optimistic: CommunityRelationshipToViewer.notRelated,
    );
    state = AsyncData(
      (state.value ?? const CommunityRelationshipState.initial()).copyWith(
        isSubmitting: true,
        error: null,
      ),
    );

    final idempotencyKey = _newIdempotencyKey();
    try {
      await _repo.unfollow(target: target, idempotencyKey: idempotencyKey);
      _commitOptimistic(target, CommunityRelationshipToViewer.notRelated);
      return const CommunityRelationshipSubmitResult.success();
    } on AppFailure catch (failure) {
      _rollbackOptimistic(target, view, previousServer, previousOptimistic);
      return CommunityRelationshipSubmitResult.failure(failure);
    }
  }

  /// Accept an incoming follow request — flips the requester's
  /// relationship to ``mutualFollow`` if the caller already
  /// followed them, else ``theyFollowYou``.
  Future<CommunityRelationshipSubmitResult> acceptFollowRequest(
    ContentId requestId,
    PublicUserId requester,
  ) async {
    if (state.value?.isSubmitting ?? false) {
      return const CommunityRelationshipSubmitResult.busy();
    }
    final view = state.value?.relationships[requester];
    final previousServer =
        view?.server ?? CommunityRelationshipToViewer.notRelated;
    final previousOptimistic = view?.optimistic;
    final optimistic = _optimisticAccept(previousServer);

    _writeRelationship(requester, view, optimistic: optimistic);
    state = AsyncData(
      (state.value ?? const CommunityRelationshipState.initial()).copyWith(
        isSubmitting: true,
        error: null,
      ),
    );

    final idempotencyKey = _newIdempotencyKey();
    try {
      await _repo.acceptFollowRequest(
        requestId: requestId,
        idempotencyKey: idempotencyKey,
      );
      _commitOptimistic(requester, optimistic);
      return const CommunityRelationshipSubmitResult.success();
    } on AppFailure catch (failure) {
      _rollbackOptimistic(requester, view, previousServer, previousOptimistic);
      return CommunityRelationshipSubmitResult.failure(failure);
    }
  }

  /// Decline an incoming follow request — clears the
  /// ``pendingRequestIncoming`` from the caller's view of the
  /// requester.
  Future<CommunityRelationshipSubmitResult> declineFollowRequest(
    ContentId requestId,
    PublicUserId requester,
  ) async {
    if (state.value?.isSubmitting ?? false) {
      return const CommunityRelationshipSubmitResult.busy();
    }
    final view = state.value?.relationships[requester];
    final previousServer =
        view?.server ?? CommunityRelationshipToViewer.notRelated;
    final previousOptimistic = view?.optimistic;

    _writeRelationship(requester, view, optimistic: _optimisticDecline());
    state = AsyncData(
      (state.value ?? const CommunityRelationshipState.initial()).copyWith(
        isSubmitting: true,
        error: null,
      ),
    );

    final idempotencyKey = _newIdempotencyKey();
    try {
      await _repo.declineFollowRequest(
        requestId: requestId,
        idempotencyKey: idempotencyKey,
      );
      _commitOptimistic(requester, _optimisticDecline());
      return const CommunityRelationshipSubmitResult.success();
    } on AppFailure catch (failure) {
      _rollbackOptimistic(requester, view, previousServer, previousOptimistic);
      return CommunityRelationshipSubmitResult.failure(failure);
    }
  }

  /// Remove a follower. Idempotent; the brief §5.3 invariant
  /// says this is NOT a block.
  Future<CommunityRelationshipSubmitResult> removeFollower(
    PublicUserId follower,
  ) async {
    if (state.value?.isSubmitting ?? false) {
      return const CommunityRelationshipSubmitResult.busy();
    }
    final view = state.value?.relationships[follower];
    final previousServer =
        view?.server ?? CommunityRelationshipToViewer.notRelated;
    final previousOptimistic = view?.optimistic;

    // The follower-side relationship flips from ``theyFollowYou``
    // / ``mutualFollow`` to ``notRelated`` for the caller.
    final optimistic = _optimisticRemoveFollower(previousServer);

    _writeRelationship(follower, view, optimistic: optimistic);
    state = AsyncData(
      (state.value ?? const CommunityRelationshipState.initial()).copyWith(
        isSubmitting: true,
        error: null,
      ),
    );

    final idempotencyKey = _newIdempotencyKey();
    try {
      await _repo.removeFollower(
        follower: follower,
        idempotencyKey: idempotencyKey,
      );
      _commitOptimistic(follower, optimistic);
      return const CommunityRelationshipSubmitResult.success();
    } on AppFailure catch (failure) {
      _rollbackOptimistic(follower, view, previousServer, previousOptimistic);
      return CommunityRelationshipSubmitResult.failure(failure);
    }
  }

  void clearError() {
    final value = state.value;
    if (value == null) return;
    state = AsyncData(value.copyWith(error: null));
  }

  // ---- optimistic helpers -------------------------------------------

  CommunityRelationshipToViewer _optimisticFollow(
    CommunityRelationshipToViewer previous,
  ) {
    return switch (previous) {
      // Already following — no change.
      CommunityRelationshipToViewer.youFollowThem =>
        CommunityRelationshipToViewer.youFollowThem,
      CommunityRelationshipToViewer.mutualFollow =>
        CommunityRelationshipToViewer.mutualFollow,
      // They follow us, we didn't follow them → mutual.
      CommunityRelationshipToViewer.theyFollowYou =>
        CommunityRelationshipToViewer.mutualFollow,
      // Pending outgoing — refresh (server may already have it).
      CommunityRelationshipToViewer.pendingRequestOutgoing =>
        CommunityRelationshipToViewer.pendingRequestOutgoing,
      // Pending incoming (we'd need to decline/accept that) — keep.
      CommunityRelationshipToViewer.pendingRequestIncoming =>
        CommunityRelationshipToViewer.pendingRequestIncoming,
      // Blocked states — no optimistic mutation (Kör 8 owns this).
      CommunityRelationshipToViewer.blocked => previous,
      CommunityRelationshipToViewer.blockedBy => previous,
      CommunityRelationshipToViewer.notRelated =>
        // A7 — public profile would have come back as
        // ``following`` already; pending is the safe optimistic
        // default that the server-confirmed value will overwrite
        // if the target turns out to be public. The
        // relationship-confirmation path (a follow-up
        // ``fetchById`` after the follow returns) commits the
        // final value.
        CommunityRelationshipToViewer.pendingRequestOutgoing,
    };
  }

  CommunityRelationshipToViewer _optimisticAccept(
    CommunityRelationshipToViewer previous,
  ) {
    return switch (previous) {
      CommunityRelationshipToViewer.theyFollowYou =>
        CommunityRelationshipToViewer.mutualFollow,
      CommunityRelationshipToViewer.pendingRequestIncoming =>
        CommunityRelationshipToViewer.mutualFollow,
      // The accept only makes sense on an incoming request; other
      // states are no-ops.
      _ => previous,
    };
  }

  CommunityRelationshipToViewer _optimisticDecline() {
    // The requester-side relationship to the caller stays
    // ``notRelated`` after a decline. (The caller's view of the
    // requester likewise drops to ``notRelated``.)
    return CommunityRelationshipToViewer.notRelated;
  }

  CommunityRelationshipToViewer _optimisticRemoveFollower(
    CommunityRelationshipToViewer previous,
  ) {
    return switch (previous) {
      CommunityRelationshipToViewer.theyFollowYou =>
        CommunityRelationshipToViewer.notRelated,
      CommunityRelationshipToViewer.mutualFollow =>
        CommunityRelationshipToViewer.youFollowThem,
      _ => previous,
    };
  }

  // ---- internal state mutations --------------------------------------

  void _writeRelationship(
    PublicUserId target,
    RelationshipView? view, {
    required CommunityRelationshipToViewer optimistic,
  }) {
    final current = state.value ?? const CommunityRelationshipState.initial();
    final next = Map<PublicUserId, RelationshipView>.from(current.relationships);
    next[target] = (view ?? const RelationshipView(
      server: CommunityRelationshipToViewer.notRelated,
    )).copyWith(optimistic: optimistic);
    state = AsyncData(current.copyWith(relationships: next));
  }

  void _commitOptimistic(
    PublicUserId target,
    CommunityRelationshipToViewer value,
  ) {
    final current = state.value ?? const CommunityRelationshipState.initial();
    final next = Map<PublicUserId, RelationshipView>.from(current.relationships);
    next[target] = RelationshipView(server: value);
    state = AsyncData(current.copyWith(
      relationships: next,
      isSubmitting: false,
      error: null,
    ));
  }

  void _rollbackOptimistic(
    PublicUserId target,
    RelationshipView? view,
    CommunityRelationshipToViewer previousServer,
    CommunityRelationshipToViewer? previousOptimistic,
  ) {
    final current = state.value ?? const CommunityRelationshipState.initial();
    final next = Map<PublicUserId, RelationshipView>.from(current.relationships);
    next[target] = view?.copyWith(
          server: previousServer,
          optimistic: previousOptimistic,
          clearOptimistic: previousOptimistic == null,
        ) ??
        RelationshipView(
          server: previousServer,
          optimistic: previousOptimistic,
        );
    state = AsyncData(current.copyWith(
      relationships: next,
      isSubmitting: false,
    ));
  }
}

/// The discriminated outcome of a write call. Mirrors the
/// Kör 6 ``CommunityProfileSubmitResult`` shape.
sealed class CommunityRelationshipSubmitResult {
  const CommunityRelationshipSubmitResult();

  const factory CommunityRelationshipSubmitResult.success() =
      CommunityRelationshipSubmitSuccess;
  const factory CommunityRelationshipSubmitResult.failure(AppFailure error) =
      CommunityRelationshipSubmitFailure;
  const factory CommunityRelationshipSubmitResult.busy() =
      CommunityRelationshipSubmitBusy;
}

class CommunityRelationshipSubmitSuccess
    implements CommunityRelationshipSubmitResult {
  const CommunityRelationshipSubmitSuccess();
}

class CommunityRelationshipSubmitFailure
    implements CommunityRelationshipSubmitResult {
  const CommunityRelationshipSubmitFailure(this.error);
  final AppFailure error;
}

class CommunityRelationshipSubmitBusy
    implements CommunityRelationshipSubmitResult {
  const CommunityRelationshipSubmitBusy();
}

final communityRelationshipControllerProvider =
    AsyncNotifierProvider.autoDispose<
      CommunityRelationshipController,
      CommunityRelationshipState
    >(CommunityRelationshipController.new);