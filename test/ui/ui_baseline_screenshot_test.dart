import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/mock_strum_engine.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/tuner/model/tuner_reading.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/main.dart';

import '../support/fake_engines.dart';
import '../support/preference_store.dart';

const _captureBaseline = bool.fromEnvironment('CAPTURE_UI_BASELINE');
const _baselineScreenshots = <String>[
  'docs/ui/baseline/screenshots/live-compact-portrait.png',
  'docs/ui/baseline/screenshots/tuner-compact-portrait.png',
  'docs/ui/baseline/screenshots/analyze-compact-portrait.png',
  'docs/ui/baseline/screenshots/learn-compact-portrait.png',
  'docs/ui/baseline/screenshots/library-compact-portrait.png',
  'docs/ui/baseline/screenshots/settings-compact-portrait.png',
  'docs/ui/baseline/screenshots/onboarding-compact-portrait.png',
];

void main() {
  testWidgets(
    'the exact compact portrait baseline corpus is decodable and non-empty',
    (tester) async {
      expect(_baselineScreenshots, hasLength(7));
      expect(_baselineScreenshots.toSet(), hasLength(7));

      for (final relativePath in _baselineScreenshots) {
        final file = File(relativePath);
        expect(
          await file.exists(),
          isTrue,
          reason: '$relativePath is required',
        );

        final bytes = await file.readAsBytes();
        expect(
          bytes,
          isNotEmpty,
          reason: '$relativePath must contain PNG bytes',
        );

        final ui.Image image = await decodeImageFromList(bytes);
        addTearDown(image.dispose);
        expect(image.width, greaterThan(0), reason: '$relativePath has width');
        expect(
          image.height,
          greaterThan(0),
          reason: '$relativePath has height',
        );
        expect(
          image.width,
          lessThan(image.height),
          reason: '$relativePath must be compact portrait',
        );
      }
    },
    skip: _captureBaseline,
  );

  testWidgets(
    'captures the seven fixed production-widget baseline states',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final strumEngine = FakeStrumEngine();
      final tunerEngine = FakeTunerEngine();
      addTearDown(strumEngine.dispose);
      addTearDown(tunerEngine.dispose);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            strumEngineProvider.overrideWithValue(strumEngine),
            tunerEngineProvider.overrideWithValue(tunerEngine),
          ],
          child: const StrumSightApp(),
        ),
      );
      await tester.pumpAndSettle();
      strumEngine.emit(
        MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      await _capture(tester, _baselineScreenshots[0]);

      for (final screen in <(String, String)>[
        ('Analyze', _baselineScreenshots[2]),
        ('Learn', _baselineScreenshots[3]),
        ('Library', _baselineScreenshots[4]),
        ('Settings', _baselineScreenshots[5]),
      ]) {
        await tester.tap(find.text(screen.$1).last);
        await tester.pumpAndSettle();
        await _capture(tester, screen.$2);
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            tunerEngineProvider.overrideWithValue(tunerEngine),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TunerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tunerEngine.emit(
        const TunerReading(note: 'A', cents: 0, frequencyHz: 110),
      );
      await tester.pumpAndSettle();
      await _capture(tester, _baselineScreenshots[1]);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: preferenceOverrides(),
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, _baselineScreenshots[6]);
    },
    skip: !_captureBaseline,
  );
}

Future<void> _capture(WidgetTester tester, String path) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('../../$path'));
