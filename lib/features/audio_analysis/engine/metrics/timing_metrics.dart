import '../../domain/analysis_capability.dart';
import '../../domain/analysis_event.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/rhythm/beat_grid.dart';
import '../../domain/rhythm/beat_point.dart';
import '../../domain/target/alignment_result.dart';
import '../alignment/tolerance_policy.dart';
import 'metric_gate.dart';

/// One matched observed-to-reference pairing feeding the shared timing
/// metric core. `signedError = observed.time - reference.time` (SDD Ch7
/// §15.2): negative is early, positive is late.
final class _MatchSample {
  const _MatchSample({required this.signedError, required this.evidenceId});

  final Duration signedError;
  final String evidenceId;
}

/// Builds the ten mandatory target timing metrics (SDD Ch7 §15.3) from an
/// [AlignmentResult]. `error = observed - expected`; on-time uses the same
/// inclusive [tolerance] the aligner matched with (OD-02) — never a
/// separate, stricter window.
List<AnalysisMetricResult> buildTargetTimingMetrics({
  required AlignmentResult alignment,
  required Duration tolerance,
  MetricGate gate = const MetricGate(),
}) {
  final samples = <_MatchSample>[
    for (final match in alignment.matches)
      _MatchSample(
        signedError: match.timingError,
        evidenceId: match.observed.id,
      ),
  ];
  return _buildSuite(
    samples: samples,
    expectedCount: alignment.matches.length + alignment.missedExpected.length,
    observedCount: alignment.matches.length + alignment.extraObserved.length,
    tolerance: tolerance,
    confidence: alignment.confidence,
    ids: TimingMetricSuiteIds.target,
    gate: gate,
  );
}

