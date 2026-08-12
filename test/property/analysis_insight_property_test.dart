import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import '../fixtures/analysis/insights/insight_fixtures.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('generated insights are referentially closed for random documents', () {
    final registry = InsightRegistry(buildInitialInsightRules());
    for (var trial = 0; trial < 200; trial++) {
      final random = math.Random(seed + trial * 1543);
      final events = <AnalysisEvent>[
        for (var index = 0; index < 8; index++)
          OnsetEvent(
            id: 'event-$index',
            time: Duration(milliseconds: index * 100),
            confidence: random.nextDouble(),
          ),
      ];
      final document = buildInsightDocument(
        events: events,
        metrics: buildInsightMetrics(
          targetMean: random.nextDouble() * 80,
          targetMedian: random.nextDouble() * 40,
          targetP90: random.nextDouble() * 150,
          targetBias: random.nextDouble() * 100 - 50,
          downUpRatio: random.nextDouble() * 3,
          clippedRatio: random.nextDouble(),
        ),
      );
      final context = buildInsightContext(
        document: document,
        timingEvidence: TimingInsightEvidence(
          firstHalfMeanAbsoluteErrorMs: random.nextDouble() * 40,
          secondHalfMeanAbsoluteErrorMs: random.nextDouble() * 80,
          firstHalfMatchedEventIds: const <String>[
            'event-0',
            'event-1',
            'event-2',
            'event-3',
          ],
          secondHalfMatchedEventIds: const <String>[
            'event-4',
            'event-5',
            'event-6',
            'event-7',
          ],
        ),
        strokeBalance: StrokeBalanceInsightEvidence(
          targetDownUpMedianRatio: 1,
          upstrokeEventIds: <String>['event-1'],
        ),
        previousComparison: PreviousMetricComparison(
          metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
          previousValue: 40,
          currentValue: 20,
          minimumMeaningfulDelta: 10,
          higherIsBetter: false,
          evidenceIds: <String>['event-1'],
        ),
      );
      final metricIds = document.metrics.map((metric) => metric.id).toSet();
      final evidenceIds = <String>{
        ...document.timeline.events.map((event) => event.id),
        ...document.timeline.chordSegments.map((segment) => segment.id),
        ...document.hotspots.map((hotspot) => hotspot.id),
      };
      for (final insight in registry.evaluate(context)) {
        expect(insight.factIds, isNotEmpty, reason: 'seed=$seed trial=$trial');
        expect(
          insight.evidenceIds,
          isNotEmpty,
          reason: 'seed=$seed trial=$trial',
        );
        for (final id in insight.factIds) {
          expect(
            metricIds,
            contains(id),
            reason: 'seed=$seed trial=$trial $id',
          );
          expect(id.startsWith('technique.'), isFalse);
        }
        for (final id in insight.evidenceIds) {
          expect(
            evidenceIds,
            contains(id),
            reason: 'seed=$seed trial=$trial $id',
          );
        }
      }
    }
  });

  test('context rejects Lab-only technique metric IDs', () {
    final document = buildInsightDocument(
      metrics: <AnalysisMetricResult>[
        metric(AnalysisMetricId.techniqueChordChangeGap, 1),
      ],
    );
    expect(
      () => AnalysisInsightContext(document: document),
      throwsArgumentError,
    );
  });
}
