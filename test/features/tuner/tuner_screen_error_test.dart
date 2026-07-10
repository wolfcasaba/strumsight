import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/features/tuner/model/tuner_reading.dart';
import 'package:music_theory/features/tuner/providers/tuner_providers.dart';
import 'package:music_theory/features/tuner/screens/tuner_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

Widget _app(FakeTunerEngine engine) => ProviderScope(
      overrides: [tunerEngineProvider.overrideWithValue(engine)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TunerScreen(),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Tuner surfaces a mic error with a Retry — parity with Live',
      (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(_app(engine));
    await tester.pumpAndSettle();

    // Mic failed to start (busy / platform error) — never a silent idle.
    engine.emitError(Exception('mic busy'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('microphone'), findsOneWidget);
  });

  testWidgets(
      'Retry restarts the engine; a reading from the recovered mic clears '
      'the banner', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(_app(engine));
    await tester.pumpAndSettle();

    engine.emitError(Exception('mic busy'));
    await tester.pumpAndSettle();
    expect(engine.startCalls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(engine.startCalls, 2, reason: 'Retry must restart the engine');

    // The restarted mic works: the first reading clears the error banner.
    engine.emit(const TunerReading(note: 'A', cents: 0, frequencyHz: 440));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsNothing,
        reason: 'a real reading replaces the error state');
    expect(find.text('A'), findsOneWidget); // the tuner is alive again
  });

  testWidgets(
      'Tuner shows the mic-permission banner when permission is denied '
      '— parity with Live', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        tunerEngineProvider.overrideWithValue(engine),
        micPermissionProvider.overrideWith((ref) async => false),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TunerScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('microphone'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });
}
