import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/model/in_tune_lock.dart';
import 'package:music_theory/features/tuner/model/tuner_reading.dart';
import 'package:music_theory/features/tuner/providers/tuner_providers.dart';
import 'package:music_theory/features/tuner/screens/tuner_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('all six standard-tuning chips are shown', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [tunerEngineProvider.overrideWithValue(engine)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TunerScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    for (final label in ['E2', 'A2', 'D3', 'G3', 'B3', 'E4']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('the chip nearest the sounding pitch is highlighted with a '
      'check when in tune', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [tunerEngineProvider.overrideWithValue(engine)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TunerScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // A perfectly tuned open A (110 Hz).
    engine.emit(const TunerReading(note: 'A', cents: 0, frequencyHz: 110));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('holding the pitch in tune locks in — the note pulses green',
      (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [tunerEngineProvider.overrideWithValue(engine)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TunerScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // One in-tune reading is NOT a lock…
    engine.emit(const TunerReading(note: 'A', cents: 0, frequencyHz: 110));
    await tester.pumpAndSettle();
    var scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale, 1.0);

    // …holding it for the required consecutive readings is. The cents
    // wobble slightly (still in tune) — identical const readings would
    // canonicalise to one instance and Riverpod would not notify.
    for (var i = 1; i < InTuneLock.holdReadings; i++) {
      engine.emit(
          TunerReading(note: 'A', cents: i * 0.1, frequencyHz: 110));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scale, greaterThan(1.0),
        reason: 'the locked note pulses to celebrate the hold');
  });
}
