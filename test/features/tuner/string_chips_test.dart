import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
