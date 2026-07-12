import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/learn/screens/learn_screen.dart';
import 'package:music_theory/features/live/model/live_frame.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

/// Round 147 — the LIVE twin of the r145 Analyze fix: a strum's frame arrives
/// ~70–140 ms after the attack (classify delay + emit cadence), and the emit
/// cadence part is 0–66 ms of JITTER that the constant latency calibration
/// cannot absorb. The frame carries BOTH clocks (emit instant + the strum's
/// attack instant), so the scorer can be handed the de-jittered time.
Lesson _lesson() => Lesson(
      id: 'jit',
      name: 'Jitter',
      bpm: 60, // 1 beat = 1 s; count-in = one 4/4 bar = 4 s
      chords: const ['C'],
      pattern: const [
        StrumDirection.down, null, null, null, null, null, null, null,
      ],
    );

LiveFrame _frame({required double attack, required double emit}) => LiveFrame(
      current: null,
      next: null,
      latestStrum: const Strum(direction: StrumDirection.down, confidence: 0.9),
      bar: const [],
      bpm: 60,
      inputLevel: 0.5,
      tuningHz: 440,
      listening: true,
      strumSeq: 1,
      latestStrumTime: attack,
      engineTimeSec: emit,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a stale frame is scored at the strum time, not arrival',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [strumEngineProvider.overrideWithValue(engine)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LearnScreen(lesson: _lesson()),
      ),
    ));
    await tester.tap(find.text('Play'));
    await tester.pump();

    // The event lands at elapsed 4.0 s (end of the 4-beat count-in). The
    // frame ARRIVES at 4.10 s carrying a strum whose attack was 100 ms ago
    // on the engine clock (emit − attack = 0.10).
    await tester.pump(const Duration(milliseconds: 4100));
    engine.emit(_frame(attack: 12.30, emit: 12.40));
    await tester.pump();

    // Uncorrected, 4.10 vs the 4.00 event is outside the ±50 ms PERFECT
    // window (it would read GOOD); corrected it is dead-on PERFECT.
    expect(find.text('Perfect!'), findsOneWidget,
        reason: 'the scorer must receive the de-jittered strum time');

    await tester.pumpWidget(const SizedBox());
  });
}
