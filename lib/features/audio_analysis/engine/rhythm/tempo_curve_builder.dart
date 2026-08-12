import '../../domain/analysis_capability.dart';
import '../../domain/rhythm/tempo_curve_point.dart';
import 'tempo_hypothesis.dart';

/// Local, documented labels for the two R12 tempo outputs (ADR 0230 §3).
/// Neither is an `AnalysisMetricId` and neither is published through
/// `AnalysisMetricResult` or `AnalysisDocument`.
final class TempoMetricLabels {
  static const String legacyBpm = 'tempo.legacy_bpm.v1';
  static const String medianBpm = 'tempo.median_bpm.v1';
}

/// R12 tempo curve output: legacy-parity BPM, the R12 median BPM, and the
/// time-indexed curve with drift/stability statistics (SDD Ch7 §14.3).
final class TempoCurve {
  TempoCurve({
    required this.status,
    this.reason,
    required this.legacyBpm,
    this.medianBpm,
    List<TempoCurvePoint> points = const <TempoCurvePoint>[],
    this.iqrBpm,
    this.driftSlopeBpmPerMinute,
    this.stableRegionRatio,
    List<TempoHypothesis> hypotheses = const <TempoHypothesis>[],
  }) : points = List<TempoCurvePoint>.unmodifiable(points),
       hypotheses = List<TempoHypothesis>.unmodifiable(hypotheses) {
    if (status == CapabilityStatus.unavailable && reason == null) {
      throw ArgumentError('Unavailable tempo curve requires a reason.');
    }
    if (!legacyBpm.isFinite || legacyBpm < 0) {
      throw ArgumentError.value(legacyBpm, 'legacyBpm');
    }
    Duration? previous;
    for (final point in this.points) {
      if (previous != null && point.time <= previous) {
        throw ArgumentError('TempoCurve.points must be strictly increasing.');
      }
      previous = point.time;
    }
  }

  final CapabilityStatus status;
  final CapabilityUnavailableReason? reason;

  /// `tempo.legacy_bpm.v1` — byte-parity adapter of `_bpmFromStrums`.
  final double legacyBpm;

  /// `tempo.median_bpm.v1` — the R12-owned published tempo estimate.
  final double? medianBpm;
  final List<TempoCurvePoint> points;
  final double? iqrBpm;
  final double? driftSlopeBpmPerMinute;
  final double? stableRegionRatio;
  final List<TempoHypothesis> hypotheses;
}

/// Builds a [TempoCurve] from ordered rhythm-event times (SDD Ch7 §14.3).
final class TempoCurveBuilder {
  const TempoCurveBuilder();

  /// Minimum event count for `tempoCurve` availability (OD-01, ideiglenes).
  static const int minimumEventCount = 8;

  /// Minimum clip duration for `tempoCurve` availability (OD-01, ideiglenes).
  static const Duration minimumClipDuration = Duration(microseconds: 4000000);

  /// Stable-region tolerance around the median BPM (OD-03, ideiglenes).
  static const double stableRegionToleranceRatio = 0.05;

  static const double _minimumIntervalSeconds = 0.05;
  static const double _baseLocalConfidence = 0.8;

  TempoCurve build({
    required List<Duration> eventTimes,
    required Duration clipDuration,
  }) {
    if (clipDuration.isNegative) {
      throw ArgumentError.value(clipDuration, 'clipDuration');
    }
    _validateOrdered(eventTimes);

    final legacyBpm = _legacyBpmFromEvents(eventTimes);
    final hasEnoughEvents = eventTimes.length >= minimumEventCount;
    final hasEnoughDuration = clipDuration >= minimumClipDuration;

    final localBpms = <double>[];
    final points = <TempoCurvePoint>[];
    for (var i = 1; i < eventTimes.length; i++) {
      final dt = _secondsBetween(eventTimes[i - 1], eventTimes[i]);
      if (dt <= _minimumIntervalSeconds) continue;
      final bpm = (60 / dt).clamp(0.001, 400).toDouble();
      localBpms.add(bpm);
      points.add(
        TempoCurvePoint(
          time: eventTimes[i],
          bpm: bpm,
          confidence: _baseLocalConfidence,
        ),
      );
    }

    if (!hasEnoughEvents || !hasEnoughDuration || localBpms.isEmpty) {
      return TempoCurve(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.insufficientEvents,
        legacyBpm: legacyBpm,
      );
    }

    final sortedBpms = List<double>.of(localBpms)..sort();
    final medianBpmRaw = sortedBpms[sortedBpms.length ~/ 2];
    final iqr = _interquartileRange(sortedBpms);
    final hypothesisSet = TempoHypothesisSet.resolve(
      rawBpm: medianBpmRaw,
      rawConfidence: _baseLocalConfidence,
    );

    return TempoCurve(
      status: CapabilityStatus.available,
      legacyBpm: legacyBpm,
      medianBpm: hypothesisSet.published.bpm,
      points: points,
      iqrBpm: iqr,
      driftSlopeBpmPerMinute: _driftSlopeBpmPerMinute(points),
      stableRegionRatio: _stableRegionRatio(points, medianBpmRaw, clipDuration),
      hypotheses: hypothesisSet.hypotheses,
    );
  }

