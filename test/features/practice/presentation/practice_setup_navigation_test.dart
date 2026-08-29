// Heal round E12-R11 / H2 (ADR 0470) — the Setup → Session hand-off.
//
// MEASURED root cause (reproduction, `main @ 8bdcfff9`):
//
//   grep -rn "AppRoutes.practiceSession" lib/
//     lib/app/routing/app_route.dart:24            (the constant)
//     lib/app/routing/app_router.dart:342          (the route registration)
//     lib/app/routing/adaptive_shell_routes.dart:41 (a stage-route predicate)
//
// Zero `lib/**` callers navigated to `/practice/session`: the Setup
// screen's Start handler dispatched `PreparePractice` and then showed a
// SnackBar, staying put. E02-R12 deferred the navigation on purpose
// ("Kör 13 brings the session route", `practice_setup_screen.dart`
// header), but `practice_setup_screen.dart` sat in E02-R13's forbidden
// zone and in E02-R21's off-list set, so no round ever closed the
// deferral. The E12-R11 E2E harness had to supply the missing link from
// the test — the L273 error class — which halted that round (H2).
//
// These two cells are the regression: they drive the REAL router and the
// REAL provider graph (platform edges faked, per the E02-R21 rule that
// production wiring must not be bypassed by constructor-injected fakes),
// and they fail on the pre-heal tree.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/practice/presentation/widgets/practice_controls.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_auth.dart';
import '../../../support/fake_engines.dart';
import '../../../support/preference_store.dart';

const _kPracticeId = 'fixture.heal.setup-nav.v1';

final _kDefinition = PracticeDefinition(
  id: _kPracticeId,
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestRoutingTitle',
  descriptionKey: 'practiceCatalogTestRoutingDescription',
  mode: PracticeMode.strumPattern,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(100),
  totalBeats: BeatPosition.quarters(16),
  events: List<PracticeEvent>.unmodifiable([
    for (var i = 0; i < 16; i++)
      PracticeEvent(
        id: '$_kPracticeId.e$i',
        position: BeatPosition.quarters(i),
        direction: StrumDirection.down,
      ),
  ]),
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: const ['heal'],
  displayTitle: 'Setup navigation fixture',
);

class _SingleDefRepository implements PracticeCatalogRepository {
  const _SingleDefRepository();
  @override
  List<PracticeDefinition> all() =>
      List<PracticeDefinition>.unmodifiable([_kDefinition]);
  @override
  PracticeDefinition? byId(String id) =>
      id == _kDefinition.id ? _kDefinition : null;
  @override
  List<PracticeDefinition> byMode(PracticeMode mode) =>
      const <PracticeDefinition>[];
  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      const <PracticeDefinition>[];
}

AppConfig _config() => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: const FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    practiceEngineV2Enabled: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

/// Pumps the real app router on the real Setup route for [_kDefinition].
/// Only platform edges are faked (`strumEngineProvider`, audio, auth,
/// preferences) — the practice provider graph itself is production wiring.
Future<ProviderContainer> _pumpSetup(WidgetTester tester) async {
  final engine = FakeStrumEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(engine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      accountEnabledProvider.overrideWithValue(false),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      appConfigProvider.overrideWithValue(_config()),
      practiceCatalogRepositoryProvider.overrideWithValue(
        const _SingleDefRepository(),
      ),
    ],
  );
  final router = container.read(routerProvider);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await engine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  router.go('${AppRoutes.practiceSetup}?id=$_kPracticeId');
  await tester.pumpAndSettle();
  expect(find.byType(PracticeSetupScreen), findsOneWidget);
  return container;
}

/// Scrolls the Start CTA into the viewport and taps it. The Start button
/// sits at the bottom of a long form — the same pattern
/// `practice_setup_screen_test.dart` uses.
Future<void> _tapStart(WidgetTester tester) async {
  final start = find.widgetWithText(FilledButton, 'Start practice');
  await tester.scrollUntilVisible(
    start,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(start);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'R1: a valid Start on the Setup screen navigates to /practice/session',
    (tester) async {
      final container = await _pumpSetup(tester);

      await _tapStart(tester);

      expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        AppRoutes.practiceSession,
        reason:
            'the product itself must walk Setup → Session; before the heal '
            'round no lib/** caller navigated to the session route, so the '
            'E12-R11 E2E harness had to issue the router.go itself (L273).',
      );
      expect(find.byType(PracticeSessionScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('R2: the session screen arrives with a live host, not the '
      '"session unavailable" state', (tester) async {
    final container = await _pumpSetup(tester);

    await _tapStart(tester);

    expect(
      container.read(practiceSessionHostProvider),
      isNotNull,
      reason:
          'the activation chain (practiceActiveSessionInputsProvider → '
          'practiceSessionControllerProvider) is auto-dispose; the '
          'product must keep it observed across the hand-off, otherwise '
          'the controller the prepare sink just built is torn down '
          'before the Session screen reads it.',
    );
    // The screen renders its real controls only when `host != null`;
    // with a null host it falls back to the `_Unavailable` empty state,
    // which carries no `PracticeControls`.
    expect(find.byType(PracticeControls), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
