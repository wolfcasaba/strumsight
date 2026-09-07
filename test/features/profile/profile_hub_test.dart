// E13-R17 — Profile Hub (UI-07). A3 (brief §6, §5.3): fully meaningful
// without an account — a login wall would break the offline-first promise.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
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
  child: const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ProfileHubScreen(),
  ),
);

/// Every destination the hub links to, as `STUB <path>`: these cells
/// measure the NAVIGATION, not the target screens (each has its own
/// widget test). R17 (2026-09-07 audit) added the three that were reached
/// with a stack-replacing `go`.
GoRouter _hubRouter() => GoRouter(
  initialLocation: AppRoutes.profileHome,
  routes: <RouteBase>[
    GoRoute(
      path: AppRoutes.profileHome,
      builder: (_, _) => const ProfileHubScreen(),
    ),
    GoRoute(path: AppRoutes.tutorHome, builder: _stub),
    GoRoute(path: AppRoutes.gamificationHub, builder: _stub),
    GoRoute(path: AppRoutes.community, builder: _stub),
    GoRoute(path: AppRoutes.login, builder: _stub),
  ],
);

Widget _stub(BuildContext _, GoRouterState state) =>
    Scaffold(body: Text('STUB ${state.uri.path}'));

/// WP-D harness — a valós Profil hub egy MINIMÁLIS go_router alatt. Az
/// AI Tanár helyén `STUB <path>` áll: a cella a NAVIGÁCIÓT méri, nem a
/// tutor-képernyő tartalmát (annak saját widget-tesztje van).
Widget _routerHost({
  required bool aiTutorEnabled,
  bool accountEnabled = false,
  bool communityEnabled = false,
  GoRouter? router,
}) {
  return ProviderScope(
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
            aiTutorEnabled: aiTutorEnabled,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
      if (accountEnabled)
        authControllerProvider.overrideWith(() => _FakeAuthController(null)),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router ?? _hubRouter(),
    ),
  );
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

  // -------------------------------------------------------------------
  // WP-D (2026-09-06) — az AI Tanár belépési pontja.
  //
  // MÉRT hiány: a `/tutor/*` útvonalak regisztrálva voltak, de a
  // szállított felületről SEMMI nem vezetett rájuk. A `/coach` héj-célpont
  // csak az adaptív héj bekapcsolt állásán látszik; a Profil hub gombja
  // attól függetlenül elérhető.
  // -------------------------------------------------------------------
  group('WP-D — the AI Tutor entry point', () {
    testWidgets('aiTutorEnabled on: the entry navigates to /tutor/home', (
      tester,
    ) async {
      await tester.pumpWidget(_routerHost(aiTutorEnabled: true));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('profile-hub-tutor-entry')));
      await tester.pumpAndSettle();

      expect(find.text('STUB ${AppRoutes.tutorHome}'), findsOneWidget);
    });

    testWidgets('aiTutorEnabled off: the entry is absent (the route is not '
        'registered either)', (tester) async {
      await tester.pumpWidget(_routerHost(aiTutorEnabled: false));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('profile-hub-tutor-entry')),
        findsNothing,
      );
    });
  });

  // -------------------------------------------------------------------
  // R17 (2026-09-07 audit) — the hub's outgoing edges PUSH.
  //
  // MÉRT hiba: mind a három belépő `context.go`-val nyílt, ami TOP-LEVEL
  // útvonalra lépve KICSERÉLI a stacket — az érkező képernyőn nincs
  // vissza-nyíl (`canPop == false`, az AppBar nem rajzol leadinget) és az
  // adaptív héj alsó sávja sincs ott, tehát csak a rendszer
  // vissza-gombja — az appból kilépve — vezetett vissza.
  // -------------------------------------------------------------------
  group('R17 — the hub entries push, so the target can come back', () {
    for (final entry in const <({String key, String path})>[
      (key: 'profile-hub-achievements-entry', path: AppRoutes.gamificationHub),
      (key: 'profile-hub-community-entry', path: AppRoutes.community),
      (key: 'profile-hub-sign-in-entry', path: AppRoutes.login),
    ]) {
      testWidgets('${entry.key} pushes ${entry.path}', (tester) async {
        final router = _hubRouter();
        await tester.pumpWidget(
          _routerHost(
            aiTutorEnabled: false,
            accountEnabled: true,
            communityEnabled: true,
            router: router,
          ),
        );
        await tester.pumpAndSettle();

        final cta = find.byKey(ValueKey(entry.key));
        await tester.ensureVisible(cta);
        await tester.pumpAndSettle();
        await tester.tap(cta);
        await tester.pumpAndSettle();

        // `state.uri`, NOT `currentConfiguration.uri` — after a push the
        // latter reports the BOTTOM of the stack (see the WP-D cells).
        expect(router.state.uri.path, entry.path);
        expect(tester.takeException(), isNull);

        // The measure: the arriving screen HAS a way back. Under `go`
        // the stack was one page deep and this was false.
        expect(router.canPop(), isTrue);
        router.pop();
        await tester.pumpAndSettle();
        expect(router.state.uri.path, AppRoutes.profileHome);
      });
    }
  });
}
