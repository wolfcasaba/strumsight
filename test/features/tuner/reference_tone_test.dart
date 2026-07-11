import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/audio/chord_audio.dart';
import 'package:music_theory/features/learn/providers/backing_provider.dart';
import 'package:music_theory/features/tuner/providers/tuner_providers.dart';
import 'package:music_theory/features/tuner/screens/tuner_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

/// Round 94 — tune by EAR: with a string pinned (round 91's manual mode), a
/// speaker button plays the target's reference tone. No pin → no button
/// (auto mode has no single target to sound).
class _RecordingBacking extends Backing {
  final List<double> tones = [];

  @override
  Future<void> playTone(double freqHz) async => tones.add(freqHz);
}

Future<void> pumpTuner(
        WidgetTester tester, FakeTunerEngine engine, Backing backing) =>
    tester.pumpWidget(ProviderScope(
      overrides: [
        tunerEngineProvider.overrideWithValue(engine),
        backingProvider.overrideWithValue(backing),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TunerScreen(),
      ),
    ));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('no pin → no reference-tone button', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await pumpTuner(tester, engine, _RecordingBacking());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.volume_up), findsNothing);
  });

  testWidgets('pinning a string reveals the button; tapping plays the '
      'target frequency', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    final backing = _RecordingBacking();
    await pumpTuner(tester, engine, backing);
    await tester.pumpAndSettle();

    await tester.tap(find.text('A2'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pumpAndSettle();

    expect(backing.tones, hasLength(1));
    expect(backing.tones.single, closeTo(110.0, 0.01)); // A2 at A4=440
  });

  // testWidgets (not test): a real Backing owns an AudioPlayer and needs the
  // widget-test binding. Its dispose() must NOT be awaited here — it awaits a
  // platform-channel future that never completes under the test binding
  // (production never awaits it either; State.dispose is sync).
  testWidgets('Backing.playTone ignores nonsense frequencies',
      (tester) async {
    final backing = Backing();
    addTearDown(() {
      unawaited(backing.dispose());
    });
    // Must not throw or try to synthesise a WAV for silence/negative input.
    await backing.playTone(0);
    await backing.playTone(-5);
  });
}
