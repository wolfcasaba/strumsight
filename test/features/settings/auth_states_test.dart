// E13-R35 — A1 (a "continue without an account" path is always offered from
// the login screen) and A2 (an authentication failure never leaks technical
// detail, only the stable localized message).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_auth.dart';

Future<void> _pumpPushedFromHome(
  WidgetTester tester, {
  FakeAuthRepository? auth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                ),
                child: const Text('open-login'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-login'));
  await tester.pumpAndSettle();
}

/// Reproduces the OTHER real entry path (javító kör 1, F4): the profile hub
/// reaches the login screen with `context.go(AppRoutes.login)`, which
/// REPLACES the location instead of pushing a route — so there is nothing
/// for a plain `Navigator.maybePop()` to pop back to. A real [GoRouter] is
/// required to reproduce this; the plain-`Navigator` harness above
/// ([_pumpPushedFromHome]) cannot exercise it, because a `push` always
/// leaves something poppable.
Future<GoRouter> _pumpGoEntry(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: AppRoutes.profileHome,
    routes: [
      GoRoute(
        path: AppRoutes.profileHome,
        builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
    ],
  );
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
  router.go(AppRoutes.login);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group(
    'A1 — the login screen always offers a way forward without a session',
    () {
      testWidgets(
        '"Continue without an account" is present and pops back without logging in',
        (tester) async {
          await _pumpPushedFromHome(tester);
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(
            find.byKey(const Key('authContinueWithoutAccount')),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const Key('authContinueWithoutAccount')));
          await tester.pumpAndSettle();

          expect(find.byType(LoginScreen), findsNothing);
          expect(find.text('open-login'), findsOneWidget);
        },
      );

      testWidgets(
        'the action is offered on the sign-up form too, not just sign-in',
        (tester) async {
          await _pumpPushedFromHome(tester);
          await tester.tap(find.text('New here? Create an account'));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('authContinueWithoutAccount')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        // Javító kör 1, F4: the profile hub reaches this screen via
        // `context.go(AppRoutes.login)` (a stack REPLACE, not a push) — a
        // real GoRouter is required to reproduce this, unlike the two cells
        // above which use a plain `Navigator.push` harness.
        'on the go()-entry path (no route to pop back to) the action still '
        'leaves the login screen, via a real router',
        (tester) async {
          final router = await _pumpGoEntry(tester);
          expect(find.byType(LoginScreen), findsOneWidget);

          await tester.tap(find.byKey(const Key('authContinueWithoutAccount')));
          await tester.pumpAndSettle();

          expect(find.byType(LoginScreen), findsNothing);
          expect(
            router.routerDelegate.currentConfiguration.uri.toString(),
            isNot(AppRoutes.login),
          );
        },
      );
    },
  );

  group('A2 — an authentication failure never leaks technical detail', () {
    testWidgets('invalid credentials show only the stable, localized message', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..loginFailure = const AuthenticationFailure(
          code: FailureCode.authInvalidCredentials,
        );
      await _pumpPushedFromHome(tester, auth: auth);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'player@strumsight.app');
      await tester.enterText(fields.at(1), 'wrongpassword');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect email or password'), findsOneWidget);
      // Never the raw stable code, never a Dart exception string.
      expect(
        find.textContaining(FailureCode.authInvalidCredentials),
        findsNothing,
      );
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets(
      'an unrecognised failure shape falls back to the generic message, '
      'never showing nothing or raw internals',
      (tester) async {
        // A failure whose `code` this UI mapping does not special-case —
        // authFailureMessage's fallback branch (any AppFailure the switch in
        // auth_failure_message.dart does not name resolves to the generic
        // unknown-error copy, never blank and never the code itself).
        final auth = FakeAuthRepository()
          ..loginFailure = const StorageFailure(code: FailureCode.storageRead);
        await _pumpPushedFromHome(tester, auth: auth);

        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'player@strumsight.app');
        await tester.enterText(fields.at(1), 'password123');
        await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
        await tester.pumpAndSettle();

        expect(
          find.text('Something went wrong. Please try again.'),
          findsOneWidget,
        );
        expect(find.textContaining(FailureCode.storageRead), findsNothing);
      },
    );
  });
}
