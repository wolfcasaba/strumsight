/// Community challenge list + invite state machine (E09-R21,
/// ADR 0415, brief §6).
///
/// The controller is the only place where the caller's challenge
/// list and the invite lifecycle are mutated. It is a Riverpod
/// ``AsyncNotifier`` so the screen can reactively re-render on
/// every state transition — the Kör 20
/// ``NotificationController`` and Kör 14 ``FeedController``
/// precedent.
///
/// **List is the source of truth (§5.1).** The screen reads the
/// list from the server's authoritative state via the
/// ``communityChallengeRepository``. A lost push (offline
/// device) is at worst a delayed refresh, not information loss
/// (the Kör 5 ``CommunityChallengeRepository`` contract).
///
/// **Idempotency key (§5.3).** Each mutation gets a fresh
/// client-side key. The repository accepts the key on the wire;
/// the server uses the natural key identity
/// (``(challenge_id, inviter_profile_id, invitee_profile_id,
/// idempotency_key)`` UNIQUE, the §D4 Kör 11 post-create
/// precedent) as the canonical idempotency surface.
///
/// **No silent no-op (L309).** Every repository call has a
/// try/catch; the controller never swallows a ``StorageException``
/// or a ``NetworkFailure`` — each one flips the state to a label
/// the UI can show.
///
/// **Deep link (A6).** Accepted invites whose challenge type
/// resolves to a Practice or Song flow surface a deep link in
/// the row's trailing action. The mapping is the same
/// challenge-type → flow routing the Kör 16 feed uses; only
/// the ``practice`` / ``song`` / ``personalBest`` types
/// resolve to a deep link, the others are display-only.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/logging/logger_provider.dart';
// A `communityChallengeRepositoryProvider` EGYETLEN definíciója a Kör 21
// data-rétegében él. Ez a fájl korábban egy MÁSODIK, `UnimplementedError`-t
// dobó providert definiált ugyanazzal a névvel; a saját doc-commentje mondta
// ki, hogy „the production wiring lands in challenge_repository_impl.dart" —
// csak a leváltása maradt el. Az `export` azért van itt, hogy a fájlból
// importáló hívók (öt teszt + a CommunityChallengesScreen) UGYANAZT a
// provider-objektumot lássák, amit a képernyő figyel.
import '../../data/repositories/challenge_repository_impl.dart'
    show communityChallengeRepositoryProvider;
export '../../data/repositories/challenge_repository_impl.dart'
    show communityChallengeRepositoryProvider;
import '../../domain/entities/community_challenge.dart';
import '../../domain/repositories/challenge_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';

/// Which practice / song flow an accepted challenge deep-links
/// into (A6). The mapping is fixed for the Kör 21 surface —
/// ``friends`` / ``club`` / ``dailyCommunity`` / ``periodicGlobal``
/// types are display-only; only the four below resolve to a
/// flow. Future rounds can add more routes without breaking the
/// wire.
enum ChallengeDeepLinkTarget { practice, song, personalBest, none }

/// Decode a [ChallengeType] into a [ChallengeDeepLinkTarget].
///
/// The mapping is structural (the wire value carries the
/// routing intent); an unknown type degrades to
/// [ChallengeDeepLinkTarget.none] so the UI can show a
/// display-only row.
ChallengeDeepLinkTarget challengeDeepLinkTargetFromType(ChallengeType type) {
  switch (type) {
    case ChallengeType.friends:
    case ChallengeType.club:
    case ChallengeType.dailyCommunity:
    case ChallengeType.periodicGlobal:
      return ChallengeDeepLinkTarget.none;
    case ChallengeType.personalBest:
      return ChallengeDeepLinkTarget.personalBest;
  }
}

/// The full state the screen renders.
class ChallengeListState {
  const ChallengeListState({
    required this.items,
    required this.cursor,
    required this.isLoading,
    required this.isLoadingMore,
    required this.isMutating,
    required this.lastError,
  });

  const ChallengeListState.initial()
    : items = const <CommunityChallengeDefinition>[],
      cursor = const CursorPage.initial(),
      isLoading = false,
      isLoadingMore = false,
      isMutating = false,
      lastError = null;

  final List<CommunityChallengeDefinition> items;
  final CursorPage cursor;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isMutating;
  final AppFailure? lastError;

  ChallengeListState copyWith({
    List<CommunityChallengeDefinition>? items,
    Object? cursor = _sentinel,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isMutating,
    Object? lastError = _sentinel,
  }) {
    return ChallengeListState(
      items: items ?? this.items,
      cursor: identical(cursor, _sentinel) ? this.cursor : cursor as CursorPage,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isMutating: isMutating ?? this.isMutating,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as AppFailure?,
    );
  }
}

const Object _sentinel = Object();

/// The community challenge list + invite state machine.
class ChallengeController extends AsyncNotifier<ChallengeListState> {
  CommunityChallengeRepository get _repo =>
      ref.read(communityChallengeRepositoryProvider);

  AppLogger get _logger => ref.read(appLoggerProvider);

  @override
  Future<ChallengeListState> build() async {
    return const ChallengeListState.initial();
  }

