import 'dart:math' as math;

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_event.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/rhythm/beat_grid.dart';
import '../../domain/rhythm/beat_point.dart';
import 'metric_gate.dart';
import 'subdivision_analysis.dart';

/// Reference provenance of a rhythm metric publication (ADR 0233).
enum RhythmMetricMode { target, inferred }

/// The complete, one-mode-only rhythm proxy result. Swing is absent from
/// inferred output and its status explains that it is not applicable without
/// a known target rather than silently returning a made-up ratio.
final class RhythmMetricReport {
  RhythmMetricReport({
    required this.mode,
    required List<AnalysisMetricResult> metrics,
    required this.subdivision,
    required this.swingStatus,
  }) : metrics = List<AnalysisMetricResult>.unmodifiable(metrics);

  final RhythmMetricMode mode;
  final List<AnalysisMetricResult> metrics;
  final SubdivisionAnalysis subdivision;
  final CapabilityStatus swingStatus;
}

/// Builds rhythm consistency and groove-proxy metrics without assigning a
/// style label or an aggregate “groove score” (SDD Ch7 §15.6, ADR 0233).
RhythmMetricReport buildRhythmMetrics({
  required List<AnalysisEvent> events,
  required BeatGrid beatGrid,
  MetricGate? gate,
}) {
  _validateEvents(events);
  final mode = _modeFor(beatGrid);
  final ids = mode == RhythmMetricMode.target
      ? RhythmMetricSuiteIds.target
      : RhythmMetricSuiteIds.inferred;
  final rhythmGate = gate ?? MetricGate();
  final subdivision = const SubdivisionAnalyzer().analyze(
    events: events,
    beatGrid: beatGrid,
  );
  final confidence = _confidence(
    events: events,
    usedBeats: subdivision.usedBeats,
    mode: mode,
  );
  final mainAvailable = rhythmGate.isAvailable(events.length);
  final ioi = _iois(events);
  final medianIoi = _median(ioi);

  AnalysisMetricResult unavailable(String id, String unit) =>
      AnalysisMetricResult(
        id: id,
        version: 1,
        status: CapabilityStatus.unavailable,
        confidence: 0,
        unit: unit,
        sampleCount: events.length,
        evidence: const <String>[],
        unavailableReason: CapabilityUnavailableReason.insufficientEvents,
      );

  AnalysisMetricResult percentage(
    String id,
    double value, {
    CapabilityStatus? status,
  }) => AnalysisMetricResult(
    id: id,
    version: 1,
    status: status ?? CapabilityStatus.available,
    confidence: confidence,
    unit: 'ratio',
    sampleCount: events.length,
    evidence: <String>[for (final event in events) event.id],
    value: PercentageMetricValue(value.clamp(0.0, 1.0)),
  );

  AnalysisMetricResult scalar(String id, double value) => AnalysisMetricResult(
    id: id,
    version: 1,
    status: CapabilityStatus.available,
    confidence: confidence,
    unit: 'events',
    sampleCount: events.length,
    evidence: <String>[for (final event in events) event.id],
    value: ScalarMetricValue(value),
  );

  AnalysisMetricResult unboundedRatio(String id, double value) =>
      AnalysisMetricResult(
        id: id,
        version: 1,
        status: CapabilityStatus.available,
        confidence: confidence,
        unit: 'ratio',
        sampleCount: events.length,
        evidence: <String>[for (final event in events) event.id],
        value: ScalarMetricValue(value),
      );

  if (!mainAvailable) {
    return RhythmMetricReport(
      mode: mode,
      metrics: <AnalysisMetricResult>[
        unavailable(ids.ioiConsistency, 'ratio'),
        unavailable(ids.subdivisionConsistency, 'ratio'),
        unavailable(ids.beatPhaseConsistency, 'ratio'),
        unavailable(ids.longestStableIoiStreak, 'events'),
        unavailable(ids.accentPositionConsistency, 'ratio'),
        if (ids.swingRatio case final swingId?) unavailable(swingId, 'ratio'),
      ],
      subdivision: subdivision,
      swingStatus: mode == RhythmMetricMode.target
          ? CapabilityStatus.unavailable
          : CapabilityStatus.notApplicable,
    );
  }

  final ioiConsistency = _ioiConsistency(ioi, medianIoi);
  final phaseConsistency = (1 - subdivision.phaseDeviation * 2).clamp(0.0, 1.0);
  final metrics = <AnalysisMetricResult>[
    percentage(ids.ioiConsistency, ioiConsistency),
    percentage(
      ids.subdivisionConsistency,
      phaseConsistency,
      status: subdivision.status == CapabilityStatus.degraded
          ? CapabilityStatus.degraded
          : CapabilityStatus.available,
    ),
    percentage(
      ids.beatPhaseConsistency,
      phaseConsistency,
      status: subdivision.status == CapabilityStatus.degraded
          ? CapabilityStatus.degraded
          : CapabilityStatus.available,
    ),
    rhythmGate.isStreakAvailable(events.length)
        ? scalar(
            ids.longestStableIoiStreak,
            _longestStableIoiStreak(ioi, medianIoi).toDouble(),
          )
        : unavailable(ids.longestStableIoiStreak, 'events'),
    percentage(
      ids.accentPositionConsistency,
      _accentPositionConsistency(events, beatGrid),
    ),
  ];
  if (ids.swingRatio case final swingId?) {
    metrics.add(unboundedRatio(swingId, _swingRatio(ioi)));
  }
  return RhythmMetricReport(
    mode: mode,
    metrics: metrics,
    subdivision: subdivision,
    swingStatus: mode == RhythmMetricMode.target
        ? CapabilityStatus.available
        : CapabilityStatus.notApplicable,
  );
}

