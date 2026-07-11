import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/screens/chord_library_screen.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/features/learn/screens/lesson_list_screen.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/features/metronome/screens/metronome_screen.dart';
import 'package:music_theory/features/progress/screens/progress_screen.dart';
import 'package:music_theory/features/tuner/model/tuner_reading.dart';
import 'package:music_theory/features/tuner/providers/tuner_providers.dart';
import 'package:music_theory/features/tuner/screens/tuner_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_engines.dart';

/// Round 96 — layout guard: every main screen must build WITHOUT overflow on
/// a small phone (320×568 logical, iPhone-SE class) and in landscape
/// (915×412). RenderFlex overflows surface as test-framework exceptions, so
/// pumping alone is the assertion.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> atSize(WidgetTester tester, Size logical,
      Future<void> Function() pumpScreen) async {
    tester.view.physicalSize = logical;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpScreen();
    await tester.pump(const Duration(milliseconds: 400));
  }

  final sizes = <String, Size>{
    'small portrait (320×568)': const Size(320, 568),
    'landscape (915×412)': const Size(915, 412),
  };

  for (final entry in sizes.entries) {
    group(entry.key, () {
      testWidgets('Tuner (with a live reading)', (tester) async {
        final engine = FakeTunerEngine();
        addTearDown(engine.dispose);
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(ProviderScope(
            overrides: [tunerEngineProvider.overrideWithValue(engine)],
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: TunerScreen(),
            ),
          ));
          await tester.pump();
          engine.emit(
              const TunerReading(note: 'A', cents: 3, frequencyHz: 110));
          await tester.pump();
        });
      });

      testWidgets('Learn home (lesson list)', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: LessonListScreen(now: DateTime(2026, 7, 11)),
            ),
          ));
        });
      });

      testWidgets('Learn player (paused, with score HUD area)',
          (tester) async {
        final engine = FakeStrumEngine();
        addTearDown(engine.dispose);
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(ProviderScope(
            overrides: [strumEngineProvider.overrideWithValue(engine)],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: LearnScreen(lesson: Lessons.downUpGroove),
            ),
          ));
        });
      });

      testWidgets('Metronome', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const MetronomeScreen(),
          ));
        });
      });

      testWidgets('Chord library', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(ProviderScope(
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ChordLibraryScreen(),
            ),
          ));
        });
      });

      testWidgets('Progress', (tester) async {
        await atSize(tester, entry.value, () async {
          await tester.pumpWidget(ProviderScope(
            child: const MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ProgressScreen(),
            ),
          ));
        });
      });
    });
  }
}
