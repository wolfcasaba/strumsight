import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/model/guitar_strings.dart';
import 'package:music_theory/features/tuner/model/tuner_reading.dart';
import 'package:music_theory/features/tuner/model/tuning.dart';
import 'package:music_theory/features/tuner/providers/tuner_providers.dart';
import 'package:music_theory/features/tuner/providers/pinned_string_provider.dart';
import 'package:music_theory/features/tuner/screens/tuner_screen.dart';
import 'package:music_theory/features/tuner/widgets/cents_gauge.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

/// Round 91 — manual string mode (GuitarTuna parity): tap a chip to PIN that
/// string; the gauge then reads against the pinned target instead of the
/// chromatic nearest note — essential when a string is so far off (or the
/// room so noisy) that auto mode names a different note entirely.
Future<void> pumpTuner(WidgetTester tester, FakeTunerEngine engine) =>
    tester.pumpWidget(ProviderScope(
      overrides: [tunerEngineProvider.overrideWithValue(engine)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TunerScreen(),
      ),
    ));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('GuitarStrings.centsTo', () {
    test('measures signed cents against a specific string', () {
      const a2 = GuitarString('A2', 45); // 110 Hz at A4=440
      expect(GuitarStrings.centsTo(a2, 110.0), closeTo(0, 0.01));
      // 105 Hz is ~80.5 cents FLAT of A2 — auto mode would call this G#.
      expect(GuitarStrings.centsTo(a2, 105.0), closeTo(-80.54, 0.1));
      expect(GuitarStrings.centsTo(a2, 113.0), closeTo(46.6, 0.1));
    });

    test('scales with the A4 reference', () {
      const a2 = GuitarString('A2', 45);
      expect(GuitarStrings.centsTo(a2, 108.25, a4: 433), closeTo(0, 0.1));
    });
  });

  testWidgets('tapping a chip pins the string: the gauge reads against IT',
      (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await pumpTuner(tester, engine);
    await tester.pumpAndSettle();

    await tester.tap(find.text('A2'));
    await tester.pumpAndSettle();

    // 105 Hz: chromatic nearest is G#2 — auto mode would say "G#". Pinned
    // to A2 the screen must keep the TARGET name and show ~-80 cents.
    engine.emit(const TunerReading(note: 'G#', cents: 19, frequencyHz: 105));
    await tester.pumpAndSettle();

    expect(find.text('G#'), findsNothing);
    // Target label on the big readout AND on its chip.
    expect(find.text('A2'), findsNWidgets(2));
    final gauge = tester.widget<CentsGauge>(find.byType(CentsGauge));
    expect(gauge.cents, closeTo(-80.5, 0.5));
    expect(gauge.inTune, isFalse);
  });

  testWidgets('tapping the pinned chip again returns to auto', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await pumpTuner(tester, engine);
    await tester.pumpAndSettle();

    await tester.tap(find.text('A2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A2'));
    await tester.pumpAndSettle();

    engine.emit(const TunerReading(note: 'G#', cents: 19, frequencyHz: 105));
    await tester.pumpAndSettle();

    expect(find.text('G#'), findsOneWidget, reason: 'auto mode is back');
  });

  test('switching tuning clears a pin that is not in the new tuning', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final pin = container.read(pinnedStringProvider.notifier);
    pin.toggle(Tunings.standard.strings.first); // E2
    expect(container.read(pinnedStringProvider), isNotNull);
    pin.reconcile(Tunings.dropD.strings); // E2 is not in drop D
    expect(container.read(pinnedStringProvider), isNull);
  });
}