RhythmMetricMode _modeFor(BeatGrid beatGrid) {
  final sources = beatGrid.beats.map((beat) => beat.source).toSet();
  if (sources.length != 1) {
    throw ArgumentError(
      'BeatGrid must not mix target and estimated beat sources.',
    );
  }
  final source = sources.singleOrNull;
  if (source == BeatSource.target &&
      beatGrid.beatsPerBarSource == BeatsPerBarSource.target) {
    return RhythmMetricMode.target;
  }
  if (source == BeatSource.estimated &&
      beatGrid.beatsPerBarSource == BeatsPerBarSource.legacyDefault) {
    return RhythmMetricMode.inferred;
  }
  throw ArgumentError(
    'BeatGrid provenance does not identify a target or inferred mode.',
  );
}

void _validateEvents(List<AnalysisEvent> events) {
  Duration? previous;
  for (final event in events) {
    if (!event.confidence.isFinite) {
      throw ArgumentError.value(
        event.confidence,
        'events[${event.id}].confidence',
      );
    }
    if (previous != null && event.time <= previous) {
      throw ArgumentError('events must be strictly time ordered.');
    }
    previous = event.time;
  }
}

double _confidence({
  required List<AnalysisEvent> events,
  required List<BeatPoint> usedBeats,
  required RhythmMetricMode mode,
}) {
  final eventConfidence = _mean(<double>[
    for (final event in events) event.confidence,
  ]);
  if (mode == RhythmMetricMode.target) return eventConfidence;
  final beatConfidence = _mean(<double>[
    for (final beat in usedBeats) beat.confidence,
  ]);
  return (eventConfidence * beatConfidence).clamp(0.0, 1.0);
}

List<double> _iois(List<AnalysisEvent> events) => <double>[
  for (var index = 1; index < events.length; index++)
    (events[index].time - events[index - 1].time).inMicroseconds.toDouble(),
];

double _ioiConsistency(List<double> iois, double medianIoi) {
  if (iois.isEmpty || medianIoi <= 0) return 0;
  return (1 - _standardDeviation(iois) / medianIoi).clamp(0.0, 1.0);
}

int _longestStableIoiStreak(List<double> iois, double medianIoi) {
  if (medianIoi <= 0) return 0;
  var longest = 0;
  var current = 0;
  for (final interval in iois) {
    if ((interval - medianIoi).abs() <= medianIoi * 0.1) {
      current += 1;
      if (current > longest) longest = current;
    } else {
      current = 0;
    }
  }
  return longest;
}

double _accentPositionConsistency(
  List<AnalysisEvent> events,
  BeatGrid beatGrid,
) {
  final positions = <int>[];
  for (var beatIndex = 0; beatIndex + 1 < beatGrid.beats.length; beatIndex++) {
    final start = beatGrid.beats[beatIndex].time;
    final end = beatGrid.beats[beatIndex + 1].time;
    final candidates = events
        .where((event) => event.time >= start && event.time < end)
        .toList();
    if (candidates.isEmpty) continue;
    candidates.sort((left, right) => _accent(left).compareTo(_accent(right)));
    final strongest = candidates.last;
    positions.add(
      beatIndex % beatGrid.beatsPerBar * 4 +
          _phaseBin(strongest.time, start, end),
    );
  }
  if (positions.isEmpty) return 0;
  final counts = <int, int>{};
  for (final position in positions) {
    counts[position] = (counts[position] ?? 0) + 1;
  }
  final mostCommon = counts.values.reduce(
    (left, right) => left > right ? left : right,
  );
  return mostCommon / positions.length;
}

double _accent(AnalysisEvent event) => switch (event) {
  OnsetEvent(:final attackStrength?) => attackStrength,
  StrumEvent(:final attackStrength?) => attackStrength,
  _ => event.confidence,
};

int _phaseBin(Duration time, Duration start, Duration end) {
  final width = end.inMicroseconds - start.inMicroseconds;
  if (width <= 0) return 0;
  return (((time.inMicroseconds - start.inMicroseconds) / width) * 4)
      .floor()
      .clamp(0, 3);
}

double _swingRatio(List<double> iois) {
  if (iois.length < 2) return 0;
  final long = _median(<double>[
    for (var index = 0; index < iois.length; index += 2) iois[index],
  ]);
  final short = _median(<double>[
    for (var index = 1; index < iois.length; index += 2) iois[index],
  ]);
  if (long <= 0 || short <= 0) return 0;
  return long >= short ? long / short : short / long;
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

extension<T> on Iterable<T> {
  T? get singleOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    final value = iterator.current;
    return iterator.moveNext() ? null : value;
  }
}
