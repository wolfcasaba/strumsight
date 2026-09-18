// On-device route sweep (round strum-strings, systematic emulator testing).
//
// Boots the REAL StrumSightApp with the E12-R11 deterministic harness (fake
// engines / network / clock — the same profile the e2e walkthrough uses),
// then visits every parameter-free route in the catalogue: navigate, let it
// settle for a bounded time, collect every Flutter error thrown while it was
// on screen, take a screenshot. Prints a route → verdict table and fails only
// at the end so one broken screen never hides the others.
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/route_sweep_test.dart -d emulator-5554
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:strumsight/app/routing/app_route.dart';

import '../test/support/e2e_harness.dart';

const _routes = <String>[
  AppRoutes.today,
  AppRoutes.live,
  AppRoutes.analyze,
  AppRoutes.learn,
  AppRoutes.library,
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
  AppRoutes.visionSetup,
  AppRoutes.visionGuitarGeometry,
  AppRoutes.analysisOverview,
  AppRoutes.analysisTimeline,
  AppRoutes.analysisCompare,
  AppRoutes.gamificationHub,
  AppRoutes.achievements,
  AppRoutes.quests,
  AppRoutes.streakDetail,
  AppRoutes.rewardInbox,
  AppRoutes.levelDetail,
  AppRoutes.coachHome,
  AppRoutes.profileHome,
  AppRoutes.practiceLive,
  AppRoutes.practiceAnalyze,
  AppRoutes.practiceLearn,
  AppRoutes.practiceTuner,
  AppRoutes.practiceMetronome,
  AppRoutes.practiceChords,
  AppRoutes.songsSetlists,
  AppRoutes.welcome,
  AppRoutes.recovery,
  AppRoutes.login,
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every parameter-free route renders without a Flutter error', (
    tester,
  ) async {
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
    );
    await tester.pump(const Duration(milliseconds: 400));
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();

    final verdicts = <String, String>{};
    for (final route in _routes) {
      current = route;
      final before = errors[route]?.length ?? 0;
      try {
        session.router.go(route);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        final thrown = tester.takeException();
        if (thrown != null) {
          errors.putIfAbsent(route, () => []).add('$thrown'.split('\n').first);
        }
        final name = route.replaceAll('/', '_').replaceAll(':', '');
        await binding.takeScreenshot('route$name');
      } catch (e) {
        errors.putIfAbsent(route, () => []).add('$e'.split('\n').first);
      }
      final count = (errors[route]?.length ?? 0) - before;
      verdicts[route] = count == 0 ? 'ok' : 'ERR x$count';
    }
    current = '(after)';

    final table = StringBuffer('ROUTE SWEEP (${_routes.length} routes)\n');
    verdicts.forEach((r, v) {
      table.writeln('${r.padRight(34)} $v');
      for (final e in errors[r] ?? const <String>[]) {
        table.writeln('    ! $e');
      }
    });
    // ignore: avoid_print
    print(table);
    final failing = verdicts.entries.where((e) => e.value != 'ok').toList();
    expect(
      failing,
      isEmpty,
      reason: 'routes with Flutter errors: ${failing.map((e) => e.key)}',
    );
  });
}