/// Builds the ten free-play timing metrics (SDD Ch7 §15.5, ADR 0232 §1) by
/// matching [observed] events to the nearest [beatGrid] beat inside a
/// tempo-derived [tolerancePolicy] window. Never reference-bound: publishes
/// under the disjoint `timing.freeplay_*` namespace, and its confidence is
/// always `<=` the matched beats' average confidence (SDD Ch7 §15.5).
List<AnalysisMetricResult> buildFreePlayTimingMetrics({
  required List<AnalysisEvent> observed,
  required BeatGrid beatGrid,
  TolerancePolicy tolerancePolicy = const TolerancePolicy(),
  MetricGate gate = const MetricGate(),
}) {
  final beats = beatGrid.beats;
  final tolerance = tolerancePolicy.forBeatDuration(
    _estimatedBeatDuration(beats),
  );

  final beatMatched = List<bool>.filled(beats.length, false);
  final samples = <_MatchSample>[];
  final matchedBeatConfidences = <double>[];
  final matchedObservedConfidences = <double>[];

  for (final event in observed) {
    var nearestIndex = -1;
    Duration? nearestDistance;
    for (var index = 0; index < beats.length; index++) {
      final distance = (event.time - beats[index].time).abs();
      if (nearestDistance == null || distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    if (nearestIndex == -1 ||
        nearestDistance == null ||
        nearestDistance > tolerance ||
        beatMatched[nearestIndex]) {
      continue;
    }
    beatMatched[nearestIndex] = true;
    samples.add(
      _MatchSample(
        signedError: event.time - beats[nearestIndex].time,
        evidenceId: event.id,
      ),
    );
    matchedBeatConfidences.add(beats[nearestIndex].confidence);
    matchedObservedConfidences.add(event.confidence);
  }

  final freeplayConfidence = matchedBeatConfidences.isEmpty
      ? 0.0
      : (_average(matchedBeatConfidences) *
                _average(matchedObservedConfidences))
            .clamp(0.0, 1.0);

  return _buildSuite(
    samples: samples,
    expectedCount: beats.length,
    observedCount: observed.length,
    tolerance: tolerance,
    confidence: freeplayConfidence,
    ids: TimingMetricSuiteIds.freeplay,
    gate: gate,
  );
}

Duration _estimatedBeatDuration(List<BeatPoint> beats) {
  if (beats.length < 2) return const Duration(milliseconds: 500);
  final totalMicroseconds =
      beats.last.time.inMicroseconds - beats.first.time.inMicroseconds;
  final gapCount = beats.length - 1;
  return Duration(microseconds: (totalMicroseconds / gapCount).round());
}

double _average(List<double> values) {
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a + b) / values.length;
}

List<AnalysisMetricResult> _buildSuite({
  required List<_MatchSample> samples,
  required int expectedCount,
  required int observedCount,
  required Duration tolerance,
  required double confidence,
  required TimingMetricSuiteIds ids,
  required MetricGate gate,
}) {
  final matchedCount = samples.length;
  final mainAvailable = gate.isAvailable(matchedCount);
  final streakAvailable = gate.isStreakAvailable(matchedCount);
  final evidenceIds = <String>[for (final sample in samples) sample.evidenceId];

  AnalysisMetricResult unavailable(String id, String unit) =>
      AnalysisMetricResult(
        id: id,
        version: 1,
        status: CapabilityStatus.unavailable,
        confidence: 0,
        unit: unit,
        sampleCount: matchedCount,
        evidence: const <String>[],
        unavailableReason: CapabilityUnavailableReason.insufficientEvents,
      );

  AnalysisMetricResult scalarMetric(String id, String unit, double value) =>
      AnalysisMetricResult(
        id: id,
        version: 1,
        status: CapabilityStatus.available,
        confidence: confidence,
        unit: unit,
        sampleCount: matchedCount,
        evidence: evidenceIds,
        value: ScalarMetricValue(value),
      );

  AnalysisMetricResult percentageMetric(String id, String unit, double value) =>
      AnalysisMetricResult(
        id: id,
        version: 1,
        status: CapabilityStatus.available,
        confidence: confidence,
        unit: unit,
        sampleCount: matchedCount,
        evidence: evidenceIds,
        value: PercentageMetricValue(value),
      );

  if (!mainAvailable) {
    final results = <AnalysisMetricResult>[
      unavailable(ids.meanAbsoluteError, 'ms'),
      unavailable(ids.medianAbsoluteError, 'ms'),
      unavailable(ids.p90AbsoluteError, 'ms'),
      unavailable(ids.signedBias, 'ms'),
      unavailable(ids.onTimeRatio, 'ratio'),
      unavailable(ids.earlyRatio, 'ratio'),
      unavailable(ids.lateRatio, 'ratio'),
      unavailable(ids.missedRatio, 'ratio'),
      unavailable(ids.extraRatio, 'ratio'),
    ];
    results.add(
      streakAvailable
          ? scalarMetric(
              ids.longestStableStreak,
              'events',
              _longestStableStreak(samples, tolerance).toDouble(),
            )
          : unavailable(ids.longestStableStreak, 'events'),
    );
    return results;
  }

  final absErrorsMs = <double>[
    for (final sample in samples)
      sample.signedError.inMicroseconds.abs() / 1000.0,
  ]..sort();
  final signedErrorsMs = <double>[
    for (final sample in samples) sample.signedError.inMicroseconds / 1000.0,
  ];

  final earlyCount = samples.where((s) => s.signedError.isNegative).length;
  final lateCount = samples.where((s) => s.signedError > Duration.zero).length;
  final onTimeCount = samples
      .where((s) => s.signedError.abs() <= tolerance)
      .length;
  final missedCount = expectedCount - matchedCount;
  final extraCount = observedCount - matchedCount;

  return <AnalysisMetricResult>[
    scalarMetric(ids.meanAbsoluteError, 'ms', _mean(absErrorsMs)),
    scalarMetric(ids.medianAbsoluteError, 'ms', _median(absErrorsMs)),
    scalarMetric(
      ids.p90AbsoluteError,
      'ms',
      _percentileLinear(absErrorsMs, 0.9),
    ),
    scalarMetric(ids.signedBias, 'ms', _mean(signedErrorsMs)),
    percentageMetric(ids.onTimeRatio, 'ratio', onTimeCount / matchedCount),
    percentageMetric(ids.earlyRatio, 'ratio', earlyCount / matchedCount),
    percentageMetric(ids.lateRatio, 'ratio', lateCount / matchedCount),
    percentageMetric(
      ids.missedRatio,
      'ratio',
      expectedCount == 0 ? 0 : missedCount / expectedCount,
    ),
    percentageMetric(
      ids.extraRatio,
      'ratio',
      observedCount == 0 ? 0 : extraCount / observedCount,
    ),
    streakAvailable
        ? scalarMetric(
            ids.longestStableStreak,
            'events',
            _longestStableStreak(samples, tolerance).toDouble(),
          )
        : unavailable(ids.longestStableStreak, 'events'),
  ];
}

double _mean(List<double> values) {
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a + b) / values.length;
}

/// Standard median: average of the two middle values on an even count.
double _median(List<double> sorted) {
  if (sorted.isEmpty) return 0;
  final n = sorted.length;
  if (n.isOdd) return sorted[n ~/ 2];
  return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// Linear-interpolation percentile over an ascending [sorted] list, matching
/// numpy's default `"linear"` method (OD-03): `index = q * (n - 1)`,
/// interpolating between the floor and ceil neighbours.
double _percentileLinear(List<double> sorted, double quantile) {
  if (sorted.isEmpty) return 0;
  if (sorted.length == 1) return sorted.first;
  final index = quantile * (sorted.length - 1);
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = index - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
}

/// Longest run of on-time (`|error| <= tolerance`) samples, in chronological
/// [samples] order. `0` is a legitimate published value (e.g. all off-time)
/// once the streak gate is satisfied — distinct from `unavailable`.
int _longestStableStreak(List<_MatchSample> samples, Duration tolerance) {
  var best = 0;
  var current = 0;
  for (final sample in samples) {
    if (sample.signedError.abs() <= tolerance) {
      current += 1;
      if (current > best) best = current;
    } else {
      current = 0;
    }
  }
  return best;
}
