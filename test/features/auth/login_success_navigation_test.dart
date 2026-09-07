// R17 (2026-09-07 audit) — the login screen's way OUT on SUCCESS.
//
// Measured defect: the success listener called a bare `context.pop()`, and
// the Profile hub opened `/login` with `context.go`, which REPLACES the
// stack. The arriving screen was therefore the ONLY page there is, and
// go_router threw `GoError: There is nothing to pop` the moment the
// sign-in succeeded — to the user, "login does not work".
//
// The fix mirrors the screen's own "continue without an account" exit:
// `maybePop` first, and a `go(profileHome)` fallback only when there
// genuinely was nothing to pop. Both halves are pinned below — the
// fallback fires on a one-page stack, and it does NOT fire when the screen
// was pushed (there the user comes back to whatever opened it).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_auth.dart';

const _signInAction = 'Sign in';

/// The routes the login screen can be reached from and leave for. The two
/// stubs are deliberately DIFFERENT paths, so "popped back to what opened
/// me" and "fell back to the profile home" can never be confused.
GoRouter _loginRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: <RouteBase>[
    GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
    GoRoute(path: AppRoutes.profileHome, builder: _stub),
    GoRoute(path: AppRoutes.settings, builder: _stub),
  ],
);

Widget _stub(BuildContext _, GoRouterState state) =>
    Scaffold(body: Text('STUB ${state.uri.path}'));

Future<GoRouter> _open(
  WidgetTester tester, {
  required String initialLocation,
  bool pushLogin = false,
}) async {
  final router = _loginRouter(initialLocation);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushLogin) {
    router.push(AppRoutes.login);
    await tester.pumpAndSettle();
  }
  expect(find.byType(LoginScreen), findsOneWidget);
  return router;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _signIn(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'player@strumsight.app');
  await tester.enterText(fields.at(1), 'password123');
  await tester.pump();
  await _tap(tester, find.widgetWithText(FilledButton, _signInAction));
}

void main() {
  group('LoginScreen — a sign-in always leaves the screen', () {
    // The exact state the defect needed: `/login` reached by a `go()` that
    // replaced the stack, so `pop()` had nothing to pop and threw.
    testWidgets('go()-opened: sign-in lands on the profile', (tester) async {
      final router = await _open(tester, initialLocation: AppRoutes.login);
      expect(router.canPop(), isFalse);

      await _signIn(tester);

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.profileHome);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('STUB ${AppRoutes.profileHome}'), findsOneWidget);
    });

    // The other half: where there IS something to pop, the fallback must
    // stay out of the way — the user returns to what opened the screen.
    testWidgets('pushed: sign-in pops back to Settings', (tester) async {
      final router = await _open(
        tester,
        initialLocation: AppRoutes.settings,
        pushLogin: true,
      );
      expect(router.canPop(), isTrue);

      await _signIn(tester);

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.settings);
      expect(find.text('STUB ${AppRoutes.settings}'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    // Both exits share ONE implementation; this is the cell that proves
    // the shared helper still serves the A1 "no account needed" path.
    testWidgets('no-account exit also leaves a lone page', (tester) async {
      final router = await _open(tester, initialLocation: AppRoutes.login);

      await _tap(tester, find.byKey(const Key('authContinueWithoutAccount')));

      expect(tester.takeException(), isNull);
      expect(router.state.uri.path, AppRoutes.profileHome);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });
}
