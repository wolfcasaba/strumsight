// Round A3 — adaptive-shell destination labels are real navigation strings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/home_shell.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// The Profile destination used `tutorProfileTitle` ("Tutor profile" /
/// "Tutor profil") — the AI-tutor's OWN profile screen title, borrowed
/// because no nav key existed yet. `profileHubTitle` ("Profile" / "Profil")
/// has existed since E13-R17 and is what `ProfileHubScreen` (the screen this
/// destination actually opens) puts in its own app bar, so the tab and its
/// destination disagreed in both locales.
void main() {
  Future<void> pumpShell(WidgetTester tester, Locale locale) async {
    final router = GoRouter(
      initialLocation: '/branch0',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => AdaptiveHomeShell(
            navigationShell: navigationShell,
            location: state.uri.path,
          ),
          branches: [
            for (var i = 0; i < 5; i++)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/branch$i',
                    builder: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: SsLightTheme.data(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('en: the Profile destination is labelled "Profile", not the '
      "tutor screen's own title", (tester) async {
    await pumpShell(tester, const Locale('en'));

    expect(find.text('Profile'), findsOneWidget);
    expect(
      find.text('Tutor profile'),
      findsNothing,
      reason: 'tutorProfileTitle titles the AI tutor profile SCREEN; the '
          'Profile tab opens ProfileHubScreen',
    );
  });

  testWidgets('hu: the Profile destination is labelled "Profil"', (
    tester,
  ) async {
    await pumpShell(tester, const Locale('hu'));

    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Tutor profil'), findsNothing);
  });
}
