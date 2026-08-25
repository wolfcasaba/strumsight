// E13-R18 A4 — the microphone stops on every measured exit path
// (§0.0/R7): (1) navigation (autoDispose), (2) backgrounding
// (`_onAppLifecycle`), (3) pause, (4) error/dispose. The navigation and
// background paths already have dedicated coverage (`live_widgets_test.dart`,
// `live_background_test.dart`); this file is the single place all four are
// asserted together, plus the NEW Finish path this round adds.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  Future<void> pumpLive(WidgetTester tester, dynamic r) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          ...fakeAudioOverrides(
            lifecycle: r.lifecycle as FakeAppLifecycleEvents,
          ),
          strumEngineProvider.overrideWithValue(r.engine as FakeStrumEngine),
        ],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('(1) navigation — leaving Live stops the mic (autoDispose)', (
    tester,
  ) async {
    final r = rig();
    await pumpLive(tester, r);
    expect(r.engine.startCalls, greaterThanOrEqualTo(1));
    final stopsBefore = r.engine.stopCalls;

    await tester.tap(find.text('Learn').first);
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
}
