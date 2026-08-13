/// Deterministic evaluation report types (E06-R29, ADR 0249).
///
/// `toJson()`/`toDeterministicJson()` never read the clock or iterate a
/// `Set`/`Map` whose order depends on hash codes — every field is a plain
/// value or a `List` built in a fixed, code-defined order, so the same
/// `EvaluationReport` always serialises to the same bytes.
library;

import 'dart:convert';

/// A precision/recall/F1 triple. `precision` is `null` when there were no
/// detections to compute a precision over (never coerced to `0`); `recall`
/// is `null` only when there was nothing expected either.
final class PrecisionRecallF1 {
  const PrecisionRecallF1({
    required this.precision,
    required this.recall,
    required this.f1,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
  });

  final double? precision;
  final double? recall;
  final double? f1;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;

  Map<String, Object?> toJson() => <String, Object?>{
    'precision': precision,
    'recall': recall,
    'f1': f1,
    'truePositives': truePositives,
    'falsePositives': falsePositives,
    'falseNegatives': falseNegatives,
  };
}

/// One reliability-diagram bin as reported to callers (see
/// `CalibrationFitter` for the fitting logic that produces these).
final class CalibrationBinReport {
  const CalibrationBinReport({
    required this.lowerBound,
    required this.upperBound,
    required this.observationCount,
    required this.meanConfidence,
    required this.empiricalAccuracy,
  });

  final double lowerBound;
  final double upperBound;
  final int observationCount;
  final double? meanConfidence;
  final double? empiricalAccuracy;

  Map<String, Object?> toJson() => <String, Object?>{
    'lowerBound': lowerBound,
    'upperBound': upperBound,
    'observationCount': observationCount,
    'meanConfidence': meanConfidence,
    'empiricalAccuracy': empiricalAccuracy,
  };
}

/// Confidence-calibration metrics. `insufficientData` is `true` (and
/// [tableVersion] is `identity.v1`) whenever the data does not clear ADR
/// 0249's 30-per-bin / 300-total minimum — the report says so explicitly
/// rather than silently shipping a curve fitted from too few points.
final class ConfidenceCalibrationMetrics {
  const ConfidenceCalibrationMetrics({
    required this.expectedCalibrationError,
    required this.insufficientData,
    required this.observationCount,
    required this.tableVersion,
    required this.bins,
  });

  final double? expectedCalibrationError;
  final bool insufficientData;
  final int observationCount;
  final String tableVersion;
  final List<CalibrationBinReport> bins;

  Map<String, Object?> toJson() => <String, Object?>{
    'expectedCalibrationError': expectedCalibrationError,
    'insufficientData': insufficientData,
    'observationCount': observationCount,
    'tableVersion': tableVersion,
    'bins': <Map<String, Object?>>[for (final bin in bins) bin.toJson()],
  };
}

/// The nine SDD metrics computed over one case (or one slice, or the
/// manifest overall).
final class EvaluationMetrics {
  const EvaluationMetrics({
    required this.caseCount,
    required this.onset,
    required this.timestampMaeMs,
    required this.chordFrameAccuracy,
    required this.chordSegmentAccuracy,
    required this.strumDirectionAccuracy,
    required this.bpmErrorPercent,
    required this.beatAlignmentAccuracy,
    required this.pitchCentsErrorMean,
    required this.confidenceCalibration,
  });

  final int caseCount;
  final PrecisionRecallF1 onset;
  final double? timestampMaeMs;
  final double? chordFrameAccuracy;
  final double? chordSegmentAccuracy;
  final double? strumDirectionAccuracy;
  final double? bpmErrorPercent;
  final double? beatAlignmentAccuracy;
  final double? pitchCentsErrorMean;
  final ConfidenceCalibrationMetrics confidenceCalibration;

  Map<String, Object?> toJson() => <String, Object?>{
    'caseCount': caseCount,
    'onset': onset.toJson(),
    'timestampMaeMs': timestampMaeMs,
    'chordFrameAccuracy': chordFrameAccuracy,
    'chordSegmentAccuracy': chordSegmentAccuracy,
    'strumDirectionAccuracy': strumDirectionAccuracy,
    'bpmErrorPercent': bpmErrorPercent,
    'beatAlignmentAccuracy': beatAlignmentAccuracy,
    'pitchCentsErrorMean': pitchCentsErrorMean,
    'confidenceCalibration': confidenceCalibration.toJson(),
  };
}

/// One named breakdown slice (e.g. `tempoBand:medium`) and its metrics.
final class MetricSlice {
  const MetricSlice({required this.key, required this.metrics});

  final String key;
  final EvaluationMetrics metrics;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'metrics': metrics.toJson(),
  };
}

/// The complete evaluation output for one manifest run: the manifest-wide
/// `overall` metrics plus at least a tempo-band, signal-quality-tier, and
/// mode slice breakdown (SDD §29.6-29.8).
final class EvaluationReport {
  EvaluationReport({
    required this.manifestSchemaVersion,
    required this.caseCount,
    required this.overall,
    required List<MetricSlice> slices,
  }) : slices = List<MetricSlice>.unmodifiable(slices);

  final String manifestSchemaVersion;
  final int caseCount;
  final EvaluationMetrics overall;
  final List<MetricSlice> slices;

  Map<String, Object?> toJson() => <String, Object?>{
    'manifestSchemaVersion': manifestSchemaVersion,
    'caseCount': caseCount,
    'overall': overall.toJson(),
    'slices': <Map<String, Object?>>[for (final slice in slices) slice.toJson()],
  };

  /// A stable, timestamp-free JSON rendering: the same report always
  /// produces byte-identical output.
  String toDeterministicJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}