  /// Whether one local BPM point falls within `±[stableRegionToleranceRatio]`
  /// of [medianBpm] (both bounds inclusive, OD-03).
  static bool isStableLocalBpm({
    required double localBpm,
    required double medianBpm,
  }) {
    final lower = medianBpm * (1 - stableRegionToleranceRatio);
    final upper = medianBpm * (1 + stableRegionToleranceRatio);
    return localBpm >= lower && localBpm <= upper;
  }

  static double _legacyBpmFromEvents(List<Duration> eventTimes) {
    if (eventTimes.length < 2) return 0;
    final intervals = <double>[];
    for (var i = 1; i < eventTimes.length; i++) {
      final dt = _secondsBetween(eventTimes[i - 1], eventTimes[i]);
      if (dt > _minimumIntervalSeconds) intervals.add(dt);
    }
    if (intervals.isEmpty) return 0;
    intervals.sort();
    final median = intervals[intervals.length ~/ 2];
    return median > 0 ? (60 / median).clamp(30, 300).toDouble() : 0;
  }

  static double _secondsBetween(Duration a, Duration b) =>
      (b - a).inMicroseconds / 1e6;

  static double _interquartileRange(List<double> sortedValues) {
    if (sortedValues.length < 2) return 0;
    final q1 = sortedValues[(sortedValues.length * 0.25).floor()];
    final q3Index = (sortedValues.length * 0.75).floor().clamp(
      0,
      sortedValues.length - 1,
    );
    final q3 = sortedValues[q3Index];
    return q3 - q1;
  }

  static double? _driftSlopeBpmPerMinute(List<TempoCurvePoint> points) {
    if (points.length < 2) return null;
    final xs = <double>[
      for (final point in points) point.time.inMicroseconds / 60e6,
    ];
    final ys = <double>[for (final point in points) point.bpm];
    final n = xs.length;
    final meanX = xs.reduce((a, b) => a + b) / n;
    final meanY = ys.reduce((a, b) => a + b) / n;
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < n; i++) {
      numerator += (xs[i] - meanX) * (ys[i] - meanY);
      denominator += (xs[i] - meanX) * (xs[i] - meanX);
    }
    if (denominator == 0) return 0;
    return numerator / denominator;
  }

  static double? _stableRegionRatio(
    List<TempoCurvePoint> points,
    double medianBpm,
    Duration clipDuration,
  ) {
    if (points.isEmpty) return null;
    var stableWeight = 0.0;
    var totalWeight = 0.0;
    for (var i = 0; i < points.length; i++) {
      final start = points[i].time;
      final end = i + 1 < points.length ? points[i + 1].time : clipDuration;
      final weight = _secondsBetween(start, end);
      if (weight <= 0) continue;
      totalWeight += weight;
      if (isStableLocalBpm(localBpm: points[i].bpm, medianBpm: medianBpm)) {
        stableWeight += weight;
      }
    }
    if (totalWeight == 0) return null;
    return stableWeight / totalWeight;
  }

  static void _validateOrdered(List<Duration> eventTimes) {
    Duration? previous;
    for (final time in eventTimes) {
      if (time.isNegative) throw ArgumentError.value(time, 'eventTimes');
      if (previous != null && time < previous) {
        throw ArgumentError('eventTimes must be time-ordered.');
      }
      previous = time;
    }
  }
}
