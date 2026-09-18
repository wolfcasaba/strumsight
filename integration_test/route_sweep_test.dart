// On-device route sweep (round strum-strings, systematic emulator testing).
//
// Boots the REAL StrumSightApp with the E12-R11 deterministic harness (fake
// engines / network / clock — the same profile the e2e walkthrough uses),
// then visits every parameter-free route in the catalogue: navigate, let it
// settle for a bounded time, collect every Flutter error thrown while it was
// on screen, take a screenshot. Prints a route → verdict table and fails only
// at the end so one broken screen never hides the others.
//
// Two boots, because a route's existence depends on the flag set: the first
// sweeps the routes registered under `e2eDefaultFlags`, the second turns on
// the adaptive shell and vision and sweeps exactly the routes that need
// them. See `_flaggedRoutes` for why one boot would report a false green,
// and the block under it for the routes no boot can cover at all.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/route_sweep_test.dart -d emulator-5554
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';

import '../test/support/e2e_harness.dart';

/// Every parameter-free route registered under the harness' default flag
/// set ([e2eDefaultFlags]), swept on the first boot.
///
/// Routes that only exist behind the adaptive-shell / vision flags live in
/// [_flaggedRoutes] instead; routes that need a payload or a started host are
/// not swept at all (see the block below).
const _routes = <String>[
  AppRoutes.live,
  AppRoutes.analyze,
  AppRoutes.learn,
  AppRoutes.library,
  AppRoutes.librarySession,
  AppRoutes.settings,
  AppRoutes.tuner,
  AppRoutes.metronome,
  AppRoutes.calibrate,
  AppRoutes.streak,
  AppRoutes.progress,
  AppRoutes.songs,
  AppRoutes.setlists,
  AppRoutes.chords,
  AppRoutes.practiceHub,
  AppRoutes.practiceSetup,
  AppRoutes.practiceGeneratorSetup,
  AppRoutes.practiceGeneratorToday,
  AppRoutes.songTrainerLibrary,
  AppRoutes.songTrainerImport,
  AppRoutes.songTrainerNewEditor,
  AppRoutes.tutorHome,
  AppRoutes.tutorChat,
  AppRoutes.tutorProfile,
  AppRoutes.tutorPrivacy,
  AppRoutes.tutorData,
  AppRoutes.gamificationHub,
  AppRoutes.achievements,
  AppRoutes.quests,
  AppRoutes.streakDetail,
  AppRoutes.rewardInbox,
  AppRoutes.levelDetail,
  AppRoutes.welcome,
  AppRoutes.recovery,
  AppRoutes.login,
];

/// Routes that exist ONLY behind a feature flag the default boot leaves off,
/// swept below on a SECOND boot that turns exactly those flags on.
///
/// Sweeping them on the default boot is a FALSE GREEN, not a failure: the
/// router installs `onException: (_, _, router) => router.go(entryLocation)`
/// (`app_router.dart`), so an unregistered location raises no Flutter error
/// — the sweep silently lands on the entry screen, records `ok`, and saves a
/// screenshot under the route's own name showing a different screen.
const _flaggedRoutes = <String>[
  // `adaptiveShellEnabled` — the shell's entry destination and every branch
  // route of its `StatefulShellRoute`, plus the top-level `/practice/live`
  // adapter. All absent entirely when the shell is off.
  AppRoutes.today,
  AppRoutes.practiceLive,
  AppRoutes.practiceAnalyze,
  AppRoutes.practiceLearn,
  AppRoutes.practiceTuner,
  AppRoutes.practiceMetronome,
  AppRoutes.practiceChords,
  AppRoutes.songsSetlists,
  AppRoutes.profileHome,
  AppRoutes.profileLibrary,
  AppRoutes.profileSettings,
  AppRoutes.profileProgress,
  AppRoutes.profileRewards,
  // `visionEnabled` plus the per-screen sub-flag each one carries — top
  // level, independent of the shell.
  AppRoutes.visionSetup,
  AppRoutes.visionGuitarGeometry,
  AppRoutes.visionSession,
];

/// The second boot's flag set: [e2eDefaultFlags] plus exactly the switches
/// [_flaggedRoutes] needs. One place, so a route added above and the flag it
/// needs cannot drift apart.
const FeatureFlags _flaggedSweepFlags = FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  practiceEngineV2Enabled: true,
  adaptiveShellEnabled: true,
  visionEnabled: true,
  visionSetupEnabled: true,
  visionGuitarGeometryEnabled: true,
);

