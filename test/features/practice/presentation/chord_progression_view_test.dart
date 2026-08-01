// E02-R14 — A6 Chord Progression mode-view test.
//
// Verifies the current + next + upcoming-bar cells, the chosen chord
// hint toggling, and the four ChordOutcome renderings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/chords/public.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/views/chord_progression_view.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/preference_store.dart';

CompiledTargetEvent _event({
  required int barIndex,
  required Duration time,
  StrumDirection? direction,
  String? chord,
}) => CompiledTargetEvent(
  sourceEventId: 'e$barIndex',
  loopIndex: 0,
  position: BeatPosition.quarters(barIndex * 4),
  time: time,
  barIndex: barIndex,
  chord: chord,
  direction: direction,
  accent: false,
  optional: false,
);

CompiledPracticeTarget _target({
  required List<CompiledTargetEvent> events,
  required List<ExpectedChordSegment> segments,
}) {
  final total = events.isEmpty ? Duration.zero : events.last.time;
  return CompiledPracticeTarget(
    definitionId: 'chord-progression',
    definitionSnapshotVersion: 1,
    tempo: const Tempo(120),
    meter: const Meter(beatsPerBar: 4),
    countInBars: 0,
    countInDuration: Duration.zero,
    events: events,
    musicalDuration: total,
    ringOutDuration: Duration.zero,
    totalDuration: total,
    barBoundaries: const [],
    loopCount: 1,
    loopRange: null,
    expectedChordSegments: segments,
    scoringApplicable: true,
  );
}

PracticeVerdict _verdict({ChordOutcome outcome = ChordOutcome.correct}) =>
    PracticeVerdict(
      targetEventId: 'e0',
      matchedObservationSequence: 1,
      targetAt: const Duration(milliseconds: 500),
      observedAt: const Duration(milliseconds: 500),
      timingOffset: Duration.zero,
      timingGrade: TimingGrade.perfect,
      expectedDirection: StrumDirection.down,
      observedDirection: StrumDirection.down,
      directionOutcome: DirectionOutcome.correct,
      expectedChord: 'C',
      observedChord: 'C',
      chordOutcome: outcome,
      eventScore: 1.0,
      missReasonCode: null,
      coachingCode: null,
    );

const PracticeMetrics _metrics = PracticeMetrics(
  completion: MetricAvailable(0.5),
  rhythm: MetricAvailable(0.8),
  direction: MetricAvailable(0.9),
  chord: MetricAvailable(0.9),
  overall: MetricAvailable(0.85),
  totalTargets: 4,
  resolvedTargets: 4,
  maxCombo: 4,
  scorePoints: 340,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
);

Widget _wrap(Widget child) => ProviderScope(
  overrides: preferenceOverrides(),
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('current + next + upcoming-bar cells render with ChordDiagram', (
    tester,
  ) async {
    final target = _target(
      events: [
        _event(
          barIndex: 0,
          time: const Duration(milliseconds: 500),
          direction: StrumDirection.down,
          chord: 'C',
        ),
        _event(
          barIndex: 1,
          time: const Duration(milliseconds: 2500),
          direction: StrumDirection.down,
          chord: 'G',
        ),
        _event(
          barIndex: 2,
          time: const Duration(milliseconds: 4500),
          direction: StrumDirection.down,
          chord: 'Am',
        ),
      ],
      segments: const [
        ExpectedChordSegment(
          chord: 'C',
          start: Duration.zero,
          end: Duration(seconds: 2),
        ),
        ExpectedChordSegment(
          chord: 'G',
          start: Duration(seconds: 2),
          end: Duration(seconds: 4),
        ),
        ExpectedChordSegment(
          chord: 'Am',
          start: Duration(seconds: 4),
          end: Duration(seconds: 6),
        ),
      ],
    );
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        ChordProgressionView(
          target: target,
          playhead: const Duration(milliseconds: 500),
          visualOffset: Duration.zero,
          width: 600,
          highwayHeight: 168,
          lastVerdict: _verdict(),
          metrics: _metrics,
          showChordHint: true,
        ),
      ),
    );
    expect(find.byType(ChordDiagram), findsNWidgets(3));
  });

  testWidgets(
    'showChordHint=false clears the chord hint (R10 / legacy parity)',
    (tester) async {
      final target = _target(
        events: [
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 500),
            direction: StrumDirection.down,
            chord: 'C',
          ),
          _event(
            barIndex: 1,
            time: const Duration(milliseconds: 2500),
            direction: StrumDirection.down,
            chord: 'G',
          ),
        ],
        segments: const [
          ExpectedChordSegment(
            chord: 'C',
            start: Duration.zero,
            end: Duration(seconds: 2),
          ),
          ExpectedChordSegment(
            chord: 'G',
            start: Duration(seconds: 2),
            end: Duration(seconds: 4),
          ),
        ],
      );
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          ChordProgressionView(
            target: target,
            playhead: const Duration(milliseconds: 500),
            visualOffset: Duration.zero,
            width: 600,
            highwayHeight: 168,
            lastVerdict: _verdict(),
            metrics: _metrics,
            showChordHint: false,
          ),
        ),
      );
      expect(find.byType(ChordDiagram), findsNothing);
    },
  );

  testWidgets('four ChordOutcome values render the chord label', (
    tester,
  ) async {
    final baseTarget = _target(
      events: [
        _event(
          barIndex: 0,
          time: const Duration(milliseconds: 500),
          direction: StrumDirection.down,
          chord: 'C',
        ),
      ],
      segments: const [
        ExpectedChordSegment(
          chord: 'C',
          start: Duration.zero,
          end: Duration(seconds: 2),
        ),
      ],
    );
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Future<void> renderWith(ChordOutcome outcome) async {
      await tester.pumpWidget(
        _wrap(
          ChordProgressionView(
            target: baseTarget,
            playhead: const Duration(milliseconds: 500),
            visualOffset: Duration.zero,
            width: 600,
            highwayHeight: 168,
            lastVerdict: _verdict(outcome: outcome),
            metrics: _metrics,
            showChordHint: true,
          ),
        ),
      );
    }

    await renderWith(ChordOutcome.correct);
    expect(find.text('C'), findsWidgets);

    await renderWith(ChordOutcome.wrong);
    expect(find.text('C'), findsWidgets);

    await renderWith(ChordOutcome.insufficientData);
    expect(find.text('C'), findsWidgets);

    await renderWith(ChordOutcome.notApplicable);
    expect(find.text('C'), findsWidgets);
  });
}
