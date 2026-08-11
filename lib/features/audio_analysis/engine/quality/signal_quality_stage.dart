import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_stage.dart';

import 'quality_thresholds.dart';
import 'signal_quality_math.dart';

/// Immutable result that retains stage-only measurements outside the R02 domain
/// report until a later pipeline work-state can compose heterogeneous stages.
final class SignalQualityStageResult {
  SignalQualityStageResult({
    required this.report,
    required this.activeRegionRatio,
    required Iterable<String> degradedMetrics,
    required this.thresholdsVersion,
  }) : degradedMetrics = Set<String>.unmodifiable(degradedMetrics) {
    if (activeRegionRatio < 0 || activeRegionRatio > 1) {
      throw ArgumentError.value(activeRegionRatio, 'activeRegionRatio');
    }
    if (thresholdsVersion.trim().isEmpty) {
      throw ArgumentError.value(thresholdsVersion, 'thresholdsVersion');
    }
  }

  final SignalQualityReport report;
  final double activeRegionRatio;
  final Set<String> degradedMetrics;
  final String thresholdsVersion;
}

/// A deterministic, local-only measurement of recording conditions.
final class SignalQualityStage
    implements
        AnalysisStage<ValidatedPcmAnalysisInput, SignalQualityStageResult> {
  static const QualityThresholds thresholds = QualityThresholds.standard;

  @override
  String get id => 'signal-quality';

  @override
  int get version => 1;

  @override
  Future<AppResult<SignalQualityStageResult>> run(
    ValidatedPcmAnalysisInput input,
    AnalysisStageContext context,
  ) async {
    context.cancellationToken.throwIfCancelled();
    final samples = input.input.samples;
    final duration = Duration(
      microseconds:
          samples.length *
          Duration.microsecondsPerSecond ~/
          input.input.sampleRate,
    );
    final isShortClip = duration < thresholds.shortClipDuration;
    final clippedRatio = SignalQualityMath.clippedSampleRatio(samples);
    final silentRatio = SignalQualityMath.silentRatio(samples);
    final rmsDbfs = SignalQualityMath.rmsDbfs(samples);
    final warnings = <AnalysisWarning>[
      if (silentRatio >= thresholds.silentRatioWarning)
        AnalysisWarning(
          kind: AnalysisWarningKind.inputQuality,
          severity: AnalysisWarningSeverity.warning,
          messageKey: 'quality.recording_silent',
        )
      else if (rmsDbfs <= thresholds.silentSampleDbfs)
        AnalysisWarning(
          kind: AnalysisWarningKind.inputQuality,
          severity: AnalysisWarningSeverity.warning,
          messageKey: 'quality.recording_low_level',
        ),
      if (clippedRatio >= thresholds.clippedRatioWarning)
        AnalysisWarning(
          kind: AnalysisWarningKind.inputQuality,
          severity: AnalysisWarningSeverity.warning,
          messageKey: 'quality.recording_clipped',
        ),
      if (isShortClip)
        AnalysisWarning(
          kind: AnalysisWarningKind.inputQuality,
          severity: AnalysisWarningSeverity.info,
          messageKey: 'quality.recording_short_clip',
        ),
    ];
    final degradedMetrics = <String>{
      if (isShortClip) 'noiseFloorDbfs',
      if (isShortClip) 'tonalness',
    };
    final report = SignalQualityReport(
      overall: _overall(
        silentRatio: silentRatio,
        rmsDbfs: rmsDbfs,
        clippedRatio: clippedRatio,
        isShortClip: isShortClip,
      ),
      peakDbfs: SignalQualityMath.peakDbfs(samples),
      rmsDbfs: rmsDbfs,
      noiseFloorDbfs: SignalQualityMath.noiseFloorDbfs(samples),
      clippedSampleRatio: clippedRatio,
      silentRatio: silentRatio,
      tonalness: SignalQualityMath.tonalness(samples),
      warnings: warnings,
    );
    context.cancellationToken.throwIfCancelled();
    return Success<SignalQualityStageResult>(
      SignalQualityStageResult(
        report: report,
        activeRegionRatio: SignalQualityMath.activeRegionRatio(samples),
        degradedMetrics: degradedMetrics,
        thresholdsVersion: thresholds.version,
      ),
    );
  }

  double _overall({
    required double silentRatio,
    required double rmsDbfs,
    required double clippedRatio,
    required bool isShortClip,
  }) {
    var overall = 1.0;
    if (silentRatio >= thresholds.silentRatioWarning) {
      overall = thresholds.silentOverall;
    } else if (rmsDbfs <= thresholds.silentSampleDbfs) {
      overall = thresholds.lowLevelOverall;
    }
    if (clippedRatio >= thresholds.clippedRatioWarning) {
      overall *= thresholds.clippedOverallMultiplier;
    }
    if (isShortClip) overall *= thresholds.shortClipOverallMultiplier;
    return overall.clamp(0.0, 1.0);
  }
}
