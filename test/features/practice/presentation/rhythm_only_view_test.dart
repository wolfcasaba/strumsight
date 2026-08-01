import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/views/rhythm_only_view.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../support/preference_store.dart';

void main() {
  testWidgets('A1 — direction-less definition shows the available rhythm row', (
    tester,
  ) async {
    await _pump(
      tester,
      RhythmOnlyView(
        target: _target(withDirection: false),
        playhead: const Duration(milliseconds: 500),
        width: 320,
        metrics: null,
      ),
    );

    expect(find.text('Rhythm-only practice'), findsOneWidget);
    expect(
      find.textContaining('chord and direction dimensions are not scored'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Rhythm-only practice, rhythm dimension not scored',
      ),
      findsOneWidget,
    );
  });

  testWidgets('A1 — direction-bearing definition shows the right body copy', (
    tester,
  ) async {
    await _pump(
      tester,
      RhythmOnlyView(
        target: _target(withDirection: true),
        playhead: const Duration(milliseconds: 500),
        width: 320,
        metrics: null,
      ),
    );

    expect(
      find.textContaining('chord dimension is not scored'),
      findsOneWidget,
    );
  });

  testWidgets('A1 — InsufficientData renders the localized copy', (
    tester,
  ) async {
    final metrics = _metrics(
      rhythm: const MetricInsufficientData(
        PracticeMetricReasonCode.insufficientSamples,
      ),
    );
    await _pump(
      tester,
      RhythmOnlyView(
        target: _target(withDirection: false),
        playhead: const Duration(milliseconds: 500),
        width: 320,
        metrics: metrics,
      ),
    );

    expect(find.text('Not enough data yet'), findsOneWidget);
  });

  testWidgets('A1 — Available renders the available copy', (tester) async {
    final metrics = _metrics(rhythm: const MetricAvailable(0.5));
    await _pump(
      tester,
      RhythmOnlyView(
        target: _target(withDirection: false),
        playhead: const Duration(milliseconds: 500),
        width: 320,
        metrics: metrics,
      ),
    );

    expect(find.text('Being measured'), findsOneWidget);
  });

  testWidgets('A1 — NotApplicable renders the not-applicable copy', (
    tester,
  ) async {
    final metrics = _metrics(rhythm: const MetricNotApplicable());
    await _pump(
      tester,
      RhythmOnlyView(
        target: _target(withDirection: false),
        playhead: const Duration(milliseconds: 500),
        width: 320,
        metrics: metrics,
      ),
    );

    expect(find.text('Not applicable for this practice'), findsOneWidget);
  });

  for (final size in [const Size(320, 568), const Size(915, 412)]) {
    testWidgets('A8 — fits without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _material(
          SingleChildScrollView(
            child: RhythmOnlyView(
              target: _target(withDirection: false),
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

CompiledPracticeTarget _target({required bool withDirection}) {
  final events = <CompiledTargetEvent>[];
  for (var i = 0; i < 4; i++) {
    final ticks = i * BeatPosition.ticksPerBeat;
    final at = Duration(milliseconds: (i * 500));
    events.add(
      CompiledTargetEvent(
        sourceEventId: 'r$i',
        loopIndex: 0,
        position: BeatPosition.fromTicks(ticks),
        time: at,
        barIndex: i,
        chord: null,
        direction: withDirection ? StrumDirection.down : null,
        accent: false,
        optional: false,
      ),
    );
  }
  return CompiledPracticeTarget(
    definitionId: 'rhythm-only-view',
    definitionSnapshotVersion: 1,
    tempo: const Tempo(60),
    meter: const Meter(beatsPerBar: 4),
    countInBars: 0,
    countInDuration: Duration.zero,
    events: events,
    musicalDuration: const Duration(seconds: 8),
    ringOutDuration: Duration.zero,
    totalDuration: const Duration(seconds: 8),
    barBoundaries: const [],
    loopCount: 1,
    loopRange: null,
    expectedChordSegments: const [],
    scoringApplicable: true,
  );
}

PracticeMetrics _metrics({required MetricValue rhythm}) => PracticeMetrics(
  completion: const MetricNotApplicable(),
  rhythm: rhythm,
  direction: const MetricNotApplicable(),
  chord: const MetricNotApplicable(),
  overall: const MetricNotApplicable(),
  totalTargets: 0,
  resolvedTargets: 0,
  maxCombo: 0,
  scorePoints: 0,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
);

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
