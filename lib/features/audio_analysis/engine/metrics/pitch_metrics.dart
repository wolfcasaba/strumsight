import 'dart:math' as math;

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/pitch/monophonic_pitch_segment.dart';
import '../../domain/pitch/pitch_frame.dart';
import '../../domain/signal_quality_report.dart';
import '../pitch/monophonic_pitch_segment_builder.dart';
import '../pitch/pitch_capability_gate.dart';

/// A target note with its intended sounding range for pitch metrics.
final class PitchTargetNote {
  PitchTargetNote({
    required this.start,
    required this.end,
    required this.midiNote,
  }) {
    if (start.isNegative || end <= start) {
      throw ArgumentError('Pitch target note must have a positive range.');
    }
    if (midiNote < 0 || midiNote > 127) {
      throw ArgumentError.value(midiNote, 'midiNote');
    }
  }

  final Duration start;
  final Duration end;
  final int midiNote;
}

/// Immutable, explicitly monophonic target evidence for the seven metrics.
final class MonophonicPitchTarget {
  MonophonicPitchTarget(List<PitchTargetNote> notes)
    : notes = List<PitchTargetNote>.unmodifiable(notes) {
    if (this.notes.isEmpty) throw ArgumentError.value(notes, 'notes');
    for (var index = 1; index < this.notes.length; index += 1) {
      if (this.notes[index].start < this.notes[index - 1].end) {
        throw ArgumentError(
          'Pitch target notes must be ordered and non-overlapping.',
        );
      }
    }
  }

  final List<PitchTargetNote> notes;
}

/// Publication for the target-bound monophonic pitch metrics.
final class PitchMetricReport {
  PitchMetricReport({
    required this.capability,
    required List<AnalysisMetricResult> metrics,
  }) : metrics = List<AnalysisMetricResult>.unmodifiable(metrics);

  final CapabilityReport capability;
  final List<AnalysisMetricResult> metrics;
}

/// The seven mandatory, target-bound pitch metric identifiers (E06-R17).
abstract final class PitchMetricIds {
  static const String noteHitRatio = AnalysisMetricId.pitchNoteHitRatio;
  static const String medianCentsError = AnalysisMetricId.pitchMedianCentsError;
  static const String p90CentsError = AnalysisMetricId.pitchP90CentsError;
  static const String stabilityCents = AnalysisMetricId.pitchStabilityCents;
  static const String noteTransitionTiming =
      AnalysisMetricId.pitchNoteTransitionTiming;
  static const String sustainedNoteDuration =
      AnalysisMetricId.pitchSustainedNoteDuration;
  static const String unwantedPitchDropoutRatio =
      AnalysisMetricId.pitchUnwantedDropoutRatio;

  static const Set<String> all = <String>{
    noteHitRatio,
    medianCentsError,
    p90CentsError,
    stabilityCents,
    noteTransitionTiming,
    sustainedNoteDuration,
    unwantedPitchDropoutRatio,
  };
}

/// Inclusive threshold for an in-tune target hit (brief §6).
const double pitchIntonationToleranceCents = 10;

/// Floating-point slack only for the exactly-on-threshold representation.
const double _pitchThresholdPrecision = 1e-9;

/// Runs the capability check before any metric calculator invocation.
PitchMetricReport buildGatedPitchMetrics({
  required bool analysisPitchEnabled,
  required MonophonicPitchTarget? target,
  required List<PitchFrame> frames,
  required List<MonophonicPitchSegment> segments,
  SignalQualityReport? signalQuality,
  PitchCapabilityGate? gate,
}) {
  final capabilityGate = gate ?? PitchCapabilityGate();
  final evaluation = capabilityGate.evaluate<List<AnalysisMetricResult>>(
    analysisPitchEnabled: analysisPitchEnabled,
    hasMonophonicTarget: target != null,
    frames: frames,
    signalQuality: signalQuality,
    onAvailable: () => buildPitchMetrics(
      target: target!,
      segments: segments,
      confidence: _mean(<double>[for (final frame in frames) frame.confidence]),
    ),
  );
  return PitchMetricReport(
    capability: evaluation.report,
    metrics:
        evaluation.value ??
        _unavailableMetrics(
          status: evaluation.report.status,
          reason: evaluation.report.reason,
        ),
  );
}

