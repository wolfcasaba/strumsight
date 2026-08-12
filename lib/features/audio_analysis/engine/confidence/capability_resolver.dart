import '../../domain/analysis_capability.dart';
import '../../domain/analysis_mode.dart';
import '../../domain/signal_quality_report.dart';
import 'calibration_table.dart';
import 'capability_thresholds.dart';
import 'confidence_combiner.dart';

/// Immutable evidence passed to the one V2 capability decision point.
final class CapabilityResolverInput {
  CapabilityResolverInput({
    required this.signalQuality,
    required this.eventCount,
    required this.modelConfidence,
    required this.alignmentQuality,
    required this.mode,
    required this.hasReferenceTarget,
    required this.modelAvailable,
    this.isClipTooShort = false,
    this.hypothesesAgree = true,
    Set<AnalysisCapability>? supportedCapabilities,
  }) : supportedCapabilities = Set<AnalysisCapability>.unmodifiable(
         supportedCapabilities ?? AnalysisCapability.values.toSet(),
       ) {
    if (eventCount < 0 ||
        !modelConfidence.isFinite ||
        modelConfidence < 0 ||
        modelConfidence > 1 ||
        !alignmentQuality.isFinite ||
        alignmentQuality < 0 ||
        alignmentQuality > 1) {
      throw ArgumentError(
        'Capability resolver input must be finite and valid.',
      );
    }
  }

  final SignalQualityReport signalQuality;
  final int eventCount;
  final double modelConfidence;
  final double alignmentQuality;
  final AnalysisMode mode;
  final bool hasReferenceTarget;
  final bool modelAvailable;
  final bool isClipTooShort;
  final bool hypothesesAgree;
  final Set<AnalysisCapability> supportedCapabilities;
}

/// Complete, immutable V2 capability verdict with Lab diagnostics.
final class CapabilityResolution {
  CapabilityResolution({
    required Map<AnalysisCapability, CapabilityReport> reports,
    required this.overallConfidence,
    required this.overallStatus,
    required this.calibrationVersion,
    required this.thresholdsVersion,
  }) : reports = Map<AnalysisCapability, CapabilityReport>.unmodifiable(
         reports,
       );

  final Map<AnalysisCapability, CapabilityReport> reports;
  final double overallConfidence;
  final CapabilityStatus overallStatus;
  final String calibrationVersion;
  final String thresholdsVersion;
}

/// Sole V2 authority for whether an analysis capability may be published.
///
/// Existing R14–R18 gates remain independent until their dedicated retrofit
/// round. New consumers must use this resolver rather than reconstructing a
/// status from individual scores. If no capability applies, [resolve] returns
/// a zero-confidence [CapabilityStatus.notApplicable] overall verdict.
final class CapabilityResolver {
  CapabilityResolver({
    CapabilityThresholds? thresholds,
    this._calibrationTable = const CalibrationTable.identityV1(),
    ConfidenceCombiner? confidenceCombiner,
  }) : _thresholds = thresholds ?? CapabilityThresholds(),
       _confidenceCombiner = confidenceCombiner ?? ConfidenceCombiner();

  static const Set<AnalysisCapability> _criticalCapabilities =
      <AnalysisCapability>{
        AnalysisCapability.signalQuality,
        AnalysisCapability.onsetTimeline,
      };

  static const Set<AnalysisCapability> _targetCapabilities =
      <AnalysisCapability>{
        AnalysisCapability.chordTimeline,
        AnalysisCapability.timingAccuracy,
        AnalysisCapability.intonation,
        AnalysisCapability.transitionSmoothness,
        AnalysisCapability.targetAlignment,
      };

  final CapabilityThresholds _thresholds;
  final CalibrationTable _calibrationTable;
  final ConfidenceCombiner _confidenceCombiner;

  CapabilityResolution resolve(CapabilityResolverInput input) {
    final reports = <AnalysisCapability, CapabilityReport>{
      for (final capability in AnalysisCapability.values)
        capability: _resolveCapability(capability, input),
    };
    final criticalUnavailable = _criticalCapabilities.any(
      (capability) =>
          reports[capability]!.status == CapabilityStatus.unavailable,
    );
    final overallFactors = <double>[
      for (final report in reports.values)
        if (report.status != CapabilityStatus.notApplicable) report.confidence,
    ];
    if (overallFactors.isEmpty) {
      return CapabilityResolution(
        reports: reports,
        overallConfidence: 0,
        overallStatus: CapabilityStatus.notApplicable,
        calibrationVersion: _calibrationTable.version,
        thresholdsVersion: _thresholds.version,
      );
    }
    final overallConfidence = _confidenceCombiner
        .combine(overallFactors, hardGateOpen: !criticalUnavailable)
        .confidence;
    final overallStatus = _statusFor(overallConfidence);
    return CapabilityResolution(
      reports: reports,
      overallConfidence: overallConfidence,
      overallStatus:
          criticalUnavailable && overallStatus == CapabilityStatus.available
          ? CapabilityStatus.degraded
          : overallStatus,
      calibrationVersion: _calibrationTable.version,
      thresholdsVersion: _thresholds.version,
    );
  }

