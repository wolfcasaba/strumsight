import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/chords/widgets/chord_diagram.dart';
import 'package:strumsight/features/live/engine/mock_strum_engine.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/widgets/strum_arrow.dart';
import 'package:strumsight/features/settings/providers/capo_provider.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// A capo notifier fixed at [_v] (skips the async prefs load) for widget tests.
class _FixedCapo extends CapoNotifier {
  _FixedCapo(this._v);
  final int _v;
  @override
  int build() => _v;
}

/// E15-R02 (ADR 0467 D9): the app now boots on the adaptive shell's /today
/// entry point by default; /live is reachable through legacyRedirects'
/// target, AppRoutes.practiceLive.
Future<ProviderContainer> _pumpLiveApp(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final container = ProviderContainer(overrides: overrides);
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

void main() {
  testWidgets(
    'Live renders the current chord + its strum on the timeline hero',
    (tester) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);

      await _pumpLiveApp(
        tester,
        overrides: [
          ...preferenceOverrides(),
          strumEngineProvider.overrideWithValue(engine),
        ],
      );

      // Feed a realistic frame (chord C, an accented downstroke at 90%).
      engine.emit(
        MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();

      // The chord-timeline hero shows the chord label, its confidence and the
      // ↓/↑ strum direction (the moat), plus the fingering diagram. E13-R18:
      // the Stage hero slot ALSO shows the current chord (glanceable
      // from-across-the-room readout, distinct from the filmstrip's own
      // richer hero card) — so "C" now appears twice, by design (§10).
      expect(find.text('C'), findsWidgets); // the chord label, hero + Stage
      expect(find.textContaining('90%'), findsOneWidget); // hero confidence bar
      expect(find.byType(StrumArrow), findsWidgets); // the ↓/↑ direction
      expect(find.byType(ChordDiagram), findsOneWidget); // hero fingering
      // The Tuner action button is present on the Live screen.
      expect(find.text('Tuner'), findsWidgets);

      // flutter_animate schedules a zero-delay play timer per Animate and only
      // .ignore()s it on dispose (doesn't cancel it) — let it fire so no Timer
      // is left pending at teardown.
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets('a capo transposes the timeline chord shape and shows a badge', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await _pumpLiveApp(
      tester,
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
        capoProvider.overrideWith(() => _FixedCapo(2)),
      ],
    );

    // Detector hears C (concert pitch); with capo 2 the fretted shape is A#.
    engine.emit(
      MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('A#'), findsWidgets); // C shown as the fretted shape
    expect(find.text('C'), findsNothing);
    expect(find.textContaining('Capo 2'), findsOneWidget); // honest badge

    // Flush flutter_animate's zero-delay play timer (see note above).
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('Pause freezes the display and toggles the action label', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await _pumpLiveApp(
      tester,
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
      ],
    );
    engine.emit(
      MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    // E13-R18: Pause/Resume moved onto the mandated SsSessionTransport
    // (ADR 0276 decision 4) — icon+tooltip, not a visible Text label.
    final transportPause = find.byKey(
      const ValueKey('ss-session-transport-pause'),
    );
    expect(transportPause, findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.tap(transportPause);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Resume'), findsOneWidget);
    // Pause must actually stop detection, not just freeze the display.
    expect(engine.stopCalls, greaterThan(0));

    await tester.tap(transportPause);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(engine.startCalls, greaterThan(0));
  });

  testWidgets('leaving the Live tab releases the mic (autoDispose timeline)', (
    tester,
  ) async {
    // Regression guard for the r185 review's C1: chordTimelineProvider must be
    // autoDispose. A non-autoDispose provider holds a permanent ref.listen on
    // the autoDispose liveFrameProvider, pinning the mic/DSP on forever after
    // the first Live visit — a battery/privacy bug synthetic UI tests miss.
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    final container = await _pumpLiveApp(
      tester,
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
      ],
    );

    // Booting on Live starts the engine (mic hot).
    expect(engine.startCalls, greaterThan(0));
    final stopsBefore = engine.stopCalls;

    // Leave Live for another destination → LiveScreen unmounts, the
    // timeline provider and liveFrameProvider auto-dispose, and
    // engine.stop() releases the mic. E15-R02 (ADR 0467 D9): /practice/live
    // is a Stage route with no primary navigation to tap through, so this
    // goes through the router directly.
    // The old page unmounts only when the route transition FINISHES.
    container.read(routerProvider).go(AppRoutes.today);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      engine.stopCalls,
      greaterThan(stopsBefore),
      reason: 'the mic must not stay hot after leaving Live',
    );
  });

  testWidgets('A mic start failure surfaces an error banner with Retry', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await _pumpLiveApp(
      tester,
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
      ],
    );

    // The mic could not be started — never a silent no-op.
    engine.emitError(Exception('mic busy'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('microphone'), findsOneWidget);
  });
}
