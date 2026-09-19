// R12 (audit §5.2) — the tutor practice-plan preview finally has an
// ON-SCREEN entry.
//
// MEASURED gap: `/tutor/plan-preview` and its real draft producer have
// existed since R9, but no shipped surface pushed the route, so the preview
// was unreachable. The CTA lives on the Tutor Profile screen (the screen
// that owns the goals the producer turns into a plan) because TutorHome and
// TutorChat are pixel-pinned goldens (e13_r29). Cells:
//
//   T1 — the CTA renders when `aiTutorEnabled` is on,
//   T2 — tapping it navigates to `AppRoutes.tutorPlanPreview`,
//   T3 — with the flag off the CTA is absent, because the ROUTE is absent
//        too (`app_router.dart` registers it inside the same flag block).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_profile_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/preference_store.dart';

const _cta = Key('tutorProfilePlanPreview');
const _target = 'plan-preview-target';

AppConfig _config({required bool aiTutorEnabled}) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    aiTutorEnabled: aiTutorEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Widget _app({required bool aiTutorEnabled}) {
  final config = _config(aiTutorEnabled: aiTutorEnabled);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const TutorProfileScreen()),
      GoRoute(
        path: AppRoutes.tutorPlanPreview,
        builder: (_, _) => const Scaffold(body: Text(_target)),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ...preferenceOverrides(),
      appConfigProvider.overrideWithValue(config),
    ],
    child: MaterialApp.router(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('T1 renders the plan-preview CTA', (tester) async {
    await tester.pumpWidget(_app(aiTutorEnabled: true));
    await tester.pump();

    expect(find.byKey(_cta), findsOneWidget);
  });

  testWidgets('T2 the CTA opens the plan preview', (tester) async {
    await tester.pumpWidget(_app(aiTutorEnabled: true));
    await tester.pump();

    // The CTA is the last row of a scrolling screen: at the default test
    // viewport it can sit below the fold, and `tap` would then miss.
    await tester.ensureVisible(find.byKey(_cta));
    await tester.pump();
    await tester.tap(find.byKey(_cta));
    await tester.pumpAndSettle();

    expect(find.text(_target), findsOneWidget);
  });

  testWidgets('T3 no CTA when the tutor flag is off', (tester) async {
    await tester.pumpWidget(_app(aiTutorEnabled: false));
    await tester.pump();

    expect(find.byKey(_cta), findsNothing);
  });
}
