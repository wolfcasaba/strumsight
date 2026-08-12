import 'dart:math' as math;

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_event.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/preprocessed_audio.dart';
import '../../domain/signal_quality_report.dart';
import 'accent_analysis.dart';
import 'dynamics_gate.dart';
import 'metric_gate.dart';

/// The complete dynamics and stroke-balance publication for one session
/// (E06-R16, ADR 0234). [gateStatus]/[gateReason] record the quality-gate
/// verdict that governed every metric in [metrics].
final class DynamicsMetricReport {
  DynamicsMetricReport({
    required this.gateStatus,
    this.gateReason,
    required List<AnalysisMetricResult> metrics,
  }) : metrics = List<AnalysisMetricResult>.unmodifiable(metrics);

  final CapabilityStatus gateStatus;
  final CapabilityUnavailableReason? gateReason;
  final List<AnalysisMetricResult> metrics;
}

/// A named constant, not a magic number: the outlier band half-width in
/// median-absolute-deviations (brief §5.1 OD-01). The band is inclusive —
/// exactly `2 * MAD` from the median is not an outlier.
const double dynamicsOutlierMadMultiplier = 2.0;

/// A named constant (brief §5.1 OD-02, [detectLocalAccents]'s default): an
/// event is an accent when its attack strength exceeds its local-window
/// median by more than this ratio.
const double dynamicsAccentThresholdRatio = 1.2;

/// A named constant: an event's local RMS below this fraction of the
/// session's non-clipped median local RMS makes it part of a quiet region.
const double dynamicsQuietRmsFraction = 0.3;

