// Audit H21 — `state.value!` on an AsyncValue throws in the loading and
// error states. The profile controller dereferenced it on every submit.
// `refresh()` sets a BARE `AsyncLoading` (no previous value carried over) and
// `AsyncValue.guard` a bare `AsyncError`, so a submit that lands while the
// gate is being re-resolved — or after that failed — used to crash instead
// of being refused. These tests pin the safe behaviour: the write is
// reported as busy, and nothing throws.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/profile_controller.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/community_profile_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';

import '../../../support/fake_auth.dart';

/// A repository whose `fetchMyProfile` is scriptable: it can hang forever
/// (the gate stays loading) or blow up (the gate ends in an error state).
class _GateRepository implements CommunityProfileRepository {
  _GateRepository({this.hang = false, this.fetchError});

  final bool hang;
  final Object? fetchError;
  final Completer<CommunityProfile?> _never = Completer<CommunityProfile?>();
  int createCalls = 0;
  int updateCalls = 0;

  @override
  Future<CommunityProfile?> fetchMyProfile() {
    if (hang) return _never.future;
    if (fetchError != null) return Future<CommunityProfile?>.error(fetchError!);
    return Future<CommunityProfile?>.value(null);
  }

  @override
  Future<CommunityProfile> fetchById(PublicUserId userId) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<CommunityProfile?> fetchByHandle(CommunityHandle handle) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityProfile>> searchProfiles({
    required String query,
    required Object cursor,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<AppResult<CommunityProfile>> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  }) async {
    createCalls++;
    return Success(
      CommunityProfile(
        userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60'),
        handle: handle,
        displayName: displayName,
        visibility: visibility,
        avatarUrl: null,
        bio: null,
        skillInterests: const <String>[],
        badges: const <String>[],
        relationship: CommunityRelationshipToViewer.notRelated,
        createdAt: DateTime.utc(2026),
      ),
    );
  }

  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) async {
    updateCalls++;
    throw UnsupportedError('not reached in this test');
  }
}

ProviderContainer _container(_GateRepository repo) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWith(
        (ref) => AppConfig.resolve(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags.forEnvironment(
            AppEnvironment.development,
            accountEnabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
      tokenStoreProvider.overrideWithValue(FakeTokenStore('test-token')),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      communityProfileRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  // Keep the autoDispose controller alive for the whole test.
  container.listen(
    communityProfileControllerProvider,
    (previous, next) {},
    fireImmediately: true,
  );
  return container;
}

CommunityProfileController _controllerOf(ProviderContainer container) =>
    container.read(communityProfileControllerProvider.notifier);

void main() {
  test('createProfile during a refresh is refused, not a crash', () async {
    final repo = _GateRepository(hang: true);
    final container = _container(repo);
    await pumpEventQueue();
    final controller = _controllerOf(container);

    // A refresh that never resolves: the state is a bare AsyncLoading, so
    // `state.value` is null — the exact shape the old `!` blew up on.
    unawaited(controller.refresh());
    expect(container.read(communityProfileControllerProvider).value, isNull);

    final result = await controller.createProfile(
      handle: CommunityHandle('wolfcasaba'),
      displayName: 'Wolf Casaba',
      visibility: ProfileVisibility.followers,
      audienceDefault: CommunityAudience.followers,
    );

    expect(result, isA<CommunityProfileSubmitBusy>());
    expect(repo.createCalls, 0);
  });

  test('updateProfile during a refresh is refused, not a crash', () async {
    final repo = _GateRepository(hang: true);
    final container = _container(repo);
    await pumpEventQueue();
    final controller = _controllerOf(container);

    unawaited(controller.refresh());
    final result = await controller.updateProfile(displayName: 'Wolf');

    expect(result, isA<CommunityProfileSubmitBusy>());
    expect(repo.updateCalls, 0);
  });

  test('a submit after a FAILED refresh is refused, not a crash', () async {
    final repo = _GateRepository(fetchError: StateError('gate blew up'));
    final container = _container(repo);
    await pumpEventQueue();
    final controller = _controllerOf(container);

    await controller.refresh();
    expect(container.read(communityProfileControllerProvider).value, isNull);

    final result = await controller.createProfile(
      handle: CommunityHandle('wolfcasaba'),
      displayName: 'Wolf Casaba',
      visibility: ProfileVisibility.followers,
      audienceDefault: CommunityAudience.followers,
    );

    expect(result, isA<CommunityProfileSubmitBusy>());
    expect(repo.createCalls, 0);
  });

  test('a resolved gate still submits (the guard is not a block)', () async {
    final repo = _GateRepository();
    final container = _container(repo);
    await pumpEventQueue();

    final state = container.read(communityProfileControllerProvider).value;
    expect(state?.status, CommunityGateStatus.profileMissing);

    final controller = _controllerOf(container);
    final result = await controller.createProfile(
      handle: CommunityHandle('wolfcasaba'),
      displayName: 'Wolf Casaba',
      visibility: ProfileVisibility.followers,
      audienceDefault: CommunityAudience.followers,
    );

    expect(result, isA<CommunityProfileSubmitSuccess>());
    expect(repo.createCalls, 1);
  });
}
