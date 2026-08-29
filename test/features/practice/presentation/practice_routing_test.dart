import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_auth.dart';
import '../../../support/fake_engines.dart';
import '../../../support/preference_store.dart';

const _kPracticeId = 'fixture.routing.v1';

final _kRoutingDefinition = PracticeDefinition(
  id: _kPracticeId,
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestRoutingTitle',
  descriptionKey: 'practiceCatalogTestRoutingDescription',
  mode: PracticeMode.strumPattern,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(100),
  totalBeats: BeatPosition.quarters(16),
  events: const [],
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: const ['routing'],
  displayTitle: 'Routing fixture',
);

class _RoutingRepository implements PracticeCatalogRepository {
  const _RoutingRepository();
  @override
  List<PracticeDefinition> all() =>
      List<PracticeDefinition>.unmodifiable([_kRoutingDefinition]);
  @override
  PracticeDefinition? byId(String id) =>
      id == _kRoutingDefinition.id ? _kRoutingDefinition : null;
  @override
  List<PracticeDefinition> byMode(PracticeMode mode) =>
      const <PracticeDefinition>[];
  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      const <PracticeDefinition>[];
}

AppConfig _configFor(bool practiceEngineV2Enabled) {
  return AppConfig.resolve(
    environment: AppEnvironment.development,
    apiBaseUrl: AppConfig.devApiBaseUrl,
    flags: FeatureFlags(
      accountEnabled: false,
      diagnosticsEnabled: false,
      labModeAvailable: false,
      practiceEngineV2Enabled: practiceEngineV2Enabled,
    ),
    diagnosticsToken: AppConfig.devDiagnosticsToken,
    buildMode: 'test',
    appVersion: 'test',
  );
}

Future<ProviderContainer> _pumpRouter(
  WidgetTester tester, {
  required bool practiceOn,
  required String startLocation,
}) async {
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
      appConfigProvider.overrideWithValue(_configFor(practiceOn)),
      practiceCatalogRepositoryProvider.overrideWithValue(
        const _RoutingRepository(),
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
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  router.go(startLocation);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('A7: flag ON, /practice builds the Hub', (tester) async {
    await _pumpRouter(
      tester,
      practiceOn: true,
      startLocation: AppRoutes.practiceHub,
    );
    expect(find.byType(PracticeHubScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A7: flag ON, /practice/setup?id=<known> builds the Setup', (
    tester,
  ) async {
    await _pumpRouter(
      tester,
      practiceOn: true,
      startLocation: '${AppRoutes.practiceSetup}?id=$_kPracticeId',
    );
    expect(find.byType(PracticeSetupScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A7: flag ON, /practice/setup?id=<unknown> shows the localized error',
    (tester) async {
      await _pumpRouter(
        tester,
        practiceOn: true,
        startLocation: '${AppRoutes.practiceSetup}?id=does-not-exist',
      );
      expect(find.text('Practice unavailable'), findsOneWidget);
      expect(find.text("This practice isn't available."), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A7: flag ON, /practice/setup (no id) shows the localized error',
    (tester) async {
      await _pumpRouter(
        tester,
        practiceOn: true,
        startLocation: AppRoutes.practiceSetup,
      );
      expect(find.text('Practice unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A7: flag OFF, /practice falls back to live (existing onException)',
    (tester) async {
      await _pumpRouter(
        tester,
        practiceOn: false,
        startLocation: AppRoutes.practiceHub,
      );
      // The router's existing onException redirects unknown paths to live.
      expect(find.byType(LiveScreen), findsOneWidget);
      expect(find.byType(PracticeHubScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A7: flag OFF, /practice/setup also falls back to live', (
    tester,
  ) async {
    await _pumpRouter(
      tester,
      practiceOn: false,
      startLocation: '${AppRoutes.practiceSetup}?id=$_kPracticeId',
    );
    expect(find.byType(LiveScreen), findsOneWidget);
    expect(find.byType(PracticeSetupScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
