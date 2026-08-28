import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/app/strumsight_app.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

Future<
  ({FakeStrumEngine live, FakeTunerEngine tuner, ProviderContainer container})
>
_pumpShell(WidgetTester tester) async {
  final live = FakeStrumEngine();
  final tuner = FakeTunerEngine();
  addTearDown(live.dispose);
  addTearDown(tuner.dispose);

  // E15-R02: the default flutter_test logical viewport (800x600) sits
  // above SsBreakpoints.compactMax (599) and renders a NavigationRail —
  // pin a compact phone size so the adaptive shell renders the bottom
  // NavigationBar this file asserts on.
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(live),
      tunerEngineProvider.overrideWithValue(tuner),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();
  // E15-R02 (ADR 0467 D9): the app now boots on the adaptive shell's
  // /today entry point by default; /live is reachable through
  // legacyRedirects' target, AppRoutes.practiceLive.
  container.read(routerProvider).go(AppRoutes.practiceLive);
  await tester.pumpAndSettle();
  return (live: live, tuner: tuner, container: container);
}

void main() {
  testWidgets('Live to Settings disposes the live mic owner', (tester) async {
    final rig = await _pumpShell(tester);
    expect(rig.live.startCalls, greaterThan(0));
    final stopsBefore = rig.live.stopCalls;

    // E15-R02 (ADR 0467 D9): /practice/live is a Stage route with no
    // primary navigation to tap through, so this goes through the router
    // directly, same as the app's own Finish/onException fallbacks do.
    rig.container.read(routerProvider).go(AppRoutes.profileSettings);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    // Profile is the adaptive shell's last destination; Coach is absent
    // (aiTutorEnabled defaults off), so index 3, not the legacy shell's 4.
    expect(navigationBar.selectedIndex, 3);
    expect(
      rig.live.stopCalls,
      greaterThan(stopsBefore),
      reason: 'the mic must not stay hot after leaving Live',
    );
  });

  testWidgets('Tuner back returns to the existing Live route', (tester) async {
    final rig = await _pumpShell(tester);

    await tester.tap(find.text('Tuner').first);
    await tester.pumpAndSettle();
    expect(find.byType(TunerScreen), findsOneWidget);

    // E15-R02 (review MAJOR-1 remeasured): `tester.pageBack()` searches for
    // a `CupertinoNavigationBarBackButton` first; `TunerScreen`'s back
    // affordance is a Material `IconButton`, so `pageBack()` fails with
    // "Found 0 widgets with type CupertinoNavigationBarBackButton" (see
    // brief §10 for the literal output) — pop through the router directly
    // instead, same as the rest of this round's router-driven navigation
    // fixes.
    rig.container.read(routerProvider).pop();
    await tester.pumpAndSettle();

    // E15-R02 (ADR 0467 D9): /practice/live is a top-level Stage route
    // (outside the shell's indexedStack), so there is no primary
    // navigation / selected-index to assert here — only that popping
    // Tuner really returns to the still-mounted Live route.
    expect(find.byType(LiveScreen), findsOneWidget);
  });
}
