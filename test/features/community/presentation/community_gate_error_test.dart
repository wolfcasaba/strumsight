// R20 (audit M6.3) — the Community gate's "we could not ask" state.
//
// MEASURED before this round
// (`lib/features/community/application/controllers/profile_controller.dart`
// :177-189): EVERY `AppFailure` that was not the R12 "module missing"
// verdict collapsed into `CommunityGateStatus.profileMissing`. A timeout or
// a 500 therefore rendered the "Create your Community profile" CTA to a
// learner who may already own one — and the create POST would then 409
// against that very profile. "We could not ask" is not "you have none".
//
// The four discriminating cells this file pins:
//
//   E1 — a timeout renders the error card (never the create CTA),
//   E2 — a 5xx renders the error card (never the create CTA),
//   E3 — a SUCCESSFUL fetch returning `null` still renders the create CTA
//        (the one result that really does mean "no profile yet"),
//   E4 — the R12 `unavailable` verdict keeps its own card, not this one,
//   E5 — Retry re-runs the probe, and a server that comes back flips the
//        gate to the create CTA.
library;

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

const _errorCard = Key('community-gate-error');
const _errorRetry = Key('community-gate-error-retry');
const _unavailableCard = Key('community-gate-unavailable');

/// A repository whose probe fails with [failure] until [failure] is cleared.
class _FailingProfileRepository implements CommunityProfileRepository {
  _FailingProfileRepository(this.failure);

  int fetchCalls = 0;
  AppFailure? failure;

  @override
  Future<CommunityProfile?> fetchMyProfile() async {
    fetchCalls++;
    final pending = failure;
    if (pending != null) throw pending;
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

Widget _app(_FailingProfileRepository repo) {
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

  testWidgets('E1 a timeout renders the error card, not the create CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FailingProfileRepository(
          const NetworkFailure(code: FailureCode.networkTimeout),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_errorCard), findsOneWidget);
    expect(find.text(l10n.communityGateErrorTitle), findsOneWidget);
    expect(find.byKey(_errorRetry), findsOneWidget);
    expect(find.text(l10n.communityGateProfileMissingCta), findsNothing);
    expect(find.byKey(_unavailableCard), findsNothing);
  });

  testWidgets('E2 a 5xx renders the error card, not the create CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FailingProfileRepository(
          const NetworkFailure(code: FailureCode.networkServer),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_errorCard), findsOneWidget);
    expect(find.text(l10n.communityGateProfileMissingCta), findsNothing);
  });

  testWidgets('E3 a successful null profile still offers the create CTA', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FailingProfileRepository(null)));
    await tester.pumpAndSettle();

    expect(find.text(l10n.communityGateProfileMissingCta), findsOneWidget);
    expect(find.byKey(_errorCard), findsNothing);
  });

  testWidgets('E4 the module-missing verdict keeps its own card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _FailingProfileRepository(
          communityUnavailableFailure('router not mounted'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_unavailableCard), findsOneWidget);
    expect(find.byKey(_errorCard), findsNothing);
  });

  testWidgets('E5 retry re-runs the probe and a recovered server flips it', (
    tester,
  ) async {
    final repo = _FailingProfileRepository(
      const NetworkFailure(code: FailureCode.networkTimeout),
    );
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(repo.fetchCalls, 1);

    repo.failure = null;
    await tester.tap(find.byKey(_errorRetry));
    await tester.pumpAndSettle();

    expect(repo.fetchCalls, 2);
    expect(find.byKey(_errorCard), findsNothing);
    expect(find.text(l10n.communityGateProfileMissingCta), findsOneWidget);
  });
}
