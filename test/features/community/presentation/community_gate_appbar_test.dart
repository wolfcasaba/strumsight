// MI-A (R33) — the Community gate's AppBar title, per gate state.
//
// MEASURED before this round: the AppBar was hard-wired to
// `communityGateProfileMissingTitle` ("Create your Community profile") in
// EVERY state — including the two whose own body says the opposite
// ("Community is not available in this build", "…not enabled on this
// server yet") and the logged-out one, which offers no profile creation
// at all. The title is the first thing a screen reader announces, so it
// was the screen's loudest untruth.
//
// Cells:
//   T1 — build-disabled → the unavailable AppBar title,
//   T2 — logged out → the sign-in AppBar title,
//   T3 — server-disabled (`CommunityGateStatus.unavailable`) → the
//        unavailable AppBar title,
//   T4 — profile-missing KEEPS the old title (the state pinned by
//        `e13_r33_gate_compact`, and the one state where it was true),
//   T5 — ready → the neutral "Community" title.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/failures/community_availability.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/community_profile_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/community_gate_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../../support/fake_auth.dart';

/// Answers with [profile], or throws the "router not mounted" failure the
/// live deploy produces when [unavailable] is set.
class _ProfileRepository implements CommunityProfileRepository {
  _ProfileRepository({this.profile, this.unavailable = false});

  CommunityProfile? profile;
  final bool unavailable;

  @override
  Future<CommunityProfile?> fetchMyProfile() async {
    if (unavailable) throw communityUnavailableFailure('router not mounted');
    return profile;
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
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) => throw UnsupportedError('not used in this test');
}

CommunityProfile _profile() => CommunityProfile(
  userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60'),
  handle: CommunityHandle('wolfcasaba'),
  displayName: 'Wolf Casaba',
  visibility: ProfileVisibility.followers,
  avatarUrl: null,
  bio: null,
  skillInterests: const <String>[],
  badges: const <String>[],
  relationship: CommunityRelationshipToViewer.notRelated,
  createdAt: DateTime.utc(2026, 8),
);

Widget _app({
  required _ProfileRepository repo,
  required bool accountEnabled,
  AuthUser? user,
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

Finder _appBarTitle(String text) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(text));

void main() {
  final l10n = AppLocalizationsEn();

  testWidgets('T1 — build-disabled does not offer to create a profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(repo: _ProfileRepository(), accountEnabled: false),
    );
    await tester.pumpAndSettle();

    expect(
      _appBarTitle(l10n.communityGateAppBarUnavailableTitle),
      findsOneWidget,
    );
    expect(_appBarTitle(l10n.communityGateProfileMissingTitle), findsNothing);
  });

  testWidgets('T2 — logged out says sign in', (tester) async {
    await tester.pumpWidget(
      _app(repo: _ProfileRepository(), accountEnabled: true),
    );
    await tester.pumpAndSettle();

    expect(
      _appBarTitle(l10n.communityGateAppBarLoggedOutTitle),
      findsOneWidget,
    );
  });

  testWidgets('T3 — the server-disabled state says unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        repo: _ProfileRepository(unavailable: true),
        accountEnabled: true,
        user: const AuthUser(id: 1, email: 'player@strumsight.app'),
        token: 'test-token',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _appBarTitle(l10n.communityGateAppBarUnavailableTitle),
      findsOneWidget,
    );
  });

  testWidgets('T4 — profile-missing keeps the pinned title', (tester) async {
    // `e13_r33_gate_compact` renders exactly this state; the title must
    // stay byte-identical or the pixel-pinned golden moves.
    await tester.pumpWidget(
      _app(
        repo: _ProfileRepository(),
        accountEnabled: true,
        user: const AuthUser(id: 1, email: 'player@strumsight.app'),
        token: 'test-token',
      ),
    );
    await tester.pumpAndSettle();

    expect(_appBarTitle(l10n.communityGateProfileMissingTitle), findsOneWidget);
  });

  testWidgets('T5 — the ready state gets the neutral title', (tester) async {
    await tester.pumpWidget(
      _app(
        repo: _ProfileRepository(profile: _profile()),
        accountEnabled: true,
        user: const AuthUser(id: 1, email: 'player@strumsight.app'),
        token: 'test-token',
      ),
    );
    await tester.pumpAndSettle();

    expect(_appBarTitle(l10n.communityGateAppBarTitle), findsOneWidget);
  });
}
