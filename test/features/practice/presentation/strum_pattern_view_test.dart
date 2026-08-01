// E02-R14 — A5 Strum Pattern mode-view test.
//
// The phase delivers the pattern preview and the verdict-driven feedback.
// The widget renders correctly with null verdict and null metrics — the
// host wires the live values in a later round (R10).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/views/strum_pattern_view.dart';
import 'package:strumsight/l10n/app_localizations.dart';

CompiledTargetEvent _event({
  required int barIndex,
  required Duration time,
  StrumDirection? direction,
  String? chord,
  String id = 'e',
}) => CompiledTargetEvent(
  sourceEventId: id,
  loopIndex: 0,
  position: BeatPosition.quarters(barIndex * 4),
  time: time,
  barIndex: barIndex,
  chord: chord,
  direction: direction,
  accent: false,
  optional: false,
);

CompiledPracticeTarget _target({required List<CompiledTargetEvent> events}) {
  final total = events.isEmpty ? Duration.zero : events.last.time;
  return CompiledPracticeTarget(
    definitionId: 'strum-pattern',
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
    expectedChordSegments: const [],
    scoringApplicable: true,
  );
}

PracticeVerdict _verdict({
  TimingGrade grade = TimingGrade.perfect,
  DirectionOutcome direction = DirectionOutcome.correct,
  StrumDirection? expectedDirection = StrumDirection.down,
}) => PracticeVerdict(
  targetEventId: 'e0',
  matchedObservationSequence: 1,
  targetAt: const Duration(milliseconds: 500),
  observedAt: const Duration(milliseconds: 500),
  timingOffset: Duration.zero,
  timingGrade: grade,
  expectedDirection: expectedDirection,
  observedDirection: expectedDirection,
  directionOutcome: direction,
  expectedChord: null,
  observedChord: null,
  chordOutcome: ChordOutcome.notApplicable,
  eventScore: 1.0,
  missReasonCode: null,
  coachingCode: null,
);

const PracticeMetrics _metrics = PracticeMetrics(
  completion: MetricAvailable(0.5),
  rhythm: MetricAvailable(0.8),
  direction: MetricAvailable(0.9),
  chord: MetricNotApplicable(),
  overall: MetricAvailable(0.85),
  totalTargets: 8,
  resolvedTargets: 4,
  maxCombo: 3,
  scorePoints: 340,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The strum pattern view is a Column with explicit dimensions; the
    // default test surface is too small for the highway + preview +
    // feedback. Override the surface so the layout fits.
  });

  testWidgets('renders the pattern preview with down/up/rest cells', (
    tester,
  ) async {
    final target = _target(
      events: [
        _event(
          barIndex: 0,
          time: const Duration(milliseconds: 500),
          direction: StrumDirection.down,
        ),
        _event(
          barIndex: 0,
          time: const Duration(milliseconds: 1000),
          direction: StrumDirection.up,
        ),
        _event(
          barIndex: 0,
          time: const Duration(milliseconds: 1500),
          direction: null,
        ),
      ],
    );
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StrumPatternView(
              target: target,
              playhead: const Duration(milliseconds: 200),
              visualOffset: Duration.zero,
              width: 600,
              highwayHeight: 168,
              lastVerdict: null,
              metrics: null,
            ),
          ),
        ),
      ),
    );
    // Pattern preview: one Down, one Up, one Rest — each rendered by a
    // distinct icon. The highway also renders the same arrows, so the
    // total is 2 (one preview + one marker) for each direction.
    expect(find.byIcon(Icons.arrow_downward), findsNWidgets(2));
    expect(find.byIcon(Icons.arrow_upward), findsNWidgets(2));
    expect(find.byIcon(Icons.remove), findsNWidgets(2));
  });

  testWidgets('perfect verdict shows the Timing label and the Perfect copy', (
    tester,
  ) async {
    final target = _target(
      events: [
        _event(
          barIndex: 0,
          time: const Duration(milliseconds: 500),
          direction: StrumDirection.down,
        ),
      ],
    );
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StrumPatternView(
              target: target,
              playhead: const Duration(milliseconds: 200),
              visualOffset: Duration.zero,
              width: 600,
              highwayHeight: 168,
              lastVerdict: _verdict(grade: TimingGrade.perfect),
              metrics: _metrics,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Perfect!'), findsOneWidget);
    expect(find.text('Best combo'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('wrong direction shows the expected-direction label', (
    tester,
  ) async {
    final target = _target(
      events: [
        _event(
          barIndex: 0,
          time: const Duration(milliseconds: 500),
          direction: StrumDirection.down,
        ),
      ],
    );
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StrumPatternView(
              target: target,
              playhead: const Duration(milliseconds: 200),
              visualOffset: Duration.zero,
              width: 600,
              highwayHeight: 168,
              lastVerdict: _verdict(
                grade: TimingGrade.good,
                direction: DirectionOutcome.wrong,
                expectedDirection: StrumDirection.up,
              ),
              metrics: _metrics,
            ),
          ),
        ),
      ),
    );
    // The wrong-direction label interpolates the expected direction.
    expect(find.textContaining('Up'), findsWidgets);
  });

  testWidgets('renders without exception when verdict and metrics are null', (
    tester,
  ) async {
    final target = _target(
      events: [
        _event(
          barIndex: 0,
          time: const Duration(milliseconds: 500),
          direction: StrumDirection.down,
        ),
      ],
    );
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StrumPatternView(
              target: target,
              playhead: const Duration(milliseconds: 200),
              visualOffset: Duration.zero,
              width: 600,
              highwayHeight: 168,
              lastVerdict: null,
              metrics: null,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Wait for the first verdict…'), findsOneWidget);
  });
}
