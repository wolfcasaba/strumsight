import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// E01-R09 §9.4/§9.5 — leaving the app (or the screen) must actually stop the
/// microphone and release the wakelock, and coming back must NOT silently
/// start listening again.
void main() {
  ({
    FakeStrumEngine engine,
    FakeAppLifecycleEvents lifecycle,
    FakeScreenWakelock wakelock,
  })
  rig() {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    return (
      engine: engine,
      lifecycle: FakeAppLifecycleEvents(),
      wakelock: FakeScreenWakelock(),
    );
  }

  Future<ProviderContainer> pumpLive(WidgetTester tester, dynamic r) async {
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(
          lifecycle: r.lifecycle as FakeAppLifecycleEvents,
          wakelock: r.wakelock as FakeScreenWakelock,
        ),
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

  testWidgets('Live holds the wakelock while the session runs', (tester) async {
    final r = rig();
    await pumpLive(tester, r);

    expect(r.wakelock.isHeld, isTrue);
    expect(r.engine.startCalls, greaterThanOrEqualTo(1));

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('backgrounding stops the mic and releases the wakelock', (
    tester,
  ) async {
    final r = rig();
    await pumpLive(tester, r);
    final startsBefore = r.engine.startCalls;

    r.lifecycle.emit(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(r.engine.stopCalls, greaterThanOrEqualTo(1));
    expect(
      r.wakelock.isHeld,
      isFalse,
      reason: 'a backgrounded app must not keep the screen awake (§9.4)',
    );

    // Resuming must NOT restart the microphone behind the user's back.
    r.lifecycle.emit(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(r.engine.startCalls, startsBefore);

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('leaving Live releases the wakelock and the lifecycle hook', (
    tester,
  ) async {
    final r = rig();
    final container = await pumpLive(tester, r);

    // Switch to another destination — the Live screen is disposed (r199
    // path). E15-R02 (ADR 0467 D9): /practice/live is a Stage route with
    // no primary navigation to tap through, so this goes through the
    // router directly.
    container.read(routerProvider).go(AppRoutes.today);
    await tester.pumpAndSettle();

    expect(r.engine.stopCalls, greaterThanOrEqualTo(1));
    expect(r.wakelock.isHeld, isFalse);

    // The screen also unhooked itself from the app lifecycle: a later
    // background event must not run its teardown again. (The app-wide
    // AudioLifecycleGuard keeps its own listener — that one is meant to stay.)
    final releasesAfterLeaving = r.wakelock.disableCalls;
    r.lifecycle.emit(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(r.wakelock.disableCalls, releasesAfterLeaving);

    await tester.pump(const Duration(milliseconds: 400));
  });
}
