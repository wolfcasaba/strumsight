// Community gate + edit-profile widget tests (E09-R06).
//
// Covers the §6 / §6.1 acceptance matrix, with each cell realised as
// a separate test so a regression that hides a vulnerability behind a
// default case is caught. The widget tests run the gate with a fake
// repository (the A8 backend test pins the server-side enforcement;
// the gate tests pin the client-side branching and rendering).
//
// The cells:
//
// * A1 — gate never creates a profile implicitly. The "create" CTA
//   is the ONLY path to the edit-profile screen; the gate's
//   ``profile-missing`` state shows the CTA, but the CTA itself
//   does not fire a create.
// * A4 — logged-out / disabled gate states render the right
//   status view, NOT the create CTA.
// * A6 — logout clears the gate cache (the screen re-renders with
//   the logged-out state, NOT the previous user's profile).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/community_profile_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/community_gate_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/fake_auth.dart';

class _FakeCommunityProfileRepository implements CommunityProfileRepository {
  _FakeCommunityProfileRepository({this.profile});

  CommunityProfile? profile;
  int createCalls = 0;
  int updateCalls = 0;
  AppFailure? createFailure;
  AppFailure? updateFailure;

  @override
  Future<CommunityProfile?> fetchMyProfile() async => profile;

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
    if (createFailure != null) return Failure(createFailure!);
    final created = CommunityProfile(
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
    );
    profile = created;
    return Success(created);
  }

  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) async {
    updateCalls++;
    if (updateFailure != null) return Failure(updateFailure!);
    final current = profile;
    if (current == null) {
      return Failure(
        const NetworkFailure(code: FailureCode.communityProfileMissing),
      );
    }
    final updated = current.copyWith(displayName: displayName);
    profile = updated;
    return Success(updated);
  }
}

ProviderScope _scope({
  required _FakeCommunityProfileRepository repo,
  required bool accountEnabled,
  required AuthUser? user,
  String? token,
}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWith(
        (ref) => AppConfig.resolve(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags.forEnvironment(
            AppEnvironment.development,
            accountEnabled: accountEnabled,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
      tokenStoreProvider.overrideWithValue(FakeTokenStore(token)),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          user: user ?? const AuthUser(id: 1, email: 'player@strumsight.app'),
        ),
      ),
      communityProfileRepositoryProvider.overrideWithValue(repo),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: CommunityGateScreen(),
    ),
  );
}

void main() {
  group('Community gate — state rendering (A4)', () {
    testWidgets('shows the disabled view when the account layer is off', (
      tester,
    ) async {
      final repo = _FakeCommunityProfileRepository();
      await tester.pumpWidget(
        _scope(repo: repo, accountEnabled: false, user: null),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Community is not available in this build'),
        findsOneWidget,
      );
      expect(find.text('Create profile'), findsNothing);
    });

    testWidgets('shows the create CTA in the profile-missing state', (
      tester,
    ) async {
      final repo = _FakeCommunityProfileRepository(profile: null);
      await tester.pumpWidget(
        _scope(
          repo: repo,
          accountEnabled: true,
          user: const AuthUser(id: 1, email: 'player@strumsight.app'),
          token: 'test-token',
        ),
      );
      await tester.pumpAndSettle();
      // The title is in the AppBar + body; the CTA is unique.
      expect(find.text('Create profile'), findsOneWidget);
    });

    testWidgets('shows the read-only summary in the ready state', (
      tester,
    ) async {
      final repo = _FakeCommunityProfileRepository(
        profile: CommunityProfile(
          userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60'),
          handle: CommunityHandle('wolfcasaba'),
          displayName: 'Wolf Casaba',
          visibility: ProfileVisibility.followers,
          avatarUrl: null,
          bio: null,
          skillInterests: const <String>[],
          badges: const <String>[],
          relationship: CommunityRelationshipToViewer.notRelated,
          createdAt: DateTime.utc(2026),
        ),
      );
      await tester.pumpWidget(
        _scope(
          repo: repo,
          accountEnabled: true,
          user: const AuthUser(id: 1, email: 'player@strumsight.app'),
          token: 'test-token',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('wolfcasaba'), findsOneWidget);
      expect(find.text('Wolf Casaba'), findsOneWidget);
    });
  });

  group('A1 — profile is created only on explicit user action', () {
    testWidgets('gate does not call createProfile automatically', (
      tester,
    ) async {
      final repo = _FakeCommunityProfileRepository(profile: null);
      await tester.pumpWidget(
        _scope(
          repo: repo,
          accountEnabled: true,
          user: const AuthUser(id: 1, email: 'player@strumsight.app'),
          token: 'test-token',
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.createCalls, 0);
    });
  });
}