// Deliberately NOT swept, with the reason per route:
//   * `practiceSession` / `practiceResult` — registered under
//     `practiceEnabled`, but both need a STARTED practice host. Visiting
//     them cold builds a session screen with no definition and no session
//     state, which is a fixture gap, not a route defect.
//   * `coachHome` — needs `adaptiveShellEnabled` AND `aiTutorEnabled`. The
//     second boot deliberately turns only the shell on, because the AI-Tutor
//     rollout flag also swaps the shell's destination list
//     (`showCoachDestination`) and belongs to that flag's owner.
//   * `analysisOverview` / `analysisTimeline` — need `audioAnalysisV2Enabled`
//     AND an `AnalysisDocument` `extra`; both `redirect` a payload-less visit
//     to `/live`, so a sweep cell could never reach the screen it claims to
//     cover.
//   * `analysisCompare` — same shape behind `analysisComparisonEnabled`, with
//     an `AnalysisComparison` `extra`.
//   * `analysisMetricDetail` — `audioAnalysisV2Enabled` plus a metric-card /
//     details `extra`, same payload-less redirect to `/live`.
//
// Pre-existing gap, out of this round's scope: `_routes` still lists routes
// that are themselves flag-gated and hit the same silent-fallback path — the
// five `tutor*` routes (`aiTutorEnabled`), `songTrainerLibrary` /
// `songTrainerImport` / `songTrainerNewEditor` (`songTrainerV2Enabled`) and
// `practiceGeneratorSetup` / `practiceGeneratorToday`
// (`practiceGeneratorEnabled`), none of which `e2eDefaultFlags` turns on.
// They predate this file's A2a pass, whose ruling covers the adaptive-shell,
// vision and audio-analysis-V2 flags only; splitting them out belongs with
// the owners of those flags.

/// Visits every route in [routes] on a freshly booted app, collecting the
/// Flutter errors thrown while each one was on screen.
///
/// [requireExactLanding] turns "the router did not actually land on the route
/// I asked for" into a failure. It is ON for [_flaggedRoutes], where the
/// whole point is to prove the flag registered the route: none of those
/// entries has a `redirect` of its own, and none is a KEY in
/// `legacyRedirects` — they are that map's TARGETS — so with the shell on
/// each must land on itself. It is OFF for [_routes], where entries redirect
/// BY DESIGN (`/welcome` resolves to the entry location once onboarding is
/// seen) and the landing is only reported.
Future<void> _sweep(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding, {
  required String title,
  required List<String> routes,
  required FeatureFlags? flags,
  required bool requireExactLanding,
}) async {
  final errors = <String, List<String>>{};
  final previousOnError = FlutterError.onError;
  String current = '(boot)';
  FlutterError.onError = (details) {
    errors
        .putIfAbsent(current, () => [])
        .add(details.exceptionAsString().split('\n').first);
  };
  addTearDown(() => FlutterError.onError = previousOnError);

  final session = await bootE2eApp(
    tester,
    store: InMemoryKeyValueStore(),
    onboardingSeen: true,
    flags: flags,
  );
  await tester.pump(const Duration(milliseconds: 400));
  await binding.convertFlutterSurfaceToImage();
  await tester.pump();

  final verdicts = <String, String>{};
  for (final route in routes) {
    current = route;
    final before = errors[route]?.length ?? 0;
    String landed = '(unknown)';
    try {
      session.router.go(route);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      final thrown = tester.takeException();
      if (thrown != null) {
        errors.putIfAbsent(route, () => []).add('$thrown'.split('\n').first);
      }
      landed = session.router.state.uri.path;
      if (requireExactLanding && landed != route) {
        errors
            .putIfAbsent(route, () => [])
            .add('not registered under these flags: landed on $landed');
      }
      final name = route.replaceAll('/', '_').replaceAll(':', '');
      await binding.takeScreenshot('route$name');
    } catch (e) {
      errors.putIfAbsent(route, () => []).add('$e'.split('\n').first);
    }
    final count = (errors[route]?.length ?? 0) - before;
    verdicts[route] = count != 0
        ? 'ERR x$count'
        : landed == route
        ? 'ok'
        : 'ok (-> $landed)';
  }
  current = '(after)';

  final table = StringBuffer('$title (${routes.length} routes)\n');
  verdicts.forEach((r, v) {
    table.writeln('${r.padRight(34)} $v');
    for (final e in errors[r] ?? const <String>[]) {
      table.writeln('    ! $e');
    }
  });
  // ignore: avoid_print
  print(table);
  final failing = verdicts.entries
      .where((e) => e.value.startsWith('ERR'))
      .toList();
  expect(
    failing,
    isEmpty,
    reason: 'routes with Flutter errors: ${failing.map((e) => e.key)}',
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every parameter-free route renders without a Flutter error', (
    tester,
  ) async {
    await _sweep(
      tester,
      binding,
      title: 'ROUTE SWEEP (default flags)',
      routes: _routes,
      flags: null,
      requireExactLanding: false,
    );
  });

  testWidgets('every flag-gated route renders once its flag is on', (
    tester,
  ) async {
    await _sweep(
      tester,
      binding,
      title: 'ROUTE SWEEP (adaptive shell + vision)',
      routes: _flaggedRoutes,
      flags: _flaggedSweepFlags,
      requireExactLanding: true,
    );
  });
}
