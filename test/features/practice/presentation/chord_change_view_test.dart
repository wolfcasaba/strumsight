import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/chords/public.dart';
import 'package:strumsight/features/practice/domain/model/chord_pair_stats.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/views/chord_change_view.dart';
import 'package:strumsight/features/practice/presentation/widgets/chord_change_breakdown.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/preference_store.dart';

void main() {
  testWidgets('renders current and next chord diagrams with a11y labels', (
    tester,
  ) async {
    await _pump(
      tester,
      ChordChangeView(
        target: _target(),
        playhead: const Duration(milliseconds: 500),
        width: 320,
        latestChange: const ChordChangeMeasurement(
          pair: ChordPair(from: 'G', to: 'D'),
          targetAt: Duration.zero,
          outcome: ChordChangeOutcome.correct,
          recognizedChangeDelay: Duration(milliseconds: 100),
          observedChord: 'D',
          stableDuration: Duration(milliseconds: 180),
        ),
      ),
    );

    expect(find.byType(ChordDiagram), findsNWidgets(2));
    expect(find.text('Recognized and stable chord'), findsOneWidget);
    expect(find.bySemanticsLabel('Current chord: G'), findsOneWidget);
    expect(find.bySemanticsLabel('Next chord: D'), findsOneWidget);
  });

  testWidgets(
    'renders no detection and insufficient signal as distinct neutral states',
    (tester) async {
      for (final outcome in [
        ChordChangeOutcome.noDetection,
        ChordChangeOutcome.insufficientSignal,
      ]) {
        await _pump(
          tester,
          ChordChangeView(
            target: _target(),
            playhead: const Duration(milliseconds: 500),
            width: 320,
            latestChange: ChordChangeMeasurement(
              pair: const ChordPair(from: 'G', to: 'D'),
              targetAt: Duration.zero,
              outcome: outcome,
            ),
          ),
        );
        expect(find.text(_outcomeText(outcome)), findsOneWidget);
        final card = tester.widget<Card>(find.byType(Card).last);
        expect(card.color, isNot(Colors.red));
      }
    },
  );

  testWidgets('marks lossy detector-label mapping in the breakdown', (
    tester,
  ) async {
    await _pump(
      tester,
      ChordChangeBreakdown(
        pairStats: [
          ChordPairStats(
            pair: const ChordPair(from: 'G', to: 'D'),
            attempts: 3,
            correctChanges: 3,
            wrongChordCount: 0,
            noDetectionCount: 0,
            unstableCount: 0,
            insufficientSignalCount: 0,
            recognizedChangeDelays: const [
              Duration(milliseconds: 100),
              Duration(milliseconds: 200),
              Duration(milliseconds: 300),
            ],
            labelMappingIsLossy: true,
          ),
        ],
      ),
    );

    expect(find.text('G → D'), findsOneWidget);
    expect(find.text('Median change delay: 200 ms'), findsOneWidget);
    expect(
      find.textContaining('Detector label mapping is limited'),
      findsOneWidget,
    );
  });

  for (final size in [const Size(320, 568), const Size(915, 412)]) {
    testWidgets('fits without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _material(
          SingleChildScrollView(
            child: ChordChangeView(
              target: _target(),
              playhead: const Duration(milliseconds: 500),
              width: size.width - 32,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

String _outcomeText(ChordChangeOutcome outcome) => switch (outcome) {
  ChordChangeOutcome.correct => 'Recognized and stable chord',
  ChordChangeOutcome.wrongChord => 'Different chord recognized',
  ChordChangeOutcome.noDetection => 'No chord detected',
  ChordChangeOutcome.unstable => 'Chord label was not stable',
  ChordChangeOutcome.insufficientSignal => 'Not enough signal for this change',
};

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

CompiledPracticeTarget _target() => CompiledPracticeTarget(
  definitionId: 'chord-change-view',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(60),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 0,
  countInDuration: Duration.zero,
  events: const [],
  musicalDuration: const Duration(seconds: 8),
  ringOutDuration: Duration.zero,
  totalDuration: const Duration(seconds: 8),
  barBoundaries: const [],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const [
    ExpectedChordSegment(
      chord: 'G',
      start: Duration.zero,
      end: Duration(seconds: 1),
    ),
    ExpectedChordSegment(
      chord: 'D',
      start: Duration(seconds: 1),
      end: Duration(seconds: 8),
    ),
  ],
  scoringApplicable: true,
);