  CapabilityReport _resolveCapability(
    AnalysisCapability capability,
    CapabilityResolverInput input,
  ) {
    if (!input.supportedCapabilities.contains(capability)) {
      return _report(
        capability: capability,
        status: CapabilityStatus.notApplicable,
        confidence: 0,
        input: input,
      );
    }

    if (_targetCapabilities.contains(capability) &&
        !_modeUsesReferenceTarget(input.mode)) {
      return _report(
        capability: capability,
        status: CapabilityStatus.notApplicable,
        confidence: 0,
        input: input,
      );
    }

    final qualityFailure = _signalQualityFailure(input.signalQuality);
    if (input.isClipTooShort) {
      return _unavailable(
        capability,
        CapabilityUnavailableReason.clipTooShort,
        input,
      );
    }
    if (qualityFailure != null) {
      return _unavailable(capability, qualityFailure, input);
    }
    if (capability != AnalysisCapability.signalQuality &&
        !input.modelAvailable) {
      return _unavailable(
        capability,
        CapabilityUnavailableReason.modelUnavailable,
        input,
      );
    }
    if (capability != AnalysisCapability.signalQuality &&
        input.eventCount < _thresholds.minimumEventCount) {
      return _unavailable(
        capability,
        CapabilityUnavailableReason.insufficientEvents,
        input,
      );
    }
    if (_targetCapabilities.contains(capability) && !input.hasReferenceTarget) {
      return _unavailable(
        capability,
        CapabilityUnavailableReason.noReferenceTarget,
        input,
      );
    }
    if (!input.hypothesesAgree) {
      return _unavailable(
        capability,
        CapabilityUnavailableReason.confidenceTooLow,
        input,
      );
    }

    final rawConfidence = _confidenceCombiner.combine(<double>[
      input.signalQuality.overall,
      input.modelConfidence,
      input.alignmentQuality,
    ]).confidence;
    final calibration = _calibrationTable.calibrate(rawConfidence);
    final status = _statusFor(calibration.confidence);
    return _report(
      capability: capability,
      status: status,
      confidence: calibration.confidence,
      reason: status == CapabilityStatus.unavailable
          ? CapabilityUnavailableReason.confidenceTooLow
          : null,
      input: input,
    );
  }

  CapabilityReport _unavailable(
    AnalysisCapability capability,
    CapabilityUnavailableReason reason,
    CapabilityResolverInput input,
  ) => _report(
    capability: capability,
    status: CapabilityStatus.unavailable,
    confidence: 0,
    reason: reason,
    input: input,
  );

  CapabilityReport _report({
    required AnalysisCapability capability,
    required CapabilityStatus status,
    required double confidence,
    required CapabilityResolverInput input,
    CapabilityUnavailableReason? reason,
  }) => CapabilityReport(
    capability: capability,
    status: status,
    confidence: confidence,
    reason: reason,
    calibrationVersion: _calibrationTable.version,
    calibrationSource: _calibrationTable.source,
    details: <String, Object?>{
      'signalQuality': input.signalQuality.overall,
      'modelConfidence': input.modelConfidence,
      'alignmentQuality': input.alignmentQuality,
      'eventCount': input.eventCount,
      'mode': input.mode.name,
      'calibrationVersion': _calibrationTable.version,
      'thresholdsVersion': _thresholds.version,
    },
  );

  CapabilityUnavailableReason? _signalQualityFailure(
    SignalQualityReport signalQuality,
  ) {
    if (!signalQuality.measured ||
        !signalQuality.overall.isFinite ||
        signalQuality.overall < 0 ||
        signalQuality.overall > 1 ||
        !signalQuality.clippedSampleRatio.isFinite ||
        signalQuality.clippedSampleRatio < 0 ||
        signalQuality.clippedSampleRatio > 1 ||
        !signalQuality.noiseFloorDbfs.isFinite ||
        !signalQuality.silentRatio.isFinite ||
        signalQuality.silentRatio < 0 ||
        signalQuality.silentRatio > 1) {
      return CapabilityUnavailableReason.internalFailure;
    }
    if (signalQuality.clippedSampleRatio >
        _thresholds.maximumClippedSampleRatio) {
      return CapabilityUnavailableReason.inputClipped;
    }
    if (signalQuality.noiseFloorDbfs >= _thresholds.maximumNoiseFloorDbfs ||
        signalQuality.silentRatio >= _thresholds.maximumSilentRatio) {
      return CapabilityUnavailableReason.inputTooNoisy;
    }
    return null;
  }

  CapabilityStatus _statusFor(double confidence) {
    if (confidence >= _thresholds.minimumAvailableConfidence) {
      return CapabilityStatus.available;
    }
    if (confidence >= _thresholds.minimumDegradedConfidence) {
      return CapabilityStatus.degraded;
    }
    return CapabilityStatus.unavailable;
  }

  bool _modeUsesReferenceTarget(AnalysisMode mode) =>
      mode == AnalysisMode.practiceTarget || mode == AnalysisMode.songReference;
}