/// Builds the seven mandatory dynamics metrics from the session's original,
/// unnormalized PCM (ADR 0206/0234 — never `canonicalSamples`).
///
/// [events] must be strictly time ordered and every retained event must
/// carry `sampleIndex` and `attackStrength` (guaranteed by R10 for events
/// that reach this stage) — a missing one is a contract violation, not a
/// runtime `unavailable` state. [expectedAccentEventIds] is the optional
/// evaluative target (brief §5.2): without it, `dynamics.accent_accuracy.v1`
/// is `notApplicable`, never a fabricated number.
DynamicsMetricReport buildDynamicsMetrics({
  required PreprocessedAudio audio,
  required List<StrumEvent> events,
  required SignalQualityReport signalQuality,
  MetricGate? gate,
  DynamicsGate? qualityGate,
  Set<String>? expectedAccentEventIds,
}) {
  _validateEvents(events, audio);
  final metricGate = gate ?? MetricGate();
  final dynamicsGate = qualityGate ?? DynamicsGate();

  final clippedById = <String, bool>{
    for (final event in events) event.id: _isClipped(event, audio),
  };
  final clippedEventRatio = events.isEmpty
      ? 0.0
      : clippedById.values.where((clipped) => clipped).length / events.length;

  final gateResult = dynamicsGate.evaluate(
    report: signalQuality,
    clippedEventRatio: clippedEventRatio,
  );

  final nonClipped = <StrumEvent>[
    for (final event in events)
      if (!clippedById[event.id]!) event,
  ];
  final confidence = _mean(<double>[
    for (final event in events) event.confidence,
  ]);

  AnalysisMetricResult unavailable(
    String id, {
    CapabilityUnavailableReason reason =
        CapabilityUnavailableReason.insufficientEvents,
    int sampleCount = 0,
  }) => AnalysisMetricResult(
    id: id,
    version: 1,
    status: CapabilityStatus.unavailable,
    confidence: 0,
    unit: 'ratio',
    sampleCount: sampleCount,
    evidence: const <String>[],
    unavailableReason: reason,
  );

  if (gateResult.status == CapabilityStatus.unavailable) {
    return DynamicsMetricReport(
      gateStatus: gateResult.status,
      gateReason: gateResult.reason,
      metrics: <AnalysisMetricResult>[
        for (final id in DynamicsMetricIds.all)
          unavailable(
            id,
            reason: gateResult.reason!,
            sampleCount: events.length,
          ),
      ],
    );
  }

  final status = gateResult.status;

  if (!metricGate.isAvailable(events.length)) {
    return DynamicsMetricReport(
      gateStatus: status,
      metrics: <AnalysisMetricResult>[
        for (final id in DynamicsMetricIds.all)
          unavailable(id, sampleCount: events.length),
      ],
    );
  }

  final clippedRatioResult = AnalysisMetricResult(
    id: DynamicsMetricIds.clippedEventRatio,
    version: 1,
    status: status,
    confidence: confidence,
    unit: 'ratio',
    sampleCount: events.length,
    evidence: <String>[for (final event in events) event.id],
    value: PercentageMetricValue(clippedEventRatio.clamp(0.0, 1.0)),
  );

  if (!metricGate.isAvailable(nonClipped.length)) {
    return DynamicsMetricReport(
      gateStatus: status,
      metrics: <AnalysisMetricResult>[
        for (final id in DynamicsMetricIds.all)
          if (id == DynamicsMetricIds.clippedEventRatio)
            clippedRatioResult
          else
            unavailable(id, sampleCount: nonClipped.length),
      ],
    );
  }

  final strengths = <double>[
    for (final event in nonClipped) event.attackStrength!,
  ];
  final medianStrength = _median(strengths);
  if (medianStrength <= 0) {
    return DynamicsMetricReport(
      gateStatus: status,
      metrics: <AnalysisMetricResult>[
        for (final id in DynamicsMetricIds.all)
          if (id == DynamicsMetricIds.clippedEventRatio)
            clippedRatioResult
          else
            unavailable(
              id,
              reason: CapabilityUnavailableReason.internalFailure,
              sampleCount: nonClipped.length,
            ),
      ],
    );
  }

  final normalizedById = <String, double>{
    for (final event in nonClipped)
      event.id: event.attackStrength! / medianStrength,
  };
  final normalizedStrengths = <double>[
    for (final event in nonClipped) normalizedById[event.id]!,
  ];
  final nonClippedIds = <String>[for (final event in nonClipped) event.id];
  final nonClippedConfidence = _mean(<double>[
    for (final event in nonClipped) event.confidence,
  ]);

  AnalysisMetricResult percentage(String id, double value) =>
      AnalysisMetricResult(
        id: id,
        version: 1,
        status: status,
        confidence: nonClippedConfidence,
        unit: 'ratio',
        sampleCount: nonClipped.length,
        evidence: nonClippedIds,
        value: PercentageMetricValue(value.clamp(0.0, 1.0)),
      );

  AnalysisMetricResult scalar(String id, double value) => AnalysisMetricResult(
    id: id,
    version: 1,
    status: status,
    confidence: nonClippedConfidence,
    unit: 'ratio',
    sampleCount: nonClipped.length,
    evidence: nonClippedIds,
    value: ScalarMetricValue(value),
  );

  final strokeStrengthCv = scalar(
    DynamicsMetricIds.strokeStrengthCv,
    _coefficientOfVariation(normalizedStrengths),
  );

  final downMedian = _median(<double>[
    for (final event in nonClipped)
      if (event.direction == StrumDirection.down) normalizedById[event.id]!,
  ]);
  final upMedian = _median(<double>[
    for (final event in nonClipped)
      if (event.direction == StrumDirection.up) normalizedById[event.id]!,
  ]);
  final downCount = nonClipped
      .where((event) => event.direction == StrumDirection.down)
      .length;
  final upCount = nonClipped
      .where((event) => event.direction == StrumDirection.up)
      .length;
  final downUpRatio = (downCount == 0 || upCount == 0 || upMedian <= 0)
      ? unavailable(
          DynamicsMetricIds.downUpMedianRatio,
          sampleCount: nonClipped.length,
        )
      : scalar(DynamicsMetricIds.downUpMedianRatio, downMedian / upMedian);

  final drift = nonClipped.length < 2
      ? unavailable(DynamicsMetricIds.drift, sampleCount: nonClipped.length)
      : scalar(DynamicsMetricIds.drift, _drift(normalizedStrengths));

  final outlierRatio = percentage(
    DynamicsMetricIds.outlierRatio,
    _outlierRatio(normalizedStrengths),
  );

  // A missing `localRms` must never silently read as "silent" — that would
  // fabricate quiet-region evidence for events that never measured a local
  // RMS (security review R16 MAJOR-4).
  final missingLocalRms = nonClipped.any((event) => event.localRms == null);
  final quietRegionRatio = missingLocalRms
      ? unavailable(
          DynamicsMetricIds.quietRegionRatio,
          reason: CapabilityUnavailableReason.internalFailure,
          sampleCount: nonClipped.length,
        )
      : percentage(
          DynamicsMetricIds.quietRegionRatio,
          _quietRegionRatio(nonClipped),
        );

  final accentAccuracy = _accentAccuracy(
    nonClipped: nonClipped,
    status: status,
    confidence: nonClippedConfidence,
    expectedAccentEventIds: expectedAccentEventIds,
  );

  return DynamicsMetricReport(
    gateStatus: status,
    metrics: <AnalysisMetricResult>[
      strokeStrengthCv,
      downUpRatio,
      drift,
      outlierRatio,
      accentAccuracy,
      quietRegionRatio,
      clippedRatioResult,
    ],
  );
}

