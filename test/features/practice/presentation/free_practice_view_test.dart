import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/free_practice_summary.dart';
import 'package:strumsight/features/practice/presentation/views/free_practice_view.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/preference_store.dart';

void main() {
  testWidgets('A7 — null summary shows the explicit "no strums" copy', (
    tester,
  ) async {
    await _pump(tester, const FreePracticeView(summary: null, width: 320));

    expect(find.text('No strums heard yet'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'No strums heard yet in this free-practice session',
      ),
      findsOneWidget,
    );
  });

  testWidgets('A7 — empty summary shows the explicit "no strums" copy', (
    tester,
  ) async {
    final summary = FreePracticeSummary(
      strumCount: 0,
      activeDuration: const Duration(seconds: 5),
      chordTimelineDuration: Duration.zero,
      chordTimeline: const [],
      bpmSamples: const [],
      tempoStability: const FreePracticeTempoStabilityInsufficientData(),
      directionRatio: const FreePracticeDirectionRatioInsufficientData(),
    );
    await _pump(tester, FreePracticeView(summary: summary, width: 320));

    expect(find.text('No strums heard yet'), findsOneWidget);
  });

  testWidgets('A7 — populated summary renders facts but no score', (
    tester,
  ) async {
    final summary = FreePracticeSummary(
      strumCount: 7,
      activeDuration: const Duration(seconds: 12),
      chordTimelineDuration: const Duration(seconds: 8),
      chordTimeline: const [
        FreePracticeChordSegment(label: 'G', duration: Duration(seconds: 4)),
        FreePracticeChordSegment(label: null, duration: Duration(seconds: 1)),
        FreePracticeChordSegment(label: 'C', duration: Duration(seconds: 3)),
      ],
      bpmSamples: const [
        FreePracticeBpmSample(bpm: 90, at: Duration(milliseconds: 500)),
      ],
      tempoStability: const FreePracticeTempoStabilityAvailable(
        Duration(milliseconds: 50),
      ),
      directionRatio: const FreePracticeDirectionRatioAvailable(
        downCount: 4,
        upCount: 3,
        downRatio: 4 / 7,
        upRatio: 3 / 7,
      ),
    );
    await _pump(tester, FreePracticeView(summary: summary, width: 320));

    expect(find.text('Practice counts'), findsOneWidget);
    expect(find.text('Strum count'), findsOneWidget);
    expect(find.text('Active time'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Direction (informational)'), findsOneWidget);
    expect(find.text('Down strums'), findsOneWidget);
    expect(find.text('Up strums'), findsOneWidget);
    expect(find.text('Chord timeline'), findsOneWidget);
    expect(find.text('No chord'), findsOneWidget);
    expect(find.text('Detected BPM samples'), findsOneWidget);

    // Audited-found strings from the A7 brief — must NOT appear.
    expect(
      find.textContaining('accuracy', findRichText: true),
      findsNothing,
      reason: 'A7 forbids "accuracy" in any free-practice label',
    );
    expect(
      find.textContaining('score', findRichText: true),
      findsNothing,
      reason: 'A7 forbids "score" in any free-practice label',
    );
    expect(
      find.textContaining('pass', findRichText: true),
      findsNothing,
      reason: 'A7 forbids "pass" in any free-practice label',
    );
  });

  testWidgets('A7 — direction NotApplicable renders the localized copy', (
    tester,
  ) async {
    final summary = FreePracticeSummary(
      strumCount: 4,
      activeDuration: const Duration(seconds: 5),
      chordTimelineDuration: Duration.zero,
      chordTimeline: const [],
      bpmSamples: const [],
      tempoStability: const FreePracticeTempoStabilityAvailable(Duration.zero),
      directionRatio: const FreePracticeDirectionRatioNotApplicable(),
    );
    await _pump(tester, FreePracticeView(summary: summary, width: 320));

    expect(
      find.text('Direction is not applicable for this practice'),
      findsOneWidget,
    );
  });

  testWidgets('A7 — InsufficientData directions render the localized copy', (
    tester,
  ) async {
    final summary = FreePracticeSummary(
      strumCount: 0,
      activeDuration: const Duration(seconds: 5),
      chordTimelineDuration: Duration.zero,
      chordTimeline: const [],
      bpmSamples: const [],
      tempoStability: const FreePracticeTempoStabilityInsufficientData(),
      directionRatio: const FreePracticeDirectionRatioInsufficientData(),
    );
    await _pump(tester, FreePracticeView(summary: summary, width: 320));

    // The "no strums heard yet" card replaces everything when strumCount is 0.
    expect(find.text('No strums heard yet'), findsOneWidget);
  });

  for (final size in [const Size(320, 568), const Size(915, 412)]) {
    testWidgets('A8 — fits without overflow at $size', (tester) async {
      final summary = FreePracticeSummary(
        strumCount: 7,
        activeDuration: const Duration(seconds: 12),
        chordTimelineDuration: const Duration(seconds: 8),
        chordTimeline: const [
          FreePracticeChordSegment(label: 'G', duration: Duration(seconds: 4)),
          FreePracticeChordSegment(label: null, duration: Duration(seconds: 1)),
          FreePracticeChordSegment(label: 'C', duration: Duration(seconds: 3)),
        ],
        bpmSamples: const [
          FreePracticeBpmSample(bpm: 90, at: Duration(milliseconds: 500)),
        ],
        tempoStability: const FreePracticeTempoStabilityAvailable(
          Duration(milliseconds: 50),
        ),
        directionRatio: const FreePracticeDirectionRatioAvailable(
          downCount: 4,
          upCount: 3,
          downRatio: 4 / 7,
          upRatio: 3 / 7,
        ),
      );
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _material(
          SingleChildScrollView(
            child: FreePracticeView(summary: summary, width: size.width - 32),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_material(SingleChildScrollView(child: child)));
}

Widget _material(Widget child) => ProviderScope(
  overrides: preferenceOverrides(),
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);