/// Computes the seven required metrics from gated, monophonic evidence.
///
/// `medianCentsError` is signed against the intended note: positive is sharp,
/// negative is flat. The p90 error is absolute. Neither metric diagnoses an
/// instrument setup or tuning fault (SDD §17.4).
List<AnalysisMetricResult> buildPitchMetrics({
  required MonophonicPitchTarget target,
  required List<MonophonicPitchSegment> segments,
  required double confidence,
}) {
  if (!confidence.isFinite || confidence < 0 || confidence > 1) {
    throw ArgumentError.value(confidence, 'confidence');
  }
  if (segments.isEmpty) {
    return _unavailableMetrics(
      status: CapabilityStatus.unavailable,
      reason: CapabilityUnavailableReason.insufficientEvents,
    );
  }
  final matched = <({MonophonicPitchSegment segment, PitchTargetNote target})>[
    for (final segment in segments)
      (segment: segment, target: _targetFor(segment.start, target.notes)),
  ];
  final errors = <double>[
    for (final pair in matched)
      centsBetween(
        _frequencyForMidi(pair.target.midiNote),
        pair.segment.medianHz,
      ),
  ];
  final absoluteErrors = <double>[for (final error in errors) error.abs()]
    ..sort();
  final evidence = <String>[
    for (var index = 0; index < matched.length; index += 1) 'pitch-$index',
  ];
  final averageStability = _median(<double>[
    for (final segment in segments) segment.stabilityCents,
  ]);
  final transitionMicros = <double>[
    for (final pair in matched)
      (pair.segment.start - pair.target.start).inMicroseconds.abs().toDouble(),
  ];
  final durationMicros = <double>[
    for (final segment in segments) segment.duration.inMicroseconds.toDouble(),
  ];
  final noteHits =
      errors
          .where(
            (error) =>
                error.abs() <=
                pitchIntonationToleranceCents + _pitchThresholdPrecision,
          )
          .length /
      errors.length;

  AnalysisMetricResult scalar(String id, double value, String unit) =>
      AnalysisMetricResult(
        id: id,
        version: 1,
        status: CapabilityStatus.available,
        confidence: confidence,
        unit: unit,
        sampleCount: segments.length,
        evidence: evidence,
        value: ScalarMetricValue(value),
      );
  AnalysisMetricResult duration(String id, double micros) =>
      AnalysisMetricResult(
        id: id,
        version: 1,
        status: CapabilityStatus.available,
        confidence: confidence,
        unit: 'ms',
        sampleCount: segments.length,
        evidence: evidence,
        value: DurationMetricValue(Duration(microseconds: micros.round())),
      );
  AnalysisMetricResult percentage(String id, double value) =>
      AnalysisMetricResult(
        id: id,
        version: 1,
        status: CapabilityStatus.available,
        confidence: confidence,
        unit: 'ratio',
        sampleCount: segments.length,
        evidence: evidence,
        value: PercentageMetricValue(value.clamp(0.0, 1.0)),
      );

  return List<AnalysisMetricResult>.unmodifiable(<AnalysisMetricResult>[
    percentage(PitchMetricIds.noteHitRatio, noteHits),
    scalar(PitchMetricIds.medianCentsError, _median(errors), 'cents'),
    scalar(
      PitchMetricIds.p90CentsError,
      _percentile(absoluteErrors, 0.9),
      'cents',
    ),
    scalar(PitchMetricIds.stabilityCents, averageStability, 'cents'),
    duration(PitchMetricIds.noteTransitionTiming, _median(transitionMicros)),
    duration(PitchMetricIds.sustainedNoteDuration, _median(durationMicros)),
    percentage(
      PitchMetricIds.unwantedPitchDropoutRatio,
      _dropoutRatio(target, segments),
    ),
  ]);
}

List<AnalysisMetricResult> _unavailableMetrics({
  required CapabilityStatus status,
  CapabilityUnavailableReason? reason,
}) => List<AnalysisMetricResult>.unmodifiable(<AnalysisMetricResult>[
  for (final id in PitchMetricIds.all)
    AnalysisMetricResult(
      id: id,
      version: 1,
      status: status,
      confidence: 0,
      unit: _unitFor(id),
      sampleCount: 0,
      evidence: const <String>[],
      unavailableReason: reason,
    ),
]);

String _unitFor(String id) => switch (id) {
  PitchMetricIds.noteHitRatio ||
  PitchMetricIds.unwantedPitchDropoutRatio => 'ratio',
  PitchMetricIds.noteTransitionTiming ||
  PitchMetricIds.sustainedNoteDuration => 'ms',
  _ => 'cents',
};

PitchTargetNote _targetFor(Duration time, List<PitchTargetNote> targets) =>
    targets.reduce(
      (nearest, candidate) =>
          _distance(time, candidate.start) < _distance(time, nearest.start)
          ? candidate
          : nearest,
    );

int _distance(Duration left, Duration right) =>
    (left - right).inMicroseconds.abs();

double _frequencyForMidi(int midi) =>
    440 * math.pow(2, (midi - 69) / 12).toDouble();

double _dropoutRatio(
  MonophonicPitchTarget target,
  List<MonophonicPitchSegment> segments,
) {
  var expectedMicros = 0;
  var coveredMicros = 0;
  for (final note in target.notes) {
    expectedMicros += (note.end - note.start).inMicroseconds;
    for (final segment in segments) {
      final start = segment.start > note.start ? segment.start : note.start;
      final end = segment.end < note.end ? segment.end : note.end;
      if (end > start) coveredMicros += (end - start).inMicroseconds;
    }
  }
  if (expectedMicros == 0) return 1;
  return (1 - coveredMicros / expectedMicros).clamp(0.0, 1.0);
}

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double _percentile(List<double> sorted, double percentile) {
  final index = ((sorted.length - 1) * percentile).ceil();
  return sorted[index];
}

double _mean(List<double> values) => values.isEmpty
    ? 0
    : values.reduce((left, right) => left + right) / values.length;
