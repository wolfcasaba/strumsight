// E13-R17 — Profile Hub (UI-07). A3 (brief §6, §5.3): fully meaningful
// without an account — a login wall would break the offline-first promise.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// A minimal fake of [AuthController] — mirrors the pattern already used in
/// `test/features/community/application/post_composer_test.dart`.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this._user);
  final AuthUser? _user;

  @override
  Future<AuthUser?> build() async => _user;
}

Widget _host({
  bool accountEnabled = false,
  bool communityEnabled = false,
  AuthUser? signedInAs,
  VoidCallback? onOpenCommunity,
}) => ProviderScope(
  overrides: [
    ...preferenceOverrides(),
    appConfigProvider.overrideWithValue(
      AppConfig(
        environment: AppEnvironment.development,
        apiBaseUrl: AppConfig.devApiBaseUrl,
        flags: FeatureFlags(
          accountEnabled: accountEnabled,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          communityEnabled: communityEnabled,
        ),
        diagnosticsToken: AppConfig.devDiagnosticsToken,
        buildMode: 'test',
        appVersion: 'test',
      ),
    ),
    if (accountEnabled)
      authControllerProvider.overrideWith(
        () => _FakeAuthController(signedInAs),
      ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ProfileHubScreen(onOpenCommunity: onOpenCommunity),
  ),
);

const _settingsCtaKey = ValueKey('profile-hub-settings-cta');
const _communityCtaKey = ValueKey('profile-hub-community-cta');

/// Sizes the test surface to a small phone and restores it afterwards.
void _useSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A3 — the Profile Hub is fully meaningful without an account', () {
    testWidgets('accountEnabled off: local-only messaging, no login wall, no '
        'sign-in affordance anywhere on the screen', (tester) async {
      await tester.pumpWidget(_host(accountEnabled: false));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Local profile'), findsOneWidget);
      expect(
        find.text(
          "You're using StrumSight without an account — everything "
          'stays on this device.',
        ),
        findsOneWidget,
      );
      expect(find.text('Sign in'), findsNothing);
      // The rest of the hub — progress, achievements, community, library,
      // settings — is fully present regardless of account state.
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets(
      'accountEnabled on, signed out: Sign in is an offered CHOICE, not a '
      'wall — every other section still renders',
      (tester) async {
        await tester.pumpWidget(_host(accountEnabled: true, signedInAs: null));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Sign in'), findsOneWidget);
        expect(find.text('Progress'), findsOneWidget);
        expect(find.text('Library'), findsOneWidget);
      },
    );

    testWidgets('accountEnabled on, signed in: signed-in state, no sign-in '
        'CTA left on screen', (tester) async {
      await tester.pumpWidget(
        _host(
          accountEnabled: true,
          signedInAs: const AuthUser(id: 1, email: 'player@example.com'),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text("You're signed in."), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    });
  });

  group('Community section reflects the real rollout flag (§5.6 spirit)', () {
    testWidgets('community disabled: names the reason', (tester) async {
      await tester.pumpWidget(_host(communityEnabled: false));
      await tester.pump();

      expect(
        find.text("Community features aren't available in this build yet."),
        findsOneWidget,
      );
    });

    testWidgets('community enabled: shows the enabled message instead', (
      tester,
    ) async {
      await tester.pumpWidget(_host(communityEnabled: true));
      await tester.pump();

      expect(
        find.text('Connect with other players and share your progress.'),
        findsOneWidget,
      );
      expect(
        find.text("Community features aren't available in this build yet."),
        findsNothing,
      );
    });
  });

  // Audit L10 — the Community entry's prominence must follow the sign-in
  // state: logged out, "open Community" only reaches the sign-in wall
  // (`CommunityGateStatus.loggedOut`), so it must not wear the screen's
  // strongest (filled) weight while promising a feed.
  group('audit L10 — Community prominence follows the sign-in state', () {
    testWidgets('signed OUT: an OUTLINED action whose label states the gate — '
        'no filled button anywhere on the screen', (tester) async {
      await tester.pumpWidget(
        _host(
          accountEnabled: true,
          communityEnabled: true,
          onOpenCommunity: () {},
        ),
      );
      await tester.pump();

      expect(find.byKey(_communityCtaKey), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Sign in to use Community'),
        findsOneWidget,
      );
      expect(
        find.byType(FilledButton),
        findsNothing,
        reason:
            'the sign-in wall must never be reached through the screen\'s '
            'strongest action',
      );
    });

    testWidgets('signed IN: the same entry becomes the filled (primary) '
        'action', (tester) async {
      await tester.pumpWidget(
        _host(
          accountEnabled: true,
          communityEnabled: true,
          signedInAs: const AuthUser(id: 1, email: 'player@example.com'),
          onOpenCommunity: () {},
        ),
      );
      await tester.pump();

      expect(
        find.widgetWithText(FilledButton, 'Open Community'),
        findsOneWidget,
      );
      expect(find.text('Sign in to use Community'), findsNothing);
    });

    testWidgets('signed in, but this build has NO Community route: no entry '
        'at all rather than a button that opens nothing', (tester) async {
      await tester.pumpWidget(
        _host(
          accountEnabled: true,
          communityEnabled: true,
          signedInAs: const AuthUser(id: 1, email: 'player@example.com'),
        ),
      );
      await tester.pump();

      expect(find.byKey(_communityCtaKey), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('community module off: no entry, signed in or out', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(accountEnabled: true, onOpenCommunity: () {}),
      );
      await tester.pump();

      expect(find.byKey(_communityCtaKey), findsNothing);
    });
  });

  // Audit U12/U1 — Settings used to be the LAST row, below Community; the
  // first viewport therefore looked complete while hiding the row users
  // reach for most.
  group('audit U12 — Settings sits directly under the header', () {
    testWidgets('Settings is the first body row: above the progress section, '
        'above Community and above Library', (tester) async {
      _useSurface(tester, const Size(360, 640));
      await tester.pumpWidget(_host(communityEnabled: true));
      await tester.pump();

      final settings = tester.getRect(find.byKey(_settingsCtaKey));
      expect(settings.top, lessThan(tester.getRect(find.text('Progress')).top));
      expect(
        settings.top,
        lessThan(tester.getRect(find.text('Community')).top),
      );
      expect(
        settings.top,
        lessThan(
          tester.getRect(find.widgetWithText(OutlinedButton, 'Library')).top,
        ),
      );
    });

    testWidgets('the e2e entry point is unchanged: Settings is still the one '
        'OutlinedButton labelled "Settings"', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(find.widgetWithText(OutlinedButton, 'Settings'), findsOneWidget);
    });
  });

  group('audit U1 — the first viewport must not look complete', () {
    testWidgets('640 dp phone: the section AFTER the header starts (and its '
        'metrics fit) inside the first viewport', (tester) async {
      _useSurface(tester, const Size(360, 640));
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(tester.getRect(find.text('Progress')).bottom, lessThan(640));
      expect(tester.getRect(find.text('Sessions')).bottom, lessThan(640));
    });

    testWidgets('short surface: the list visibly continues past the fold — '
        'the viewport CLIPS it, so it cannot read as a complete screen', (
      tester,
    ) async {
      _useSurface(tester, const Size(360, 480));
      await tester.pumpWidget(_host());
      await tester.pump();

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: 'content below the fold is what the cue announces',
      );
      expect(
        tester.getRect(find.widgetWithText(OutlinedButton, 'Library')).bottom,
        greaterThan(480),
        reason: 'the last row is cut by the bottom edge, not tidily inside it',
      );
    });
  });

  // Audit U13 — the bottom navigation already owns the AI Tutor/Coach
  // destination (`AdaptiveHomeShell`), so a second entry here would be a
  // duplicate. HEAD has none; this cell keeps it that way.
  group('audit U13 — no duplicate AI Tutor entry on Profile', () {
    testWidgets('no Coach/Tutor action on the Profile hub', (tester) async {
      await tester.pumpWidget(_host(accountEnabled: true));
      await tester.pump();

      expect(find.textContaining('Tutor'), findsNothing);
      expect(find.textContaining('Coach'), findsNothing);
    });
  });
}
