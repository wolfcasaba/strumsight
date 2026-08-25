import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/tuner/providers/reference_tone_provider.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// A5 (brief §5.4, §9): the reference tone and the mic's audio focus must
/// both release when the Tuner route is left — never audible/held in the
/// background after navigating away.
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

/// `overrideWithValue` bypasses the provider's OWN `create` body — exactly
/// where the real provider wires `ref.onDispose(player.dispose)` — so it can
/// never exercise autodispose teardown. Overriding with a builder that wires
/// the same `ref.onDispose` call keeps the fake injectable while still
/// exercising the real disposal path this test asserts on (A5).
Override _toneOverride(ReferenceTonePlayer tone) =>
    referenceTonePlayerProvider.overrideWith((ref) {
      ref.onDispose(tone.dispose);
      return tone;
    });

Widget _hostApp(Widget Function(BuildContext) openTuner) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => ElevatedButton(
      onPressed: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: openTuner)),
      child: const Text('open tuner'),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('leaving Tuner stops the mic engine (audio focus released)', (
    tester,
  ) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          tunerEngineProvider.overrideWithValue(engine),
        ],
        child: _hostApp((_) => const TunerScreen()),
      ),
    );

    await tester.tap(find.text('open tuner'));
    await tester.pumpAndSettle();
    expect(find.byType(TunerScreen), findsOneWidget);
    expect(engine.startCalls, 1);
    expect(engine.stopCalls, 0);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(TunerScreen), findsNothing);
    expect(
      engine.stopCalls,
      1,
      reason: 'the autodisposed reading stream must stop the mic engine',
    );
  });

  testWidgets(
    'leaving Tuner disposes the reference-tone player even mid-tone (A5)',
    (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      final tone = _RecordingTonePlayer();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            tunerEngineProvider.overrideWithValue(engine),
            _toneOverride(tone),
          ],
          child: _hostApp((_) => const TunerScreen()),
        ),
      );

      await tester.tap(find.text('open tuner'));
      await tester.pumpAndSettle();

      // Pin a string and start the reference tone — the exact scenario the
      // risk names: leaving mid-tone must not leave it audible (§9).
      await tester.tap(find.text('E2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pumpAndSettle();
      expect(tone.tones, hasLength(1));
      expect(tone.disposed, isFalse);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(
        tone.disposed,
        isTrue,
        reason: 'the reference tone must stop when the route is left',
      );
    },
  );
}
