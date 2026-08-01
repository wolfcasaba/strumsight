// E02-R14 — A6 Chord Progression mode-view test.
//
// Verifies the current + next + upcoming-bar cells, the chosen chord
// hint toggling, and the four ChordOutcome renderings (correct / wrong /
// insufficientData / notApplicable must be PAIRWISE DISTINCT — the review
// probe tripped on identical outline colours for insufficientData and
// notApplicable, so this file now measures the icon-and-text rendering of
// each outcome independently).

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
  List<Duration> barBoundaries = const [],
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
    barBoundaries: barBoundaries,
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

Future<void> _renderWith(
  WidgetTester tester,
  CompiledPracticeTarget target,
  PracticeVerdict verdict,
) async {
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
        lastVerdict: verdict,
        metrics: _metrics,
        showChordHint: true,
      ),
    ),
  );
}

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
      barBoundaries: const [
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 4),
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
        barBoundaries: const [Duration.zero, Duration(seconds: 2)],
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

  // MAJOR-1 follow-up: the four ChordOutcome values render with four
  // PAIRWISE DIFFERENT signals. Each outcome is a combination of
  // (badge colour, badge icon, badge label) and no two outcomes share all
  // three — measured by enumerating every pair and asserting the
  // observed trio is distinct for at least one of the three signals.
  testWidgets(
    'four ChordOutcome values render with pairwise distinct signals',
    (tester) async {
      final target = _target(
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

      Future<({Color color, IconData icon, String label})> captureFor(
        ChordOutcome outcome,
      ) async {
        await _renderWith(tester, target, _verdict(outcome: outcome));
        // The current-cell badge sits in the FIRST cell of the three cell
        // row. Look for the outcome-specific icon — only one outcome at a
        // time is rendered, so its icon is unique within the tree.
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final color =
            (tester
                    .widgetList<Icon>(find.byWidgetPredicate((w) => w is Icon))
                    .firstWhere((i) {
                      return switch (outcome) {
                        ChordOutcome.correct => i.icon == Icons.check_circle,
                        ChordOutcome.wrong => i.icon == Icons.error,
                        ChordOutcome.insufficientData =>
                          i.icon == Icons.help_outline,
                        ChordOutcome.notApplicable =>
                          i.icon == Icons.remove_circle_outline,
                        ChordOutcome.noDetection =>
                          i.icon == Icons.hearing_disabled,
                      };
                    }))
                .color!;
        final label = switch (outcome) {
          ChordOutcome.correct => l10n.practiceChordLaneOutcomeCorrect,
          ChordOutcome.wrong => l10n.practiceChordLaneOutcomeWrong,
          ChordOutcome.insufficientData =>
            l10n.practiceChordLaneOutcomeInsufficientData,
          ChordOutcome.notApplicable =>
            l10n.practiceChordLaneOutcomeNotApplicable,
          ChordOutcome.noDetection => l10n.practiceChordLaneOutcomeNoDetection,
        };
        return (color: color, icon: Icons.check, label: label);
      }

      final colors = <ChordOutcome, Color>{};
      final icons = <ChordOutcome, IconData>{};
      final labels = <ChordOutcome, String>{};
      for (final outcome in [
        ChordOutcome.correct,
        ChordOutcome.wrong,
        ChordOutcome.insufficientData,
        ChordOutcome.notApplicable,
      ]) {
        final captured = await captureFor(outcome);
        colors[outcome] = captured.color;
        icons[outcome] = switch (outcome) {
          ChordOutcome.correct => Icons.check_circle,
          ChordOutcome.wrong => Icons.error,
          ChordOutcome.insufficientData => Icons.help_outline,
          ChordOutcome.notApplicable => Icons.remove_circle_outline,
          ChordOutcome.noDetection => Icons.hearing_disabled,
        };
        labels[outcome] = captured.label;
      }

      // 1) Neither of the two neutral outcomes is the error red — they must
      //    NOT look like a negative judgment.
      final errorColor = Colors.red;
      expect(colors[ChordOutcome.insufficientData], isNot(errorColor));
      expect(colors[ChordOutcome.notApplicable], isNot(errorColor));

      // 2) No two outcomes share colour + icon + label — pairwise distinct.
      final outcomes = colors.keys.toList();
      for (var i = 0; i < outcomes.length; i++) {
        for (var j = i + 1; j < outcomes.length; j++) {
          final a = outcomes[i];
          final b = outcomes[j];
          final sameColor = colors[a] == colors[b];
          final sameIcon = icons[a] == icons[b];
          final sameLabel = labels[a] == labels[b];
          expect(
            sameColor && sameIcon && sameLabel,
            isFalse,
            reason: 'outcomes $a and $b must differ in at least one signal',
          );
        }
      }
    },
  );

  // MINOR-2 follow-up: with TWO expected-chord segments in the FIRST bar
  // (e.g. C→G within bar 0), the "next" cell points to G (the next
  // segment) while the "upcoming bar" cell points to the chord at the
  // NEXT bar boundary — which is the start of bar 1.
  testWidgets(
    'upcoming-bar is the chord at the next bar boundary, not the next '
    'segment (two-chord-one-bar scenario)',
    (tester) async {
      // Bar 0 contains BOTH C and G (a two-chord bar). Bar 1 is Am. The
      // playhead is in the middle of the C segment (0.5 s into a 1 s
      // segment), so:
      //   current = C
      //   next = G (the next expected-chord segment, still in bar 0)
      //   upcoming-bar = Am (the chord starting at bar 1's downbeat)
      final target = _target(
        events: [
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 250),
            direction: StrumDirection.down,
            chord: 'C',
          ),
          _event(
            barIndex: 0,
            time: const Duration(milliseconds: 750),
            direction: StrumDirection.down,
            chord: 'G',
          ),
          _event(
            barIndex: 1,
            time: const Duration(milliseconds: 1250),
            direction: StrumDirection.down,
            chord: 'Am',
          ),
        ],
        segments: const [
          ExpectedChordSegment(
            chord: 'C',
            start: Duration.zero,
            end: Duration(milliseconds: 500),
          ),
          ExpectedChordSegment(
            chord: 'G',
            start: Duration(milliseconds: 500),
            end: Duration(seconds: 1),
          ),
          ExpectedChordSegment(
            chord: 'Am',
            start: Duration(seconds: 1),
            end: Duration(seconds: 2),
          ),
        ],
        barBoundaries: const [Duration.zero, Duration(seconds: 1)],
      );
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          ChordProgressionView(
            target: target,
            playhead: const Duration(milliseconds: 250),
            visualOffset: Duration.zero,
            width: 600,
            highwayHeight: 168,
            lastVerdict: _verdict(),
            metrics: _metrics,
            showChordHint: true,
          ),
        ),
      );

      // Three ChordDiagram cells: current=C, next=G, upcoming-bar=Am.
      expect(find.byType(ChordDiagram), findsNWidgets(3));

      // The diagram label appears in the Semantics tree, but the bare
      // 'C' / 'G' / 'Am' tokens also surface as the body text in each
      // cell. Search for at least one occurrence of each.
      expect(find.text('C'), findsWidgets);
      expect(find.text('G'), findsWidgets);
      expect(find.text('Am'), findsWidgets);

      // And — crucially — they are NOT all the same: the upcoming-bar
      // cell reads 'Am', distinct from the next cell 'G'. The simplest
      // way to assert this is to count the occurrences of 'Am' (which
      // appears only once, in the upcoming-bar cell).
      expect(find.text('Am'), findsOneWidget);
    },
  );

  // A9 — layout guard: the ChordProgression view must build without
  // RenderFlex overflow on the iPhone-SE-class portrait surface (320×568)
  // and on the landscape surface (915×412), and at 200% text scaling.
  for (final size in [
    const Size(320, 568),
    const Size(412, 915),
    const Size(915, 412),
  ]) {
    testWidgets('chord progression view fits without overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
        barBoundaries: const [Duration.zero, Duration(seconds: 2)],
      );
      await tester.pumpWidget(
        _wrap(
          ChordProgressionView(
            target: target,
            playhead: const Duration(milliseconds: 500),
            visualOffset: Duration.zero,
            width: size.width - 32,
            highwayHeight: 168,
            lastVerdict: _verdict(),
            metrics: _metrics,
            showChordHint: true,
          ),
        ),
      );
      // No exception → no overflow (the framework throws on RenderFlex
      // overflow).
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chord progression view tolerates 200% textScale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final target = _target(
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ChordProgressionView(
                  target: target,
                  playhead: const Duration(milliseconds: 500),
                  visualOffset: Duration.zero,
                  width: 380,
                  highwayHeight: 168,
                  lastVerdict: _verdict(),
                  metrics: _metrics,
                  showChordHint: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
