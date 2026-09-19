// Round A3 — Today Hub: localised goal metric + non-stranding Vision entry.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

List<Override> _overrides({
  bool visionEnabled = false,
  bool visionSetupEnabled = false,
}) => [
  ...preferenceOverrides(),
  appConfigProvider.overrideWithValue(
    AppConfig(
      environment: AppEnvironment.development,
      apiBaseUrl: AppConfig.devApiBaseUrl,
      flags: FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        visionEnabled: visionEnabled,
        visionSetupEnabled: visionSetupEnabled,
      ),
      diagnosticsToken: AppConfig.devDiagnosticsToken,
      buildMode: 'test',
      appVersion: 'test',
    ),
  ),
];

Widget _host(Locale locale) => ProviderScope(
  overrides: _overrides(),
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TodayHubScreen(now: DateTime(2026, 8, 25)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the daily-goal metric goes through ARB', () {
    testWidgets('hu: the minutes value reads "perc", not the English "min"', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const Locale('hu')));
      await tester.pumpAndSettle();

      expect(
        find.text('0 perc'),
        findsOneWidget,
        reason:
            "'\$todayMinutes min' was a hard-coded English unit "
            '(AGENTS.md §7) — progressGoalOption already carries it',
      );
      expect(find.text('0 min'), findsNothing);
    });

    testWidgets('en: the same metric still reads "min"', (tester) async {
      await tester.pumpWidget(_host(const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('0 min'), findsOneWidget);
    });
  });

  group('the Vision entry point does not strand the user', () {
    testWidgets('tapping it PUSHES the Vision route, so there is something '
        'to pop back to', (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.today,
        routes: [
          GoRoute(
            path: AppRoutes.today,
            builder: (_, _) => TodayHubScreen(now: DateTime(2026, 8, 25)),
          ),
          GoRoute(
            path: AppRoutes.visionSetup,
            builder: (_, _) => const Scaffold(body: Text('vision-setup-probe')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(visionEnabled: true, visionSetupEnabled: true),
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Az E18-vonal két új kártyája (pengetés-kihívás, adatvédelmi ígéret)
      // a Vision-kártyát a teszt-felület alá tolja, ezért előbb láthatóvá
      // kell tenni — enélkül a koppintás elvétené (warnIfMissed).
      final visionCta = find.byType(TextButton);
      await tester.ensureVisible(visionCta);
      await tester.pumpAndSettle();
      await tester.tap(visionCta);
      await tester.pumpAndSettle();

      expect(find.text('vision-setup-probe'), findsOneWidget);
      expect(
        router.canPop(),
        isTrue,
        reason:
            'context.go REPLACES the stack: the Vision screens have no app '
            'bar back affordance of their own, so the user is stranded',
      );
    });
  });
}
