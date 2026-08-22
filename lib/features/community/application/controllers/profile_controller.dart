/// Community profile controller — the four-state gate + write surface
/// (E09-R06, ADR 0400 §5).
///
/// The controller is the ONLY place the four states
/// (``disabled`` / ``logged-out`` / ``profile-missing`` / ``ready``)
/// collapse into a single value the UI can branch on. It is built
/// on top of three orthogonal providers:
///
/// * ``accountEnabledProvider`` — Kör 1 / Kör 2 master switch. When
///   ``false``, the gate is the ``disabled`` view (a "feature not
///   available" screen, no further queries).
/// * ``authControllerProvider`` — Kör 5 auth state. When no user is
///   signed in, the gate is the ``logged-out`` view (the user is
///   invited to sign in / sign up first).
/// * ``communityProfileRepositoryProvider`` — Kör 6 repository.
///   When the auth is OK and the user is signed in, the controller
///   calls ``fetchMyProfile()`` to decide ``profile-missing`` vs
///   ``ready``.
///
/// The **invariants** the brief §5.1 / A1 requires:
///
/// 1. The controller NEVER creates a profile implicitly. The
///    ``ready`` state is reached only by an explicit
///    ``createProfile(...)`` call from the edit-profile screen. The
///    fetch in ``build`` is read-only.
/// 2. The controller never writes to the cache from a non-explicit
///    path. A5's "dupla submit két profilt hoz létre" failure mode
///    is guarded by ``_submitting`` (a single in-flight boolean),
///    which the edit-profile screen also guards at the UI level
///    (disabled submit button). The DB-level ``user_id`` unique
///    index is the belt-and-braces — see ADR 0400 §5.3 / A8.
///
/// A3 ("hálózati hiba nem veszti el a kitöltött profilt") is the
/// edit-profile screen's job — the controller's form state is the
/// screen, the controller itself only orchestrates the API. The
/// screen holds the in-progress draft and re-pushes it after a
/// network failure.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../features/auth/public.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/community_profile_repository.dart';
import '../../domain/value_objects/community_handle.dart';

/// The four gate states the brief §5.1 names.
enum CommunityGateStatus {
  /// The account layer (or the Community module flag) is off for
  /// this build — the gate shows the "feature not available" view.
  disabled,

  /// The user is not signed in — the gate shows the auth flow
  /// before the Community screen mounts.
  loggedOut,

  /// The user is signed in but does not yet own a Community
  /// profile — the gate shows the onboarding flow.
  profileMissing,

  /// The user is signed in AND owns a profile — the gate shows the
  /// read-only or edit-profile screen.
  ready,
}

/// The snapshot the controller publishes to the UI. The gate is
/// driven by [status]; the loaded profile is exposed alongside so
/// the ready-state view does not have to re-fetch.
class CommunityProfileState {
  const CommunityProfileState({
    required this.status,
    required this.profile,
    required this.error,
    required this.isSubmitting,
  });

  const CommunityProfileState.initial()
    : status = CommunityGateStatus.disabled,
      profile = null,
      error = null,
      isSubmitting = false;

  final CommunityGateStatus status;
  final CommunityProfile? profile;
  final AppFailure? error;
  final bool isSubmitting;

  CommunityProfileState copyWith({
    CommunityGateStatus? status,
    CommunityProfile? profile,
    Object? error = _sentinel,
    bool? isSubmitting,
  }) {
    return CommunityProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      error: identical(error, _sentinel) ? this.error : error as AppFailure?,
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }
}

const Object _sentinel = Object();

/// The Community profile state machine.
///
/// The build method is the gate's resolver — it composes
/// ``accountEnabledProvider`` + ``authControllerProvider`` +
/// ``communityProfileRepositoryProvider`` into a single
/// [CommunityProfileState]. The state machine also exposes the two
/// write methods the edit-profile screen calls. The build method
/// re-runs whenever any of its three dependencies change (Riverpod
/// auto-track), so a logout / login / re-enable transition
/// automatically re-evaluates the gate.
class CommunityProfileController extends AsyncNotifier<CommunityProfileState> {
  CommunityProfileRepository get _repo =>
      ref.read(communityProfileRepositoryProvider);

  @override
  Future<CommunityProfileState> build() async {
    final accountEnabled = ref.watch(accountEnabledProvider);
    if (!accountEnabled) {
      return const CommunityProfileState(
        status: CommunityGateStatus.disabled,
        profile: null,
        error: null,
        isSubmitting: false,
      );
    }

    final auth = ref.watch(authControllerProvider).value;
    if (auth == null) {
      return const CommunityProfileState(
        status: CommunityGateStatus.loggedOut,
        profile: null,
        error: null,
        isSubmitting: false,
      );
    }

    // The user is signed in. Probe the repository for the profile
    // row. The repository is the dio impl; it returns ``null`` on
    // 404 (the "no profile yet" signal) and throws on other
    // failures (network, 5xx).
    try {
      final profile = await _repo.fetchMyProfile();
      if (profile == null) {
        return const CommunityProfileState(
          status: CommunityGateStatus.profileMissing,
          profile: null,
          error: null,
          isSubmitting: false,
        );
      }
      return CommunityProfileState(
        status: CommunityGateStatus.ready,
        profile: profile,
        error: null,
        isSubmitting: false,
      );
    } on AppFailure catch (failure) {
      return CommunityProfileState(
        status: CommunityGateStatus.profileMissing,
        profile: null,
        error: failure,
        isSubmitting: false,
      );
    }
  }

