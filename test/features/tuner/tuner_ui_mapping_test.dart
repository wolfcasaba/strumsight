import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/tuner/model/tuner_reading.dart';
import 'package:strumsight/features/tuner/model/tuner_stability.dart';
import 'package:strumsight/features/tuner/model/tuner_ui_state.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// A1/A2/A3/A7 (brief §6, §0.0/R5.1): the pitch estimator's `TunerReading`
/// carries no "idle"/"unstable" state of its own — every branch below is
/// either read straight off the estimator's fields or derived purely in the
/// UI layer (`TunerStability`), never in `engine/dsp/**` (§3, AGENTS.md §9).
void main() {
  group('A1 — tunerUiStateOf maps every measured branch', () {
    test('no signal → idle, regardless of stale cents/inTune', () {
      expect(
        tunerUiStateOf(hasSignal: false, inTune: true, unstable: true),
        TunerUiState.idle,
      );
    });

    test(
      'signal + unstable → unstable, even if the cents would be in tune',
      () {
        expect(
          tunerUiStateOf(hasSignal: true, inTune: true, unstable: true),
          TunerUiState.unstable,
        );
      },
    );

    test('signal + stable + in tune → inTune', () {
      expect(
        tunerUiStateOf(hasSignal: true, inTune: true, unstable: false),
        TunerUiState.inTune,
      );
    });

    test('signal + stable + not in tune → outOfTune', () {
      expect(
        tunerUiStateOf(hasSignal: true, inTune: false, unstable: false),
        TunerUiState.outOfTune,
      );
    });

    group('the three mandatory ±5 cent cells (brief §6.1)', () {
      test('under the threshold: ±3 cents → in tune', () {
        const reading = TunerReading(note: 'A', cents: 3, frequencyHz: 110);
        expect(reading.inTune, isTrue);
        expect(
          tunerUiStateOf(
            hasSignal: reading.hasSignal,
            inTune: reading.inTune,
            unstable: false,
          ),
          TunerUiState.inTune,
        );
      });

      test('on the boundary: exactly ±5 cents → in tune (inclusive)', () {
        const reading = TunerReading(note: 'A', cents: -5, frequencyHz: 110);
        expect(reading.inTune, isTrue);
        expect(
          tunerUiStateOf(
            hasSignal: reading.hasSignal,
            inTune: reading.inTune,
            unstable: false,
          ),
          TunerUiState.inTune,
        );
      });

      test('over the threshold: ±9 cents → not in tune', () {
        const reading = TunerReading(note: 'A', cents: 9, frequencyHz: 110);
        expect(reading.inTune, isFalse);
        expect(
          tunerUiStateOf(
            hasSignal: reading.hasSignal,
            inTune: reading.inTune,
            unstable: false,
          ),
          TunerUiState.outOfTune,
        );
      });
    });
  });

  group('TunerStability — the UI-derived "unstable" flag', () {
    test('no signal never reads as unstable, and resets the tracker', () {
      final stability = TunerStability();
      expect(stability.feed(hasSignal: false, note: '', cents: 0), isFalse);
    });

    test('a small drift on the same note is stable', () {
      final stability = TunerStability();
      stability.feed(hasSignal: true, note: 'A', cents: 0);
      expect(stability.feed(hasSignal: true, note: 'A', cents: 4), isFalse);
    });

    test('a big jump on the same note is unstable', () {
      final stability = TunerStability();
      stability.feed(hasSignal: true, note: 'A', cents: 0);
      expect(stability.feed(hasSignal: true, note: 'A', cents: 30), isTrue);
    });

    test('a note change never itself counts as unstable', () {
      final stability = TunerStability();
      stability.feed(hasSignal: true, note: 'A', cents: 0);
      expect(stability.feed(hasSignal: true, note: 'E', cents: 40), isFalse);
    });
  });

  Future<void> pumpTuner(
    WidgetTester tester,
    FakeTunerEngine engine, {
    Size? size,
    double textScale = 1.0,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...preferenceOverrides(),
          tunerEngineProvider.overrideWithValue(engine),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const TunerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('A2/A3 — the visible feedback row', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('sharp: a visible direction text and an icon (not colour '
        'alone)', (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      await pumpTuner(tester, engine);

      engine.emit(const TunerReading(note: 'A', cents: 18, frequencyHz: 110));
      await tester.pumpAndSettle();

      expect(find.text('18 cents sharp'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('flat: a visible direction text and an icon', (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      await pumpTuner(tester, engine);

      engine.emit(const TunerReading(note: 'A', cents: -18, frequencyHz: 110));
      await tester.pumpAndSettle();

      expect(find.text('18 cents flat'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('in tune: icon + visible text + colour together (A3)', (
      tester,
    ) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      await pumpTuner(tester, engine);

      engine.emit(const TunerReading(note: 'A', cents: 0, frequencyHz: 110));
      await tester.pumpAndSettle();

      expect(find.text('IN TUNE'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });

  group('A7 — 2.0 text scale + landscape never overflows', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('portrait at textScale 2.0', (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      await pumpTuner(
        tester,
        engine,
        size: const Size(320, 690),
        textScale: 2.0,
      );
      engine.emit(const TunerReading(note: 'A', cents: 2, frequencyHz: 110));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('landscape at textScale 2.0', (tester) async {
      final engine = FakeTunerEngine();
      addTearDown(engine.dispose);
      await pumpTuner(
        tester,
        engine,
        size: const Size(844, 390),
        textScale: 2.0,
      );
      engine.emit(const TunerReading(note: 'A', cents: -12, frequencyHz: 110));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
