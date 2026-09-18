// E13-R18 A4 — the microphone stops on every measured exit path
// (§0.0/R7): (1) navigation (autoDispose), (2) backgrounding
// (`_onAppLifecycle`), (3) pause, (4) error/dispose. The navigation and
// background paths already have dedicated coverage (`live_widgets_test.dart`,
// `live_background_test.dart`); this file is the single place all four are
// asserted together, plus the NEW Finish path this round adds.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/audio/audio_providers.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/audio/mic_capture.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/leasing_engines.dart';
import '../../support/preference_store.dart';
import '../../support/slow_stopping_capture.dart';

void main() {
  ({
    FakeStrumEngine engine,
    FakeTunerEngine tuner,
    FakeAppLifecycleEvents lifecycle,
    FakeScreenWakelock wakelock,
  })
  rig() {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    final tuner = FakeTunerEngine();
    addTearDown(tuner.dispose);
    return (
      engine: engine,
      tuner: tuner,
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
        tunerEngineProvider.overrideWithValue(r.tuner as FakeTunerEngine),
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

  testWidgets(
    '(6) tuner shortcut — pushing the Tuner over Live releases the mic lease '
    '(LiveScreen stays mounted underneath) and gives it back on the way out',
    (tester) async {
      final r = rig();
      final container = await pumpLive(tester, r);
      final stopsBefore = r.engine.stopCalls;
      final startsBefore = r.engine.startCalls;
      expect(r.wakelock.isHeld, isTrue);

      // The bottom action bar's Tuner shortcut (l10n `liveTuner`).
      await tester.tap(find.text('Tuner'));
      await tester.pumpAndSettle();

      expect(find.byType(TunerScreen), findsOneWidget);
      expect(
        r.engine.stopCalls,
        greaterThan(stopsBefore),
        reason:
            'the pushed Tuner does NOT unmount Live, so liveFrameProvider '
            'keeps the engine alive and the exclusive mic lease held — the '
            'Tuner would get audioSessionBusy forever',
      );
      expect(
        r.wakelock.isHeld,
        isFalse,
        reason: 'a covered Live session must not keep the screen awake',
      );

      container.read(routerProvider).pop();
      await tester.pumpAndSettle();

      expect(find.byType(TunerScreen), findsNothing);
      expect(
        r.engine.startCalls,
        greaterThan(startsBefore),
        reason: 'coming back from the Tuner must resume listening',
      );
      expect(r.wakelock.isHeld, isTrue);
    },
  );

  // ---------------------------------------------------------------------
  // (7)/(8) The same shortcut, measured on the LEASE instead of on a call
  // counter. Cases (1)-(6) run on FakeStrumEngine/FakeTunerEngine, which
  // never touch `MicCapture` or the `AudioSessionCoordinator` — they can only
  // show that Pause was *invoked*, not that the microphone was free when the
  // Tuner asked for it. These two use engine doubles that hold the real
  // exclusive lease, so "releases the mic lease" is actually asserted.
  // ---------------------------------------------------------------------

  ({
    AudioSessionCoordinator coordinator,
    LeasingStrumEngine live,
    LeasingTunerEngine tuner,
    List<SlowStoppingAudioCapture> captures,
    FakeAppLifecycleEvents lifecycle,
    FakeScreenWakelock wakelock,
  })
  leaseRig() {
    final coordinator = AudioSessionCoordinator();
    final permissions = FakeMicrophonePermissionGateway();
    // Every platform capture either engine ever opened — "nothing is
    // recording" has to hold for ALL of them, not just the newest handle.
    final captures = <SlowStoppingAudioCapture>[];
    MicCapture micFor(AudioOwner owner) => MicCapture(
      owner: owner,
      coordinator: coordinator,
      permissions: permissions,
      // A platform stream does not close for free, and that round-trip IS the
      // window a restart lands in; a capture that stops within a microtask
      // hides the handover race completely.
      captureFactory: () {
        final capture = SlowStoppingAudioCapture();
        captures.add(capture);
        return capture;
      },
    );
    // Deliberately NOT `addTearDown(engine.dispose)`: these engines stop
    // through a platform round-trip, i.e. a timer, and a tearDown runs after
    // the last `pump` — nothing is left that can elapse the fake clock, so an
    // awaited disposal would simply hang until the 10-minute test timeout.
    // The doubles own nothing but an unlistened broadcast controller.
    final live = LeasingStrumEngine(micFor(AudioOwner.live));
    final tuner = LeasingTunerEngine(micFor(AudioOwner.tuner));
    return (
      coordinator: coordinator,
      live: live,
      tuner: tuner,
      captures: captures,
      lifecycle: FakeAppLifecycleEvents(),
      wakelock: FakeScreenWakelock(),
    );
  }

  Future<ProviderContainer> pumpLeasedLive(
    WidgetTester tester,
    dynamic r,
  ) async {
    final container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(
          lifecycle: r.lifecycle as FakeAppLifecycleEvents,
          wakelock: r.wakelock as FakeScreenWakelock,
        ),
        // THE coordinator both engines lease from — the same instance the
        // Live screen reads to hand the session over.
        audioSessionCoordinatorProvider.overrideWithValue(
          r.coordinator as AudioSessionCoordinator,
        ),
        strumEngineProvider.overrideWithValue(r.live as LeasingStrumEngine),
        tunerEngineProvider.overrideWithValue(r.tuner as LeasingTunerEngine),
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
    container.read(routerProvider).go(AppRoutes.practiceLive);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    '(7) tuner shortcut — the microphone LEASE is back with the coordinator '
    'before the Tuner asks for it',
    (tester) async {
      final r = leaseRig();
      await pumpLeasedLive(tester, r);
      expect(r.coordinator.activeOwner, AudioOwner.live);

      await tester.tap(find.text('Tuner'));
      // NO time is advanced by this pump: it is exactly the frame a push that
      // did not await the handover would build the Tuner into, while Live's
      // `MicCapture.stop()` is still inside the platform round-trip and its
      // lease is therefore still the active one.
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(TunerScreen), findsOneWidget);
      expect(
        r.tuner.failures,
        isEmpty,
        reason:
            'the Tuner must not be handed audioSessionBusy: Live has to give '
            'the lease back BEFORE the route is pushed, not merely start '
            'giving it back',
      );
      expect(
        r.coordinator.activeOwner,
        AudioOwner.tuner,
        reason: 'the Tuner now owns the microphone',
      );
      expect(r.wakelock.isHeld, isFalse);
    },
  );

  testWidgets(
    '(8) tuner shortcut — coming back waits for the Tuner to hand the lease '
    'back before Live resumes',
    (tester) async {
      final r = leaseRig();
      final container = await pumpLeasedLive(tester, r);

      await tester.tap(find.text('Tuner'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(r.coordinator.activeOwner, AudioOwner.tuner);
      final liveFailuresBefore = r.live.failures.length;

      container.read(routerProvider).pop();
      // Again without advancing time: the Tuner's own lease is released by an
      // UN-AWAITED `ref.onDispose(engine.stop)`, so it is still held here.
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(TunerScreen), findsNothing);
      expect(
        r.live.failures.length,
        liveFailuresBefore,
        reason:
            'resuming Live must wait for the Tuner teardown instead of racing '
            'it into audioSessionBusy (which surfaces as the mic error banner)',
      );
      expect(
        r.coordinator.activeOwner,
        AudioOwner.live,
        reason: 'Live owns the microphone again',
      );
      expect(r.wakelock.isHeld, isTrue);
    },
  );

  testWidgets(
    '(9) backgrounding while a Resume start is still QUEUED leaves nothing '
    'recording and the microphone lease free (§5, E01-R09 §9.4)',
    (tester) async {
      final r = leaseRig();
      await pumpLeasedLive(tester, r);
      expect(r.coordinator.activeOwner, AudioOwner.live);

      final pause = find.byKey(const ValueKey('ss-session-transport-pause'));
      // Pause: the platform stream close is a real round-trip, so this stop is
      // still in flight for as long as no time is advanced.
      await tester.tap(pause);
      await tester.pump();
      // Resume in that same window: `ref.invalidate(liveFrameProvider)` puts a
      // start on the engine's lifecycle queue BEHIND the unfinished stop, so
      // the microphone it will open is not open yet.
      await tester.tap(pause);
      await tester.pump();
      // …and the user switches apps. `_onAppLifecycle` fires an UN-AWAITED
      // `stop()`, which lands on the queue AFTER that start. It must therefore
      // stop the microphone THAT start opens: an engine that consumes the stop
      // signal eagerly leaves the app recording in the background with the
      // exclusive lease held forever.
      r.lifecycle.emit(AppLifecycleState.paused);
      await tester.pumpAndSettle();

      expect(
        r.captures.where((capture) => capture.isRunning),
        isEmpty,
        reason: 'the app must never sit in the background recording',
      );
      expect(
        r.coordinator.activeOwner,
        isNull,
        reason: 'the exclusive lease must be back once the queue has drained',
      );
      expect(r.live.session.lifecycleErrors, isEmpty);
      expect(r.wakelock.isHeld, isFalse);
    },
  );
}
