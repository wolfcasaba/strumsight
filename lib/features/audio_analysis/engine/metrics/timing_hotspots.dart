import '../../domain/analysis_hotspot.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/target/alignment_result.dart';

/// Builds timing hotspots from contiguous off-tolerance spans in an
/// [AlignmentResult] (SDD Ch7 §15, ADR 0232 §5). Every hotspot carries the
/// contributing observed event IDs in [AnalysisHotspot.evidenceIds] (never
/// an event-less hotspot) and the [ids] metric IDs it was built from.
List<AnalysisHotspot> buildTimingHotspots({
  required AlignmentResult alignment,
  required Duration tolerance,
  required TimingMetricSuiteIds ids,
  int minimumSpanMatches = 2,
}) {
  final hotspots = <AnalysisHotspot>[];
  var spanStart = -1;

  void closeSpan(int spanEndExclusive) {
    if (spanStart == -1) return;
    final spanMatches = alignment.matches.sublist(spanStart, spanEndExclusive);
    spanStart = -1;
    if (spanMatches.length < minimumSpanMatches) return;

    final absErrorsMs = <double>[
      for (final match in spanMatches)
        match.timingError.inMicroseconds.abs() / 1000.0,
    ];
    final meanAbsErrorMs =
        absErrorsMs.reduce((a, b) => a + b) / absErrorsMs.length;
    final toleranceMs = tolerance.inMicroseconds / 1000.0;
    final severity = meanAbsErrorMs >= toleranceMs * 2.5
        ? AnalysisHotspotSeverity.high
        : meanAbsErrorMs >= toleranceMs * 1.5
        ? AnalysisHotspotSeverity.medium
        : AnalysisHotspotSeverity.low;
    final confidence =
        spanMatches.map((m) => m.observed.confidence).reduce((a, b) => a + b) /
        spanMatches.length;

    hotspots.add(
      AnalysisHotspot(
        id: 'timing-hotspot-${spanMatches.first.observed.id}',
        kind: AnalysisHotspotKind.timing,
        start: spanMatches.first.observed.time,
        end: spanMatches.last.observed.time,
        severity: severity,
        confidence: confidence,
        metricIds: <String>[ids.onTimeRatio, ids.meanAbsoluteError],
        evidenceIds: <String>[for (final m in spanMatches) m.observed.id],
      ),
    );
  }

  for (var index = 0; index < alignment.matches.length; index++) {
    final offTime = alignment.matches[index].timingError.abs() > tolerance;
    if (offTime) {
      spanStart = spanStart == -1 ? index : spanStart;
    } else {
      closeSpan(index);
    }
  }
  closeSpan(alignment.matches.length);

  return hotspots;
}
