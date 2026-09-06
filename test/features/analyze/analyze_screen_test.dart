import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/analyze/screens/analyze_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

void main() {
  testWidgets('Analyze tab shows the Record CTA (no more "coming soon")', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    // E15-R02 (ADR 0467 D9): the app boots on the adaptive shell's /today
    // entry point now; Analyze lives at AppRoutes.practiceAnalyze.
    container.read(routerProvider).go(AppRoutes.practiceAnalyze);
    await tester.pumpAndSettle();

    expect(find.text('Record'), findsOneWidget);
    expect(find.textContaining('timeline'), findsOneWidget); // intro copy
    expect(find.textContaining('Coming in'), findsNothing); // placeholder gone
  });

  _wpDEntryPointTests();
}

// ---------------------------------------------------------------------
// WP-D (2026-09-06) — a V2 felvételi folyamat BELÉPÉSI PONTJA.
//
// MÉRT hiány: az `/analysis/capture` (és mögötte a felvevő + a feldolgozó
// képernyő) REGISZTRÁLVA volt, de a szállított felületről EGYETLEN
// hivatkozás sem vezetett rá — csak a folyamat saját, belső élei
// (`onCancel`) nevezték meg. A felhasználó számára ez ugyanaz, mintha a
// három képernyő nem létezne.
//
// A cella MINIMÁLIS routert használ (a klub-lista WP-C precedense): a
// mérés a NAVIGÁCIÓ, nem a cél-képernyő tartalma — annak saját
// widget-tesztjei vannak (`analysis_home_screen` cellái).
// ---------------------------------------------------------------------

AppConfig _analyzeConfig({required bool audioAnalysisV2Enabled}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    audioAnalysisV2Enabled: audioAnalysisV2Enabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Widget _analyzeHost({required bool audioAnalysisV2Enabled}) {
  final router = GoRouter(
    initialLocation: AppRoutes.practiceAnalyze,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.practiceAnalyze,
        builder: (_, _) => const Scaffold(body: AnalyzeScreen()),
      ),
      GoRoute(
        path: AppRoutes.analysisCapture,
        builder: (_, state) => Scaffold(body: Text('STUB ${state.uri.path}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ...preferenceOverrides(),
      appConfigProvider.overrideWithValue(
        _analyzeConfig(audioAnalysisV2Enabled: audioAnalysisV2Enabled),
      ),
    ],
    child: MaterialApp.router(
      theme: SsLightTheme.data(),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en')],
      routerConfig: router,
    ),
  );
}

void _wpDEntryPointTests() {
  testWidgets('WP-D — the Analyze home opens the V2 capture flow', (
    tester,
  ) async {
    await tester.pumpWidget(_analyzeHost(audioAnalysisV2Enabled: true));
    await tester.pump();

    await tester.tap(find.byKey(const Key('analyze-open-analysis-v2')));
    await tester.pumpAndSettle();

    expect(find.text('STUB ${AppRoutes.analysisCapture}'), findsOneWidget);
  });

  testWidgets('WP-D — the entry is ABSENT when audioAnalysisV2Enabled is off '
      '(the route is not registered either)', (tester) async {
    // A gomb kapuja bájtra a routeré. Ha itt megjelenne, egy nem létező
    // címre mutatna, és a router `onException`-je dobná vissza a
    // felhasználót — halott vezérlő.
    await tester.pumpWidget(_analyzeHost(audioAnalysisV2Enabled: false));
    await tester.pump();

    expect(find.byKey(const Key('analyze-open-analysis-v2')), findsNothing);
  });
}