void _validateEvents(List<StrumEvent> events, PreprocessedAudio audio) {
  Duration? previous;
  final seenIds = <String>{};
  for (final event in events) {
    if (previous != null && event.time <= previous) {
      throw ArgumentError('events must be strictly time ordered.');
    }
    previous = event.time;
    // A duplicate id lets a later, non-clipped event overwrite an earlier
    // clipped one in `clippedById` — that can hide real clipping behind an
    // `available` 0.0 ratio (security review R16 MAJOR-3).
    if (!seenIds.add(event.id)) {
      throw ArgumentError('Duplicate StrumEvent id ${event.id}.');
    }
    // `AnalysisEvent`'s own `[0, 1]` range check does not catch `NaN` (its
    // comparisons are all false for `NaN`), so a non-finite confidence could
    // otherwise reach `_mean` and publish as a fabricated metric confidence
    // (security review R16 MAJOR-1).
    if (!event.confidence.isFinite) {
      throw ArgumentError.value(
        event.confidence,
        'StrumEvent ${event.id}.confidence',
        'must be finite',
      );
    }
    if (event.sampleIndex == null) {
      throw ArgumentError('StrumEvent ${event.id} is missing sampleIndex.');
    }
    if (event.attackStrength == null) {
      throw ArgumentError('StrumEvent ${event.id} is missing attackStrength.');
    }
    final sampleIndex = event.sampleIndex!;
    if (sampleIndex >= audio.originalSamples.length) {
      throw ArgumentError.value(
        sampleIndex,
        'StrumEvent ${event.id}.sampleIndex',
        'must be within the audio bounds',
      );
    }
    // R10 guarantees `sampleIndex` and `time` are derived from the same
    // instant; a mismatch here would let a fabricated/mistranscribed index
    // drive an unrelated clipping scan (security review R16 MAJOR-5).
    final expectedSampleIndex = audio.durationToSampleIndex(event.time);
    if (sampleIndex != expectedSampleIndex) {
      throw ArgumentError(
        'StrumEvent ${event.id} sampleIndex $sampleIndex is incoherent with '
        'time ${event.time} (expected $expectedSampleIndex).',
      );
    }
  }
}

const Duration _attackWindow = Duration(milliseconds: 20);
const double _clippedSampleThreshold = 0.999;

bool _isClipped(StrumEvent event, PreprocessedAudio audio) {
  final samples = audio.originalSamples;
  if (samples.isEmpty) return false;
  final start = event.sampleIndex!;
  if (start >= samples.length) return false;
  final windowSamples =
      _attackWindow.inMicroseconds *
      audio.sampleRate ~/
      Duration.microsecondsPerSecond;
  final end = math.min(start + windowSamples, samples.length - 1);
  for (var index = start; index <= end; index++) {
    final sample = samples[index];
    if (sample.isFinite && sample.abs() >= _clippedSampleThreshold) {
      return true;
    }
  }
  return false;
}

AnalysisMetricResult _accentAccuracy({
  required List<StrumEvent> nonClipped,
  required CapabilityStatus status,
  required double confidence,
  required Set<String>? expectedAccentEventIds,
}) {
  if (expectedAccentEventIds == null) {
    return AnalysisMetricResult(
      id: DynamicsMetricIds.accentAccuracy,
      version: 1,
      status: CapabilityStatus.notApplicable,
      confidence: 0,
      unit: 'ratio',
      sampleCount: nonClipped.length,
      evidence: const <String>[],
    );
  }
  final detected = detectLocalAccents(events: nonClipped).accentEventIds;
  var correct = 0;
  for (final event in nonClipped) {
    final isDetected = detected.contains(event.id);
    final isExpected = expectedAccentEventIds.contains(event.id);
    if (isDetected == isExpected) correct += 1;
  }
  final accuracy = nonClipped.isEmpty ? 0.0 : correct / nonClipped.length;
  return AnalysisMetricResult(
    id: DynamicsMetricIds.accentAccuracy,
    version: 1,
    status: status,
    confidence: confidence,
    unit: 'ratio',
    sampleCount: nonClipped.length,
    evidence: <String>[for (final event in nonClipped) event.id],
    value: PercentageMetricValue(accuracy.clamp(0.0, 1.0)),
  );
}

double _coefficientOfVariation(List<double> values) {
  final mean = _mean(values);
  if (mean <= 0) return 0;
  return _standardDeviation(values) / mean;
}

double _drift(List<double> normalizedStrengths) {
  final half = normalizedStrengths.length ~/ 2;
  final firstHalf = normalizedStrengths.sublist(0, half);
  final secondHalf = normalizedStrengths.sublist(
    normalizedStrengths.length - half,
  );
  return _mean(secondHalf) - _mean(firstHalf);
}

double _outlierRatio(List<double> normalizedStrengths) {
  if (normalizedStrengths.isEmpty) return 0;
  final median = _median(normalizedStrengths);
  final deviations = <double>[
    for (final value in normalizedStrengths) (value - median).abs(),
  ];
  final mad = _median(deviations);
  final band = dynamicsOutlierMadMultiplier * mad;
  final outliers = deviations.where((deviation) => deviation > band).length;
  return outliers / normalizedStrengths.length;
}

double _quietRegionRatio(List<StrumEvent> nonClipped) {
  if (nonClipped.isEmpty) return 0;
  final rms = <double>[for (final event in nonClipped) event.localRms!];
  final medianRms = _median(rms);
  if (medianRms <= 0) return 0;
  final threshold = medianRms * dynamicsQuietRmsFraction;
  final quiet = rms.where((value) => value < threshold).length;
  return quiet / nonClipped.length;
}

double _mean(List<double> values) => values.isEmpty
    ? 0
    : values.reduce((left, right) => left + right) / values.length;

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double _standardDeviation(List<double> values) {
  if (values.isEmpty) return 0;
  final mean = _mean(values);
  final variance = _mean(<double>[
    for (final value in values) (value - mean) * (value - mean),
  ]);
  return math.sqrt(variance);
}
