import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  AnalysisHotspot hotspot(
    String id,
    AnalysisHotspotSeverity severity,
    double confidence,
  ) => AnalysisHotspot(
    id: id,
    kind: AnalysisHotspotKind.timing,
    start: Duration.zero,
    end: const Duration(milliseconds: 100),
    severity: severity,
    confidence: confidence,
    metricIds: const <String>[AnalysisMetricId.timingTargetMeanAbsoluteError],
    evidenceIds: const <String>['event-1'],
  );

  test('hotspots sort severity then confidence then stable ID', () {
    const ranker = HotspotRanker();
    final ordered = ranker.rank(<AnalysisHotspot>[
      hotspot('z', AnalysisHotspotSeverity.high, 0.8),
      hotspot('a', AnalysisHotspotSeverity.high, 0.8),
      hotspot('middle', AnalysisHotspotSeverity.high, 0.9),
      hotspot('low', AnalysisHotspotSeverity.low, 1),
    ]);
    expect(ordered.map((item) => item.id), <String>['middle', 'a', 'z', 'low']);
  });
}
