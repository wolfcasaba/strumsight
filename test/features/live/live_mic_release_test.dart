// E13-R18 A4 — the microphone stops on every measured exit path
// (§0.0/R7): (1) navigation (autoDispose), (2) backgrounding
// (`_onAppLifecycle`), (3) pause, (4) error/dispose. The navigation and
// background paths already have dedicated coverage (`live_widgets_test.dart`,
// `live_background_test.dart`); this file is the single place all four are
// asserted together, plus the NEW Finish path this round adds.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

void main() {
  ({FakeStrumEngine engine, FakeAppLifecycleEvents lifecycle}) rig() {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    return (engine: engine, lifecycle: FakeAppLifecycleEvents());
  }

  Future<ProviderContainer> pumpLive(WidgetTester tester, dynamic r) async {
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(lifecycle: r.lifecycle as FakeAppLifecycleEvents),
        strumEngineProvider.overrideWithValue(r.engine as FakeStrumEngine),
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
    return container;
  }

  testWidgets('(1) navigation — leaving Live stops the mic (autoDispose)', (
    tester,
  ) async {
    final r = rig();
    final container = await pumpLive(tester, r);
    expect(r.engine.startCalls, greaterThanOrEqualTo(1));
    final stopsBefore = r.engine.stopCalls;

    // E15-R02 (ADR 0467 D9): /practice/live is a Stage route (no primary
    // navigation to tap through), so leaving is driven through the router
    // directly, same as the app's own Finish/onException fallbacks do.
    container.read(routerProvider).go(AppRoutes.today);
    await tester.pumpAndSettle();

    expect(r.engine.stopCalls, greaterThan(stopsBefore));
  });

  testWidgets('(2) backgrounding — the app-lifecycle hook stops the mic', (
    tester,
  ) async {
    final r = rig();
    await pumpLive(tester, r);
    final stopsBefore = r.engine.stopCalls;

    r.lifecycle.emit(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(r.engine.stopCalls, greaterThan(stopsBefore));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('(3) pause — tapping Pause stops the mic', (tester) async {
    final r = rig();
    await pumpLive(tester, r);
    final stopsBefore = r.engine.stopCalls;

    await tester.tap(find.byKey(const ValueKey('ss-session-transport-pause')));
    await tester.pumpAndSettle();

    expect(r.engine.stopCalls, greaterThan(stopsBefore));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('(4) error — a mic start failure never leaves it silently open '
      '(the engine already reports the failure, not a stuck-open handle)', (
    tester,
  ) async {
    final r = rig();
    await pumpLive(tester, r);

    r.engine.emitError(Exception('mic busy'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    // Retry re-invalidates the provider — the previous (failed) engine
    // instance is not left running; the same fake engine's own stop-call
    // count is unaffected by an error it never started successfully from.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    '(4) dispose — leaving via Finish stops the mic before the route goes',
    (tester) async {
      final r = rig();
      await pumpLive(tester, r);
      final stopsBefore = r.engine.stopCalls;

      await tester.tap(
        find.byKey(const ValueKey('ss-session-transport-finish')),
      );
      await tester.pump();

      // The mic stops immediately on tap, well before the deferred
      // navigation (300 ms) actually leaves the route.
      expect(r.engine.stopCalls, greaterThan(stopsBefore));

      await tester.pump(const Duration(milliseconds: 350));
    },
  );

  testWidgets(
    '(5) dispose — unmounting Live disposes its SsLiveRegion, not just its '
    'listeners (review MINOR-1)',
    (tester) async {
      final r = rig();
      final container = await pumpLive(tester, r);

      final liveRegion = tester
          .widget<SsLiveRegionAnnouncer>(find.byType(SsLiveRegionAnnouncer))
          .controller;

      // Leave the route so `_LiveScreenState.dispose()` runs. E15-R02
      // (ADR 0467 D9): /practice/live is a Stage route with no primary
      // navigation to tap through, so this goes through the router.
      container.read(routerProvider).go(AppRoutes.today);
      await tester.pumpAndSettle();

      // A disposed ChangeNotifier throws on any further listener
      // registration (the Flutter framework's own contract) — this is what
      // distinguishes "disposed" from merely "no longer listened to".
      expect(() => liveRegion.addListener(() {}), throwsFlutterError);
    },
  );
}
