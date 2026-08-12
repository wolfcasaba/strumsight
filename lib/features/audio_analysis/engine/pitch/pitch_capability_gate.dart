import 'dart:math' as math;

import '../../domain/analysis_capability.dart';
import '../../domain/pitch/pitch_frame.dart';
import '../../domain/signal_quality_report.dart';
import 'monophonic_pitch_segment_builder.dart';

/// Capability verdict plus an optional result built only after the gate opens.
final class PitchCapabilityEvaluation<T> {
  const PitchCapabilityEvaluation({required this.report, this.value});

  final CapabilityReport report;
  final T? value;
}

/// Fail-closed boundary for the experimental monophonic pitch capability.
///
/// `analysisPitchEnabled` is deliberately the first condition evaluated. The
/// optional [onAvailable] seam lets callers prove that expensive metric work
/// never starts for disabled or unsupported input (ADR 0235 decision 5).
final class PitchCapabilityGate {
  PitchCapabilityGate({
    this.minimumVoicedRatio = 0.35,
    this.minimumMedianConfidence = 0.6,
    this.maximumPitchSpreadCents = 100,
    this.maximumNoiseFloorDbfs = -25,
  }) {
    if (!minimumVoicedRatio.isFinite ||
        minimumVoicedRatio < 0 ||
        minimumVoicedRatio > 1 ||
        !minimumMedianConfidence.isFinite ||
        minimumMedianConfidence < 0 ||
        minimumMedianConfidence > 1 ||
        !maximumPitchSpreadCents.isFinite ||
        maximumPitchSpreadCents <= 0 ||
        !maximumNoiseFloorDbfs.isFinite) {
      throw ArgumentError(
        'Pitch capability thresholds must be finite and valid.',
      );
    }
  }

  final double minimumVoicedRatio;
  final double minimumMedianConfidence;
  final double maximumPitchSpreadCents;
  final double maximumNoiseFloorDbfs;

  PitchCapabilityEvaluation<T> evaluate<T>({
    required bool analysisPitchEnabled,
    required bool hasMonophonicTarget,
    required List<PitchFrame> frames,
    SignalQualityReport? signalQuality,
    T Function()? onAvailable,
  }) {
    // This must remain first: the flag is the release boundary, independent
    // of input content and before every OD-01 condition.
    if (!analysisPitchEnabled) {
      return PitchCapabilityEvaluation<T>(
        report: CapabilityReport(
          capability: AnalysisCapability.monophonicPitch,
          status: CapabilityStatus.notApplicable,
          confidence: 0,
        ),
      );
    }
    if (!hasMonophonicTarget) {
      return PitchCapabilityEvaluation<T>(
        report: CapabilityReport(
          capability: AnalysisCapability.monophonicPitch,
          status: CapabilityStatus.notApplicable,
          confidence: 0,
        ),
      );
    }
    if (frames.isEmpty) {
      return _unavailable<T>(CapabilityUnavailableReason.insufficientEvents);
    }

    final voiced = <PitchFrame>[
      for (final frame in frames)
        if (frame.isVoiced) frame,
    ];
    final voicedRatio = voiced.length / frames.length;
    if (voicedRatio < minimumVoicedRatio) {
      return _unavailable<T>(
        voiced.isEmpty
            ? CapabilityUnavailableReason.insufficientEvents
            : CapabilityUnavailableReason.confidenceTooLow,
      );
    }
    final medianConfidence = _median(<double>[
      for (final frame in voiced) frame.confidence,
    ]);
    if (medianConfidence < minimumMedianConfidence) {
      return _unavailable<T>(CapabilityUnavailableReason.confidenceTooLow);
    }
    final spread = _pitchSpreadCents(voiced);
    if (spread > maximumPitchSpreadCents) {
      return _unavailable<T>(CapabilityUnavailableReason.polyphonicInput);
    }
    if (signalQuality != null &&
        (!signalQuality.measured ||
            !signalQuality.noiseFloorDbfs.isFinite ||
            !signalQuality.silentRatio.isFinite ||
            signalQuality.noiseFloorDbfs >= maximumNoiseFloorDbfs ||
            signalQuality.silentRatio >= 0.95)) {
      return _unavailable<T>(CapabilityUnavailableReason.inputTooNoisy);
    }
    final confidence = (medianConfidence * voicedRatio).clamp(0.0, 1.0);
    return PitchCapabilityEvaluation<T>(
      report: CapabilityReport(
        capability: AnalysisCapability.monophonicPitch,
        status: CapabilityStatus.available,
        confidence: confidence,
        details: <String, Object?>{
          'voicedRatio': voicedRatio,
          'medianConfidence': medianConfidence,
          'pitchSpreadCents': spread,
        },
      ),
      value: onAvailable?.call(),
    );
  }

  PitchCapabilityEvaluation<T> _unavailable<T>(
    CapabilityUnavailableReason reason,
  ) => PitchCapabilityEvaluation<T>(
    report: CapabilityReport(
      capability: AnalysisCapability.monophonicPitch,
      status: CapabilityStatus.unavailable,
      confidence: 0,
      reason: reason,
    ),
  );
}

double _pitchSpreadCents(List<PitchFrame> frames) {
  final frequencies = <double>[for (final frame in frames) frame.frequencyHz!];
  final medianHz = _median(frequencies);
  return <double>[
    for (final frequency in frequencies)
      centsBetween(medianHz, frequency).abs(),
  ].reduce(math.max);
}

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
