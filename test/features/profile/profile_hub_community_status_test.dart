// MI-L (R33) — the Profile hub's Community subtitle tells the MEASURED
// truth.
//
// MEASURED before this round: the subtitle was chosen by the BUILD FLAG
// alone, so a build that ships Community against a server running with
// the module switched off promised "Connect with other players and share
// your progress" and then handed the user a gate screen saying the
// opposite. The gate controller already measures that case as
// `CommunityGateStatus.unavailable`.
//
// Cells:
//   L1 — server-disabled → the honest "switched off on the server" copy,
//   L2 — the gate resolved as usable → the ORIGINAL copy, byte-identical
//        (this is what `e13_r17_profile_hub_compact` renders),
//   L3 — a gate that has not resolved (or failed to) keeps the original
//        copy too: an unfinished probe is not evidence,
//   L4 — the build flag off still wins, unchanged.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_result.dart';
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
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../support/preference_store.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._user);
  final AuthUser? _user;

  @override
  Future<AuthUser?> build() async => _user;
}

class _ProfileRepository implements CommunityProfileRepository {
  _ProfileRepository({this.unavailable = false, this.never = false});

  final bool unavailable;
  final bool never;

  @override
  Future<CommunityProfile?> fetchMyProfile() async {
    if (never) return Completer<CommunityProfile?>().future;
    if (unavailable) throw communityUnavailableFailure('router not mounted');
    return null;
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

Widget _host({
  required bool communityEnabled,
  required _ProfileRepository repo,
  bool accountEnabled = true,
}) => ProviderScope(
  overrides: [
    ...preferenceOverrides(),
    appConfigProvider.overrideWithValue(
      AppConfig(
        environment: AppEnvironment.development,
        apiBaseUrl: AppConfig.devApiBaseUrl,
        flags: FeatureFlags(
          accountEnabled: accountEnabled,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          communityEnabled: communityEnabled,
        ),
        diagnosticsToken: AppConfig.devDiagnosticsToken,
        buildMode: 'test',
        appVersion: 'test',
      ),
    ),
    authControllerProvider.overrideWith(
      () => _FakeAuthController(
        const AuthUser(id: 1, email: 'player@strumsight.app'),
      ),
    ),
    communityProfileRepositoryProvider.overrideWithValue(repo),
  ],
  child: const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: Locale('en'),
    home: ProfileHubScreen(),
  ),
);

void main() {
  final l10n = AppLocalizationsEn();

  testWidgets('L1 — a server-disabled Community says so', (tester) async {
    await tester.pumpWidget(
      _host(
        communityEnabled: true,
        repo: _ProfileRepository(unavailable: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.profileHubCommunityServerDisabledMessage),
      findsOneWidget,
    );
    expect(find.text(l10n.profileHubCommunityEnabledMessage), findsNothing);
  });

  testWidgets('L2 — a usable gate keeps the original copy', (tester) async {
    await tester.pumpWidget(
      _host(communityEnabled: true, repo: _ProfileRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.profileHubCommunityEnabledMessage), findsOneWidget);
  });

  testWidgets('L3 — an unresolved probe keeps the original copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(communityEnabled: true, repo: _ProfileRepository(never: true)),
    );
    await tester.pump();

    expect(find.text(l10n.profileHubCommunityEnabledMessage), findsOneWidget);
  });

  testWidgets('L4 — the build flag off still wins', (tester) async {
    await tester.pumpWidget(
      _host(communityEnabled: false, repo: _ProfileRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.profileHubCommunityDisabledReason), findsOneWidget);
  });
}