  /// Load the first page of challenges visible to the viewer.
  Future<void> load({int pageSize = 25}) async {
    final current = state.value ?? const ChallengeListState.initial();
    state = AsyncData(current.copyWith(isLoading: true, lastError: null));
    try {
      final page = await _repo.listChallenges(
        cursor: const CursorPage.initial(),
        limit: pageSize,
      );
      state = AsyncData(
        current.copyWith(
          items: page.items,
          cursor: page.cursor,
          isLoading: false,
        ),
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.challenges.load.failure',
        fields: {'pageSize': pageSize},
      );
      state = AsyncData(current.copyWith(isLoading: false, lastError: failure));
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.challenges.load.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'pageSize': pageSize},
      );
      state = AsyncData(
        current.copyWith(
          isLoading: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Load the next page of challenges, if any.
  Future<void> loadMore({int pageSize = 25}) async {
    final current = state.value;
    if (current == null) return;
    if (current.isLoading || current.isLoadingMore) return;
    if (current.cursor.isInitial || current.cursor.cursor == null) {
      return;
    }
    state = AsyncData(current.copyWith(isLoadingMore: true, lastError: null));
    try {
      final page = await _repo.listChallenges(
        cursor: current.cursor,
        limit: pageSize,
      );
      state = AsyncData(
        current.copyWith(
          items: <CommunityChallengeDefinition>[
            ...current.items,
            ...page.items,
          ],
          cursor: page.cursor,
          isLoadingMore: false,
        ),
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.challenges.loadMore.failure',
        fields: {'pageSize': pageSize},
      );
      state = AsyncData(
        current.copyWith(isLoadingMore: false, lastError: failure),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.challenges.loadMore.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'pageSize': pageSize},
      );
      state = AsyncData(
        current.copyWith(
          isLoadingMore: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Invite a profile to a challenge (D4 idempotency).
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
  }) async {
    final current = state.value;
    if (current == null) return;
    if (current.isMutating) return;
    state = AsyncData(current.copyWith(isMutating: true, lastError: null));
    try {
      await _repo.invite(
        challengeId: challengeId,
        target: target,
        idempotencyKey: _newIdempotencyKey(),
      );
      state = AsyncData((state.value ?? current).copyWith(isMutating: false));
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.challenges.invite.failure',
        fields: {'challengeId': challengeId.value, 'target': target.value},
      );
      state = AsyncData(
        current.copyWith(isMutating: false, lastError: failure),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.challenges.invite.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'challengeId': challengeId.value, 'target': target.value},
      );
      state = AsyncData(
        current.copyWith(
          isMutating: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Accept a pending invite (A1 / A2 transitions).
  Future<void> acceptInvite(ContentId invitePublicId) async {
    final current = state.value;
    if (current == null) return;
    if (current.isMutating) return;
    state = AsyncData(current.copyWith(isMutating: true, lastError: null));
    try {
      await _repo.acceptInvite(
        challengeId: invitePublicId,
        idempotencyKey: _newIdempotencyKey(),
      );
      // Refresh the list — an accepted invite resolves the
      // participant state which the screen re-renders.
      await load();
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.challenges.acceptInvite.failure',
        fields: {'invitePublicId': invitePublicId.value},
      );
      state = AsyncData(
        current.copyWith(isMutating: false, lastError: failure),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.challenges.acceptInvite.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'invitePublicId': invitePublicId.value},
      );
      state = AsyncData(
        current.copyWith(
          isMutating: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Decline a pending invite (A1 transitions).
  Future<void> declineInvite(ContentId invitePublicId) async {
    final current = state.value;
    if (current == null) return;
    if (current.isMutating) return;
    state = AsyncData(current.copyWith(isMutating: true, lastError: null));
    try {
      await _repo.declineInvite(
        challengeId: invitePublicId,
        idempotencyKey: _newIdempotencyKey(),
      );
      await load();
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.challenges.declineInvite.failure',
        fields: {'invitePublicId': invitePublicId.value},
      );
      state = AsyncData(
        current.copyWith(isMutating: false, lastError: failure),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.challenges.declineInvite.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'invitePublicId': invitePublicId.value},
      );
      state = AsyncData(
        current.copyWith(
          isMutating: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Cancel an outgoing invite (A5 cancel-race surface).
  Future<void> cancelInvite({
    required ContentId invitePublicId,
    required PublicUserId target,
  }) async {
    final current = state.value;
    if (current == null) return;
    if (current.isMutating) return;
    state = AsyncData(current.copyWith(isMutating: true, lastError: null));
    try {
      await _repo.cancelInvite(
        challengeId: invitePublicId,
        target: target,
        idempotencyKey: _newIdempotencyKey(),
      );
      await load();
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.challenges.cancelInvite.failure',
        fields: {
          'invitePublicId': invitePublicId.value,
          'target': target.value,
        },
      );
      state = AsyncData(
        current.copyWith(isMutating: false, lastError: failure),
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.challenges.cancelInvite.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'invitePublicId': invitePublicId.value,
          'target': target.value,
        },
      );
      state = AsyncData(
        current.copyWith(
          isMutating: false,
          lastError: UnknownFailure(
            code: FailureCode.unknown,
            cause: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    }
  }

  /// Drop the last error (the user dismissed the banner).
  void clearError() {
    final current = state.value;
    if (current == null || current.lastError == null) return;
    state = AsyncData(current.copyWith(lastError: null));
  }

  // ---- internal ----------------------------------------------------------

  int _idempotencyCounter = 0;

  String _newIdempotencyKey() {
    _idempotencyCounter += 1;
    return 'e09-r21-$_idempotencyCounter-${DateTime.now().microsecondsSinceEpoch}';
  }
}

/// Provider for the [ChallengeController]. The screen reads
/// this directly; the repository dependency is pulled from
/// [communityChallengeRepositoryProvider].
final challengeControllerProvider =
    AsyncNotifierProvider.autoDispose<ChallengeController, ChallengeListState>(
      ChallengeController.new,
    );
