import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';

import '../analysis_context.dart';
import '../analysis_stage.dart';
import 'quality_thresholds.dart';
import 'signal_quality_math.dart';

/// R04 pipeline stage: a deterministic, versioned recording-quality report
/// (ADR 0223). It never grades the player, never touches `DspConfig`, and
/// never publishes a terminal pipeline event — at most one
/// [AnalysisStageContext.reportProgress] call.
final class SignalQualityStage
    implements AnalysisStage<PcmAnalysisInput, SignalQualityReport> {
  const SignalQualityStage();

  @override
  String get id => 'signal_quality';

  @override
  int get version => QualityThresholds.version;

  @override
  Future<AppResult<SignalQualityReport>> run(
    PcmAnalysisInput input,
    AnalysisStageContext context,
  ) async {
    context.reportProgress();
    return AppResult<SignalQualityReport>.success(_buildReport(input));
  }

  SignalQualityReport _buildReport(PcmAnalysisInput input) {
    final samples = input.samples;
    const floor = QualityThresholds.silenceFloorDbfs;
    const ceiling = QualityThresholds.maxDbfs;

    final peakDbfs = SignalQualityMath.peakDbfs(
      samples,
      floorDbfs: floor,
      ceilingDbfs: ceiling,
    );
    final rmsDbfs = SignalQualityMath.rmsDbfs(
      samples,
      floorDbfs: floor,
      ceilingDbfs: ceiling,
    );
    final clippedSampleRatio = SignalQualityMath.clippedSampleRatio(
      samples,
      threshold: QualityThresholds.clippedSampleThreshold,
    );

    final frames = SignalQualityMath.frameMetrics(
      samples,
      frameSize: QualityThresholds.frameSize,
      hopSize: QualityThresholds.hopSize,
      floorDbfs: floor,
      ceilingDbfs: ceiling,
    );
    final frameRmsDbfsValues = <double>[
      for (final frame in frames) frame.rmsDbfs,
    ];
    final noiseFloorDbfs = frameRmsDbfsValues.isEmpty
        ? floor
        : SignalQualityMath.percentile(
            frameRmsDbfsValues,
            QualityThresholds.noiseFloorPercentile,
          );
    final silentRatio = SignalQualityMath.silentFrameRatio(
      frameRmsDbfsValues,
      silentThresholdDbfs: QualityThresholds.silentFrameDbfs,
    );
    final tonalness = SignalQualityMath.weightedTonalness(
      <double>[for (final frame in frames) frame.spectralFlatness],
      <double>[for (final frame in frames) frame.linearRms],
    );

    final overall = _overall(
      clippedSampleRatio: clippedSampleRatio,
      silentRatio: silentRatio,
      rmsDbfs: rmsDbfs,
      noiseFloorDbfs: noiseFloorDbfs,
      tonalness: tonalness,
    );

    final durationSeconds = input.sampleRate > 0
        ? samples.length / input.sampleRate
        : 0.0;
    final warnings = _warnings(
      durationSeconds: durationSeconds,
      clippedSampleRatio: clippedSampleRatio,
      silentRatio: silentRatio,
    );

    return SignalQualityReport(
      overall: overall,
      peakDbfs: peakDbfs,
      rmsDbfs: rmsDbfs,
      noiseFloorDbfs: noiseFloorDbfs,
      clippedSampleRatio: clippedSampleRatio,
      silentRatio: silentRatio,
      tonalness: tonalness,
      warnings: warnings,
    );
  }

  double _overall({
    required double clippedSampleRatio,
    required double silentRatio,
    required double rmsDbfs,
    required double noiseFloorDbfs,
    required double tonalness,
  }) {
    final clippingScore =
        (1.0 - clippedSampleRatio / QualityThresholds.clippingFullPenaltyRatio)
            .clamp(0.0, 1.0);
    final silenceScore = (1.0 - silentRatio).clamp(0.0, 1.0);
    final dynamicRangeScore =
        ((rmsDbfs - noiseFloorDbfs) / QualityThresholds.fullDynamicRangeDb)
            .clamp(0.0, 1.0);
    final tonalnessScore = tonalness.clamp(0.0, 1.0);

    final overall =
        QualityThresholds.weightClipping * clippingScore +
        QualityThresholds.weightSilence * silenceScore +
        QualityThresholds.weightDynamicRange * dynamicRangeScore +
        QualityThresholds.weightTonalness * tonalnessScore;
    return overall.clamp(0.0, 1.0);
  }

  List<AnalysisWarning> _warnings({
    required double durationSeconds,
    required double clippedSampleRatio,
    required double silentRatio,
  }) {
    final warnings = <AnalysisWarning>[];
    if (durationSeconds < QualityThresholds.minReliableDurationSeconds) {
      warnings.add(
        AnalysisWarning(
          kind: AnalysisWarningKind.inputQuality,
          severity: AnalysisWarningSeverity.info,
          messageKey: 'signal_quality.short_clip',
        ),
      );
    }
    if (clippedSampleRatio >= QualityThresholds.clippedRatioWarning) {
      warnings.add(
        AnalysisWarning(
          kind: AnalysisWarningKind.inputQuality,
          severity: AnalysisWarningSeverity.warning,
          messageKey: 'signal_quality.clipping_detected',
        ),
      );
    }
    if (silentRatio >= QualityThresholds.mostlySilentRatioWarning) {
      warnings.add(
        AnalysisWarning(
          kind: AnalysisWarningKind.inputQuality,
          severity: AnalysisWarningSeverity.warning,
          messageKey: 'signal_quality.mostly_silent',
        ),
      );
    }
    return warnings;
  }
}