  /// Refresh the gate. The edit-profile screen calls this after a
  /// successful create / update so the gate transitions to
  /// ``ready`` without a full re-mount.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Create the caller's community profile. The submit-gate on the
  /// edit-profile screen prevents a second concurrent call from
  /// landing here, but ``isSubmitting`` is the belt-and-braces for
  /// the same race.
  Future<CommunityProfileSubmitResult> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  }) async {
    if (state.value?.isSubmitting ?? false) {
      return const CommunityProfileSubmitResult.busy();
    }
    state = AsyncData(state.value!.copyWith(isSubmitting: true, error: null));
    final result = await _repo.createProfile(
      handle: handle,
      displayName: displayName,
      visibility: visibility,
      audienceDefault: audienceDefault,
    );
    return switch (result) {
      Success(:final value) => _onWriteSuccess(value),
      Failure(:final error) => _onWriteFailure(error),
    };
  }

  /// Update the caller's own profile (display name only). Privacy
  /// changes are a separate endpoint (the Kör 4 ``privacy.py``
  /// router, not wired into the module in this round), and the
  /// edit-mode UI therefore does not offer a privacy re-selection.
  Future<CommunityProfileSubmitResult> updateProfile({
    required String displayName,
  }) async {
    if (state.value?.isSubmitting ?? false) {
      return const CommunityProfileSubmitResult.busy();
    }
    state = AsyncData(state.value!.copyWith(isSubmitting: true, error: null));
    final result = await _repo.updateProfile(displayName: displayName);
    return switch (result) {
      Success(:final value) => _onWriteSuccess(value),
      Failure(:final error) => _onWriteFailure(error),
    };
  }

  /// Reset the controller's local error. The screen calls this when
  /// the user dismisses an error banner / re-types a field, so the
  /// next submit does not flash the same error from the cache.
  void clearError() {
    final value = state.value;
    if (value == null) return;
    state = AsyncData(value.copyWith(error: null));
  }

  CommunityProfileSubmitResult _onWriteSuccess(CommunityProfile profile) {
    state = AsyncData(
      CommunityProfileState(
        status: CommunityGateStatus.ready,
        profile: profile,
        error: null,
        isSubmitting: false,
      ),
    );
    return CommunityProfileSubmitResult.success(profile);
  }

  CommunityProfileSubmitResult _onWriteFailure(AppFailure error) {
    state = AsyncData(state.value!.copyWith(isSubmitting: false, error: error));
    if (error is ValidationFailure &&
        error.code == FailureCode.communityConflict) {
      // 409 on create — by the controller's pre-submit
      // ``fetchMyProfile()`` gate, the only remaining conflict
      // source is the handle. The screen surfaces it as an inline
      // field error.
      return const CommunityProfileSubmitResult.handleTaken();
    }
    return CommunityProfileSubmitResult.failure(error);
  }
}

/// The discriminated outcome of a write call. The screen branches on
/// this — it does NOT inspect the AppFailure directly.
sealed class CommunityProfileSubmitResult {
  const CommunityProfileSubmitResult();

  const factory CommunityProfileSubmitResult.success(CommunityProfile profile) =
      CommunityProfileSubmitSuccess;
  const factory CommunityProfileSubmitResult.handleTaken() =
      CommunityProfileSubmitHandleTaken;
  const factory CommunityProfileSubmitResult.failure(AppFailure error) =
      CommunityProfileSubmitFailure;
  const factory CommunityProfileSubmitResult.busy() =
      CommunityProfileSubmitBusy;
}

class CommunityProfileSubmitSuccess implements CommunityProfileSubmitResult {
  const CommunityProfileSubmitSuccess(this.profile);
  final CommunityProfile profile;
}

class CommunityProfileSubmitHandleTaken
    implements CommunityProfileSubmitResult {
  const CommunityProfileSubmitHandleTaken();
}

class CommunityProfileSubmitFailure implements CommunityProfileSubmitResult {
  const CommunityProfileSubmitFailure(this.error);
  final AppFailure error;
}

class CommunityProfileSubmitBusy implements CommunityProfileSubmitResult {
  const CommunityProfileSubmitBusy();
}

final communityProfileControllerProvider =
    AsyncNotifierProvider.autoDispose<
      CommunityProfileController,
      CommunityProfileState
    >(CommunityProfileController.new);
