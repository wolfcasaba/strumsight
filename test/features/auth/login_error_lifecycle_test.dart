// R15/A — the failure message on the login screen must belong to the attempt
// the user is looking at.
//
// Measured defect: `LoginScreen` painted `authFailureMessage(l10n,
// auth.error)` for as long as `AuthController` held an `AsyncError`. After a
// failed sign-up (409 "e-mail already taken") the user toggled to sign-in and
// the sign-up error kept standing over the sign-in form until the next
// submit — and the same the other way round.
//
// The fix is SCREEN-LOCAL on purpose: the controller keeps its honest
// `AsyncError` (no faked `AsyncData(null)` "signed out fine" state), the
// screen just stops repainting a failure the user has answered by changing
// what they are doing. Both halves are pinned below — the dismissal happens,
// and it never swallows the NEXT failure.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_auth.dart';

const _invalidCredentials = 'Incorrect email or password';
const _emailTaken = 'That email is already registered';
const _emailTakenHint = 'Already have an account? Switch to sign-in below.';
const _networkError = "Can't reach the server. Check your connection.";
const _unknownError = 'Something went wrong. Please try again.';

const _toSignUp = 'New here? Create an account';
const _toSignIn = 'Have an account? Sign in';
const _signInAction = 'Sign in';
const _signUpAction = 'Create account';

/// The PUSHED entry path (from Settings) — the same harness the E13-R35
/// cells use, so a success would have a route to pop back to.
Future<void> _openLogin(WidgetTester tester, FakeAuthRepository auth) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        authRepositoryProvider.overrideWithValue(auth),
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

/// Scrolls [target] into view before tapping it: the failure message plus
/// its next-step hint make the form taller than the plain one the other
/// cells pump, and an off-screen control cannot be tapped.
Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, String action) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'player@strumsight.app');
  await tester.enterText(fields.at(1), 'password123');
  await tester.pump();
  await _tap(tester, find.widgetWithText(FilledButton, action));
}

Future<void> _toggle(WidgetTester tester, String label) async {
  await _tap(tester, find.text(label));
}

void main() {
  group('LoginScreen — the visible failure follows the form', () {
    // The stale-error defect itself: the sign-in failure must not survive
    // the switch to the sign-up form, which it does not answer.
    testWidgets('toggling the mode drops the old failure', (tester) async {
      final auth = FakeAuthRepository()
        ..loginFailure = const AuthenticationFailure(
          code: FailureCode.authInvalidCredentials,
        );
      await _openLogin(tester, auth);

      await _submit(tester, _signInAction);
      expect(find.text(_invalidCredentials), findsOneWidget);

      await _toggle(tester, _toSignUp);

      expect(find.text(_invalidCredentials), findsNothing);
      // The controller still holds its error — only the screen stopped
      // showing it. The sign-up form is what the user now sees.
      expect(find.text('Create your account'), findsOneWidget);
    });

    // The other half of the contract: a dismissal covers exactly the
    // submission it dismissed, never the next one.
    testWidgets('a new failure in the other mode is shown', (tester) async {
      final auth = FakeAuthRepository()
        ..loginFailure = const AuthenticationFailure(
          code: FailureCode.authInvalidCredentials,
        )
        ..registerFailure = const ValidationFailure(
          code: FailureCode.validationEmailTaken,
        );
      await _openLogin(tester, auth);

      await _submit(tester, _signInAction);
      expect(find.text(_invalidCredentials), findsOneWidget);

      await _toggle(tester, _toSignUp);
      expect(find.text(_invalidCredentials), findsNothing);

      await _submit(tester, _signUpAction);

      expect(find.text(_emailTaken), findsOneWidget);
      expect(find.text(_invalidCredentials), findsNothing);
    });

    // A 409 has exactly one obvious next step; the screen now names it
    // instead of leaving the user on a form that can never succeed.
    testWidgets('a sign-up 409 offers the sign-in step', (tester) async {
      final auth = FakeAuthRepository()
        ..registerFailure = const ValidationFailure(
          code: FailureCode.validationEmailTaken,
        );
      await _openLogin(tester, auth);

      await _toggle(tester, _toSignUp);
      await _submit(tester, _signUpAction);

      expect(find.text(_emailTaken), findsOneWidget);
      expect(find.text(_emailTakenHint), findsOneWidget);

      // Taking that step clears both the message and its hint.
      await _toggle(tester, _toSignIn);

      expect(find.text(_emailTaken), findsNothing);
      expect(find.text(_emailTakenHint), findsNothing);
    });

    // Editing a field is the other "I have moved on" signal — and the very
    // next submission still reports its own outcome.
    testWidgets('editing a field clears the old failure', (tester) async {
      final auth = FakeAuthRepository()
        ..loginFailure = const AuthenticationFailure(
          code: FailureCode.authInvalidCredentials,
        );
      await _openLogin(tester, auth);

      await _submit(tester, _signInAction);
      expect(find.text(_invalidCredentials), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), 'password456');
      await tester.pump();
      expect(find.text(_invalidCredentials), findsNothing);

      auth.loginFailure = const NetworkFailure(
        code: FailureCode.networkUnavailable,
      );
      await _submit(tester, _signInAction);

      expect(find.text(_networkError), findsOneWidget);
    });

    // The state the E13-R35 pixel golden renders: a freshly opened screen
    // carries no failure copy at all.
    testWidgets('the default state shows no failure text', (tester) async {
      await _openLogin(tester, FakeAuthRepository());

      expect(find.text(_invalidCredentials), findsNothing);
      expect(find.text(_emailTaken), findsNothing);
      expect(find.text(_emailTakenHint), findsNothing);
      expect(find.text(_networkError), findsNothing);
      expect(find.text(_unknownError), findsNothing);
    });
  });
}
