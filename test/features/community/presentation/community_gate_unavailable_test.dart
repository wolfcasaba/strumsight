// R12 (audit §5.2) — the Community gate's "not enabled on this server"
// state.
//
// MEASURED: the live deploy runs with `STRUMSIGHT_COMMUNITY_ENABLED=false`,
// so every `/community/**` call 404s because the router is never mounted.
// Until this round the gate turned that into `profileMissing` and offered
// Create profile — a CTA whose POST could only 404 again, reported with the
// generic "check your connection" copy. Cells:
//
//   G1 — the dedicated unavailable card renders, the generic error does not,
//   G2 — the Create-profile CTA is NOT offered in this state,
//   G3 — Retry re-runs the gate, and a server that comes back flips it.
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

const _card = Key('community-gate-unavailable');
const _retry = Key('community-gate-unavailable-retry');

/// A repository that answers like a server WITHOUT the community router
/// mounted, until [unavailable] is turned off.
class _UnavailableProfileRepository implements CommunityProfileRepository {
  int fetchCalls = 0;
  bool unavailable = true;

  @override
  Future<CommunityProfile?> fetchMyProfile() async {
    fetchCalls++;
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

Widget _app(_UnavailableProfileRepository repo) {
  return ProviderScope(
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
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          user: const AuthUser(id: 1, email: 'player@strumsight.app'),
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
  final l10n = AppLocalizationsEn();

  testWidgets('G1 renders the unavailable card', (tester) async {
    await tester.pumpWidget(_app(_UnavailableProfileRepository()));
    await tester.pumpAndSettle();

    expect(find.byKey(_card), findsOneWidget);
    expect(find.text(l10n.communityGateUnavailableTitle), findsOneWidget);
    expect(find.text(l10n.communityGateErrorBody), findsNothing);
  });

  testWidgets('G2 offers no create-profile CTA', (tester) async {
    await tester.pumpWidget(_app(_UnavailableProfileRepository()));
    await tester.pumpAndSettle();

    expect(find.text(l10n.communityGateProfileMissingCta), findsNothing);
    expect(find.byKey(_retry), findsOneWidget);
  });

  testWidgets('G3 retry re-runs the gate', (tester) async {
    final repo = _UnavailableProfileRepository();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(repo.fetchCalls, 1);

    // The operator flips the server switch; the next attempt succeeds.
    repo.unavailable = false;
    await tester.tap(find.byKey(_retry));
    await tester.pumpAndSettle();

    expect(repo.fetchCalls, 2);
    expect(find.byKey(_card), findsNothing);
    expect(find.text(l10n.communityGateProfileMissingCta), findsOneWidget);
  });
}
