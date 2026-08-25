import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/learn/audio/chord_audio.dart';
import 'package:strumsight/features/tuner/providers/reference_tone_provider.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// Round 94 — tune by EAR: with a string pinned (round 91's manual mode), a
/// speaker button plays the target's reference tone. No pin → no button.
/// E13-R19 migration: the tone is now played by a Tuner-owned
/// [ReferenceTonePlayer] (autodisposed with the route, brief §0.0/R5, A5)
/// instead of the app-wide `Backing` shared with Learn.
class _RecordingTonePlayer implements ReferenceTonePlayer {
  final List<double> tones = [];
  bool disposed = false;
  int stopCalls = 0;

  @override
  Future<void> play(double freqHz) async => tones.add(freqHz);

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async => disposed = true;
}

Future<void> pumpTuner(
  WidgetTester tester,
  FakeTunerEngine engine,
  ReferenceTonePlayer tone,
) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      ...preferenceOverrides(),
      tunerEngineProvider.overrideWithValue(engine),
      referenceTonePlayerProvider.overrideWithValue(tone),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TunerScreen(),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('no pin → no reference-tone button', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await pumpTuner(tester, engine, _RecordingTonePlayer());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.volume_up), findsNothing);
  });

  testWidgets('pinning a string reveals the button; tapping plays the '
      'target frequency', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    final tone = _RecordingTonePlayer();
    await pumpTuner(tester, engine, tone);
    await tester.pumpAndSettle();

    await tester.tap(find.text('A2'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pumpAndSettle();

    expect(tone.tones, hasLength(1));
    expect(tone.tones.single, closeTo(110.0, 0.01)); // A2 at A4=440
  });

  testWidgets(
    'leaving the Tuner route disposes the reference-tone player (A5)',
    (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      final tone = _RecordingTonePlayer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            tunerEngineProvider.overrideWithValue(engine),
            referenceTonePlayerProvider.overrideWithValue(tone),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const TunerScreen())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tone.disposed, isFalse);

      await tester.tap(
        find.byTooltip(
          MaterialLocalizations.of(
            tester.element(find.byType(TunerScreen)),
          ).backButtonTooltip,
        ),
      );
      await tester.pumpAndSettle();

      expect(tone.disposed, isTrue);
    },
  );

  // testWidgets (not test): a real Backing owns an AudioPlayer and needs the
  // widget-test binding. Its dispose() must NOT be awaited here — it awaits a
  // platform-channel future that never completes under the test binding
  // (production never awaits it either; State.dispose is sync). Kept here
  // (unrelated to the Tuner-owned ReferenceTonePlayer above) as the only
  // coverage of `Backing.playTone`'s nonsense-frequency guard.
  testWidgets('Backing.playTone ignores nonsense frequencies', (tester) async {
    final backing = Backing();
    addTearDown(() {
      unawaited(backing.dispose());
    });
    // Must not throw or try to synthesise a WAV for silence/negative input.
    await backing.playTone(0);
    await backing.playTone(-5);
  });
}
