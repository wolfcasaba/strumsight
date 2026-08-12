import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

const _tolerance = Duration(milliseconds: 125);

void main() {
  group('buildTimingHotspots — referential integrity (ADR 0232 §5)', () {
    test('every hotspot evidence ID points to a real observed event', () {
      final matches = <AlignmentMatch>[
        for (var i = 0; i < 6; i++)
          AlignmentMatch(
            observedIndex: i,
            expectedIndex: i,
            observed: OnsetEvent(
              id: 'o$i',
              // Two consecutive off-tolerance events in the middle.
              time: Duration(
                milliseconds: 1000 * i + (i == 2 || i == 3 ? 400 : 0),
              ),
              confidence: 1,
            ),
            expected: ExpectedEvent(
              id: 'e$i',
              time: Duration(milliseconds: 1000 * i),
              type: ExpectedEventType.onset,
            ),
            timingError: Duration(milliseconds: i == 2 || i == 3 ? 400 : 0),
            cost: 0,
          ),
      ];
      final observedIds = matches.map((m) => m.observed.id).toSet();
      final alignment = AlignmentResult(
        matches: matches,
        missedExpected: const <ExpectedEvent>[],
        extraObserved: const <AnalysisEvent>[],
        totalCost: 0,
        confidence: 1,
        diagnostics: const AlignmentDiagnostics(
          algorithmVersion: 'test',
          observedCount: 6,
          expectedCount: 6,
          candidatePairCount: 6,
          maximumCandidateBandWidth: 1,
          scoreStateCount: 6,
        ),
      );

      final hotspots = buildTimingHotspots(
        alignment: alignment,
        tolerance: _tolerance,
        ids: TimingMetricSuiteIds.target,
      );

      expect(hotspots, isNotEmpty);
      for (final hotspot in hotspots) {
        expect(hotspot.evidenceIds, isNotEmpty);
        for (final id in hotspot.evidenceIds) {
          expect(observedIds, contains(id));
        }
        for (final metricId in hotspot.metricIds) {
          expect(AnalysisMetricId.contains(metricId), isTrue);
        }
        expect(hotspot.kind, AnalysisHotspotKind.timing);
      }
    });

    test('an all-on-time alignment produces no hotspots', () {
      final matches = <AlignmentMatch>[
        for (var i = 0; i < 6; i++)
          AlignmentMatch(
            observedIndex: i,
            expectedIndex: i,
            observed: OnsetEvent(
              id: 'o$i',
              time: Duration(milliseconds: 1000 * i),
              confidence: 1,
            ),
            expected: ExpectedEvent(
              id: 'e$i',
              time: Duration(milliseconds: 1000 * i),
              type: ExpectedEventType.onset,
            ),
            timingError: Duration.zero,
            cost: 0,
          ),
      ];
      final alignment = AlignmentResult(
        matches: matches,
        missedExpected: const <ExpectedEvent>[],
        extraObserved: const <AnalysisEvent>[],
        totalCost: 0,
        confidence: 1,
        diagnostics: const AlignmentDiagnostics(
          algorithmVersion: 'test',
          observedCount: 6,
          expectedCount: 6,
          candidatePairCount: 6,
          maximumCandidateBandWidth: 1,
          scoreStateCount: 6,
        ),
      );

      final hotspots = buildTimingHotspots(
        alignment: alignment,
        tolerance: _tolerance,
        ids: TimingMetricSuiteIds.target,
      );
      expect(hotspots, isEmpty);
    });

    test(
      'a single isolated off-tolerance event stays below the span minimum',
      () {
        final matches = <AlignmentMatch>[
          for (var i = 0; i < 6; i++)
            AlignmentMatch(
              observedIndex: i,
              expectedIndex: i,
              observed: OnsetEvent(
                id: 'o$i',
                time: Duration(milliseconds: 1000 * i + (i == 3 ? 400 : 0)),
                confidence: 1,
              ),
              expected: ExpectedEvent(
                id: 'e$i',
                time: Duration(milliseconds: 1000 * i),
                type: ExpectedEventType.onset,
              ),
              timingError: Duration(milliseconds: i == 3 ? 400 : 0),
              cost: 0,
            ),
        ];
        final alignment = AlignmentResult(
          matches: matches,
          missedExpected: const <ExpectedEvent>[],
          extraObserved: const <AnalysisEvent>[],
          totalCost: 0,
          confidence: 1,
          diagnostics: const AlignmentDiagnostics(
            algorithmVersion: 'test',
            observedCount: 6,
            expectedCount: 6,
            candidatePairCount: 6,
            maximumCandidateBandWidth: 1,
            scoreStateCount: 6,
          ),
        );

        final hotspots = buildTimingHotspots(
          alignment: alignment,
          tolerance: _tolerance,
          ids: TimingMetricSuiteIds.target,
        );
        expect(hotspots, isEmpty);
      },
    );
  });
}
