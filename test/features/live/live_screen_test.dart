import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/widgets/chord_diagram.dart';
import 'package:music_theory/features/live/engine/mock_strum_engine.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/features/live/widgets/strum_arrow.dart';
import 'package:music_theory/features/settings/providers/capo_provider.dart';
import 'package:music_theory/main.dart';

import '../../support/fake_engines.dart';

/// A capo notifier fixed at [_v] (skips the async prefs load) for widget tests.
class _FixedCapo extends CapoNotifier {
  _FixedCapo(this._v);
  final int _v;
  @override
  int build() => _v;
}

void main() {
  testWidgets('Live renders the current chord + its strum on the timeline hero',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [strumEngineProvider.overrideWithValue(engine)],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Feed a realistic frame (chord C, an accented downstroke at 90%).
    engine.emit(MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    // The chord-timeline hero shows the chord label, its confidence and the
    // ↓/↑ strum direction (the moat), plus the fingering diagram.
    expect(find.text('C'), findsOneWidget); // the hero chord label
    expect(find.textContaining('90%'), findsOneWidget); // hero confidence bar
    expect(find.byType(StrumArrow), findsWidgets); // the ↓/↑ direction
    expect(find.byType(ChordDiagram), findsOneWidget); // hero fingering
    // The Tuner action button is present on the Live screen.
    expect(find.text('Tuner'), findsWidgets);

    // flutter_animate schedules a zero-delay play timer per Animate and only
    // .ignore()s it on dispose (doesn't cancel it) — let it fire so no Timer
    // is left pending at teardown.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a capo transposes the timeline chord shape and shows a badge',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strumEngineProvider.overrideWithValue(engine),
          capoProvider.overrideWith(() => _FixedCapo(2)),
        ],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Detector hears C (concert pitch); with capo 2 the fretted shape is A#.
    engine.emit(MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('A#'), findsOneWidget); // C shown as the fretted shape
    expect(find.text('C'), findsNothing);
    expect(find.textContaining('Capo 2'), findsOneWidget); // honest badge

    // Flush flutter_animate's zero-delay play timer (see note above).
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('Pause freezes the display and toggles the action label',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [strumEngineProvider.overrideWithValue(engine)],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();
    engine.emit(MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    // Pause must actually stop detection, not just freeze the display.
    expect(engine.stopCalls, greaterThan(0));

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget);
    expect(engine.startCalls, greaterThan(0));
  });

  testWidgets('leaving the Live tab releases the mic (autoDispose timeline)',
      (tester) async {
    // Regression guard for the r185 review's C1: chordTimelineProvider must be
    // autoDispose. A non-autoDispose provider holds a permanent ref.listen on
    // the autoDispose liveFrameProvider, pinning the mic/DSP on forever after
    // the first Live visit — a battery/privacy bug synthetic UI tests miss.
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [strumEngineProvider.overrideWithValue(engine)],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Booting on Live starts the engine (mic hot).
    expect(engine.startCalls, greaterThan(0));
    final stopsBefore = engine.stopCalls;

    // Leave Live for another tab → LiveScreen unmounts, the timeline provider
    // and liveFrameProvider auto-dispose, and engine.stop() releases the mic.
    // The old page unmounts only when the route transition FINISHES.
    await tester.tap(find.text('Learn'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));

    expect(engine.stopCalls, greaterThan(stopsBefore),
        reason: 'the mic must not stay hot after leaving Live');
  });

  testWidgets('A mic start failure surfaces an error banner with Retry',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [strumEngineProvider.overrideWithValue(engine)],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The mic could not be started — never a silent no-op.
    engine.emitError(Exception('mic busy'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('microphone'), findsOneWidget);
  });
}
