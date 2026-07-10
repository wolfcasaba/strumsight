import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/features/learn/widgets/lesson_highway.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/features/settings/providers/input_latency_provider.dart';
import 'package:music_theory/features/settings/providers/visual_latency_provider.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

class _FixedMs extends InputLatencyNotifier {
  _FixedMs(this._v);
  final int _v;
  @override
  int build() => _v;
}

class _FixedVisualMs extends VisualLatencyNotifier {
  _FixedVisualMs(this._v);
  final int _v;
  @override
  int build() => _v;
}

/// Chunk 016b P3, the visual half: the highway is DRAWN shifted by the
/// audio↔display skew (tap-vs-click − tap-vs-flash) so a card crosses the
/// strike line when the beat is HEARD. Scoring keeps the true playhead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the highway draws with the calibrated audio↔display skew',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        strumEngineProvider.overrideWithValue(engine),
        // Audio 100 ms, visual 40 ms → skew 60 ms. First Strums is 70 BPM
        // → 0.06 s × (70/60) beats = 0.07 beats drawn LATER.
        inputLatencyProvider.overrideWith(() => _FixedMs(100)),
        visualLatencyProvider.overrideWith(() => _FixedVisualMs(40)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LearnScreen(lesson: Lessons.firstStrums),
      ),
    ));

    final highway =
        tester.widget<LessonHighway>(find.byType(LessonHighway));
    const truePlayhead = -4.0; // paused before start: −countIn beats
    final expected = truePlayhead - 0.06 * (Lessons.firstStrums.bpm / 60.0);
    expect(highway.playheadBeat, closeTo(expected, 1e-9));
  });

  testWidgets('uncalibrated devices draw the true playhead (no shift)',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [strumEngineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LearnScreen(lesson: Lessons.firstStrums),
      ),
    ));
    final highway =
        tester.widget<LessonHighway>(find.byType(LessonHighway));
    expect(highway.playheadBeat, closeTo(-4.0, 1e-9));
  });
}
