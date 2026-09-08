import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Audit H5 — the four Quick tools opened with `context.go`, which REPLACES
/// the navigation stack: one BACK from the Metronome left the app for the
/// launcher instead of returning to the hub. They must PUSH.
Future<GoRouter> _pumpHub(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: AppRoutes.practiceHub,
    routes: [
      GoRoute(
        path: AppRoutes.practiceHub,
        builder: (_, _) => const PracticeAreaHubScreen(),
      ),
      for (final path in <String>[
        AppRoutes.practiceLive,
        AppRoutes.practiceTuner,
        AppRoutes.practiceMetronome,
        AppRoutes.practiceChords,
        AppRoutes.practiceSetup,
      ])
        GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  final tools = <String, String>{
    l10n.navLive: AppRoutes.practiceLive,
    l10n.liveTuner: AppRoutes.practiceTuner,
    l10n.metronomeTitle: AppRoutes.practiceMetronome,
    l10n.chordLibraryTitle: AppRoutes.practiceChords,
  };

  for (final entry in tools.entries) {
    testWidgets('the "${entry.key}" quick tool PUSHES ${entry.value}', (
      tester,
    ) async {
      final router = await _pumpHub(tester);
      expect(
        router.canPop(),
        isFalse,
        reason: 'the hub itself is the only entry on the stack',
      );

      final tool = find.text(entry.key);
      expect(tool, findsOneWidget);
      await tester.ensureVisible(tool);
      await tester.tap(tool);
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), entry.value);
      // `go` would have REPLACED the hub — nothing left to pop back to.
      expect(
        router.canPop(),
        isTrue,
        reason: 'BACK from a quick tool must return to the Practice hub',
      );

      router.pop();
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), AppRoutes.practiceHub);
    });
  }
}
