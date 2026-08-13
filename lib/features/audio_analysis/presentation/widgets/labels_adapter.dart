import 'package:strumsight/l10n/app_localizations.dart';

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_document.dart';
import '../../domain/analysis_input_summary.dart';
import '../../domain/analysis_insight.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/analysis_mode.dart';
import '../../domain/analysis_warning.dart';
import '../controllers/overview_view_model.dart';

/// Localised [OverviewLabels] backed by the generated [AppLocalizations].
///
/// The adapter never computes domain logic; every value it returns is a
/// either a direct string lookup, a deterministic format from a numeric
/// primitive the domain already validated, or a `switch` over a closed
/// enum. The view model may consume this adapter inside a build method.
final class AppLocalizationsOverviewLabels implements OverviewLabels {
  const AppLocalizationsOverviewLabels(this._l10n);

  final AppLocalizations _l10n;

  @override
  String actionDisabledTooltip(AnalysisRecommendedAction action) =>
      _l10n.analysisOverviewActionDisabledTooltip;

  @override
  String actionLabel(AnalysisRecommendedAction action) => switch (action) {
    AnalysisRecommendedAction.repeatSection =>
      _l10n.analysisOverviewActionRepeatSection,
    AnalysisRecommendedAction.slowDown => _l10n.analysisOverviewActionSlowDown,
    AnalysisRecommendedAction.adjustInput =>
      _l10n.analysisOverviewActionAdjustInput,
    AnalysisRecommendedAction.continuePractice =>
      _l10n.analysisOverviewActionContinuePractice,
  };

  @override
  String completionLabel(AnalysisCompletion completion) {
    return switch (completion.status) {
      AnalysisCompletionStatus.complete =>
        _l10n.analysisOverviewCompletionComplete,
      AnalysisCompletionStatus.degraded =>
        _l10n.analysisOverviewCompletionDegraded,
      AnalysisCompletionStatus.cancelled =>
        _l10n.analysisOverviewCompletionCancelled,
      AnalysisCompletionStatus.failed => _l10n.analysisOverviewCompletionFailed(
        completion.failureCode ?? '',
      ),
    };
  }

  @override
  String confidenceHigh() => _l10n.analysisOverviewConfidenceHigh;

  @override
  String confidenceLow() => _l10n.analysisOverviewConfidenceLow;

  @override
  String confidenceMedium() => _l10n.analysisOverviewConfidenceMedium;

  @override
  String formatDbfs(double dbfs) => '${dbfs.toStringAsFixed(1)} dB';

  @override
  String formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  String formatMetricValue(AnalysisMetricResult metric) {
    final value = metric.value;
    if (value == null) return _l10n.analysisOverviewMetricValuePlaceholder;
    if (value is ScalarMetricValue) {
      return _formatScalar(value.value, metric.unit);
    }
    if (value is PercentageMetricValue) {
      return '${(value.value * 100).toStringAsFixed(0)}%';
    }
    if (value is DurationMetricValue) {
      return '${value.value.inMilliseconds} ms';
    }
    if (value is ScoreMetricValue) {
      return value.value.toStringAsFixed(0);
    }
    if (value is CategoryMetricValue) {
      return value.value;
    }
    if (value is DistributionMetricValue) {
      return value.values.length.toString();
    }
    if (value is TimeSeriesMetricValue) {
      return value.points.length.toString();
    }
    return _l10n.analysisOverviewMetricValuePlaceholder;
  }

  String _formatScalar(double value, String unit) {
    if (unit == 's') {
      return '${(value * 1000).toStringAsFixed(0)} ms';
    }
    if (unit == 'ms') {
      return '${value.toStringAsFixed(0)} ms';
    }
    if (unit == 'ratio') {
      return value.toStringAsFixed(2);
    }
    return '${value.toStringAsFixed(2)} $unit';
  }

  @override
  String formatRatio(double ratio) => '${(ratio * 100).toStringAsFixed(1)}%';

  @override
  String inputSubtitle(AnalysisInputSummary input) {
    final source = switch (input.source) {
      AnalysisInputSource.microphone => _l10n.analysisOverviewInputMicrophone,
      AnalysisInputSource.importedFile =>
        _l10n.analysisOverviewInputImportedFile,
      AnalysisInputSource.practiceSession =>
        _l10n.analysisOverviewInputPracticeSession,
      AnalysisInputSource.songSession => _l10n.analysisOverviewInputSongSession,
    };
    return _l10n.analysisOverviewInputSubtitle(
      source,
      input.duration.inSeconds.toString(),
    );
  }

  @override
  String insightKindLabel(AnalysisInsightKind kind) => switch (kind) {
    AnalysisInsightKind.recommendation =>
      _l10n.analysisOverviewInsightKindLabelRecommendation,
    AnalysisInsightKind.observation =>
      _l10n.analysisOverviewInsightKindLabelObservation,
    AnalysisInsightKind.caution =>
      _l10n.analysisOverviewInsightKindLabelCaution,
  };

  @override
  String insightKindTitle(AnalysisInsightKind kind) => switch (kind) {
    AnalysisInsightKind.recommendation =>
      _l10n.analysisOverviewInsightKindTitleRecommendation,
    AnalysisInsightKind.observation =>
      _l10n.analysisOverviewInsightKindTitleObservation,
    AnalysisInsightKind.caution =>
      _l10n.analysisOverviewInsightKindTitleCaution,
  };

  /// Resolves an insight message key with its args. Only the canonical
  /// R20 insight keys are supported here; anything else falls back to the
  /// raw key as the test for "missing hu translation" expects to surface.
  @override
  String insightMessage(String messageKey, Map<String, String> args) {
    return switch (messageKey) {
      'analysisInsightRushBias' => _l10n.analysisInsightRushBias(
        _arg(args, 'milliseconds', '0'),
      ),
      'analysisInsightDragBias' => _l10n.analysisInsightDragBias(
        _arg(args, 'milliseconds', '0'),
      ),
      'analysisInsightLargeTimingOutliers' =>
        _l10n.analysisInsightLargeTimingOutliers(
          _arg(args, 'p90Milliseconds', '0'),
        ),
      'analysisInsightSecondHalfDrift' => _l10n.analysisInsightSecondHalfDrift(
        _arg(args, 'milliseconds', '0'),
      ),
      'analysisInsightWeakUpstroke' => _l10n.analysisInsightWeakUpstroke(
        _arg(args, 'ratio', '0'),
      ),
      'analysisInsightChordTransitionHotspot' =>
        _l10n.analysisInsightChordTransitionHotspot(
          _arg(args, 'hotspotId', ''),
        ),
      'analysisInsightLowSignalQuality' =>
        _l10n.analysisInsightLowSignalQuality(_arg(args, 'ratio', '0')),
      'analysisInsightCompatibleImprovement' =>
        _l10n.analysisInsightCompatibleImprovement(
          _arg(args, 'delta', '0'),
          _arg(args, 'metricId', ''),
        ),
      'analysisInsightInsufficientData' =>
        _l10n.analysisInsightInsufficientData,
      _ => messageKey,
    };
  }

  String _arg(Map<String, String> args, String key, String fallback) =>
      args[key] ?? fallback;

  @override
  String metricLabel(String metricId) {
    if (!AnalysisMetricId.contains(metricId)) return metricId;
    // Map the canonical metric IDs to their label keys.
    return switch (metricId) {
      AnalysisMetricId.timingMeanAbsoluteError =>
        _l10n.analysisMetricLabelTimingMeanAbsoluteError,
      AnalysisMetricId.rhythmRushDragBias =>
        _l10n.analysisMetricLabelRhythmRushDragBias,
      AnalysisMetricId.dynamicsStrumConsistency =>
        _l10n.analysisMetricLabelDynamicsStrokeStrengthCv,
      AnalysisMetricId.harmonyChordCoverage =>
        _l10n.analysisMetricLabelHarmonyChordCoverage,
      AnalysisMetricId.timingTargetMeanAbsoluteError =>
        _l10n.analysisMetricLabelTimingTargetMeanAbsoluteError,
      AnalysisMetricId.timingTargetMedianAbsoluteError =>
        _l10n.analysisMetricLabelTimingTargetMedianAbsoluteError,
      AnalysisMetricId.timingTargetP90AbsoluteError =>
        _l10n.analysisMetricLabelTimingTargetP90AbsoluteError,
      AnalysisMetricId.timingTargetSignedBias =>
        _l10n.analysisMetricLabelTimingTargetSignedBias,
      AnalysisMetricId.timingTargetOnTimeRatio =>
        _l10n.analysisMetricLabelTimingTargetOnTimeRatio,
      AnalysisMetricId.timingTargetEarlyRatio =>
        _l10n.analysisMetricLabelTimingTargetEarlyRatio,
      AnalysisMetricId.timingTargetLateRatio =>
        _l10n.analysisMetricLabelTimingTargetLateRatio,
      AnalysisMetricId.timingTargetMissedRatio =>
        _l10n.analysisMetricLabelTimingTargetMissedRatio,
      AnalysisMetricId.timingTargetExtraRatio =>
        _l10n.analysisMetricLabelTimingTargetExtraRatio,
      AnalysisMetricId.timingTargetLongestStableStreak =>
        _l10n.analysisMetricLabelTimingTargetLongestStableStreak,
      AnalysisMetricId.timingFreeplayMeanAbsoluteError =>
        _l10n.analysisMetricLabelTimingFreeplayMeanAbsoluteError,
      AnalysisMetricId.timingFreeplayMedianAbsoluteError =>
        _l10n.analysisMetricLabelTimingFreeplayMedianAbsoluteError,
      AnalysisMetricId.timingFreeplayP90AbsoluteError =>
        _l10n.analysisMetricLabelTimingFreeplayP90AbsoluteError,
      AnalysisMetricId.timingFreeplaySignedBias =>
        _l10n.analysisMetricLabelTimingFreeplaySignedBias,
      AnalysisMetricId.timingFreeplayOnTimeRatio =>
        _l10n.analysisMetricLabelTimingFreeplayOnTimeRatio,
      AnalysisMetricId.timingFreeplayEarlyRatio =>
        _l10n.analysisMetricLabelTimingFreeplayEarlyRatio,
      AnalysisMetricId.timingFreeplayLateRatio =>
        _l10n.analysisMetricLabelTimingFreeplayLateRatio,
      AnalysisMetricId.timingFreeplayMissedRatio =>
        _l10n.analysisMetricLabelTimingFreeplayMissedRatio,
      AnalysisMetricId.timingFreeplayExtraRatio =>
        _l10n.analysisMetricLabelTimingFreeplayExtraRatio,
      AnalysisMetricId.timingFreeplayLongestStableStreak =>
        _l10n.analysisMetricLabelTimingFreeplayLongestStableStreak,
      AnalysisMetricId.rhythmTargetIoiConsistency =>
        _l10n.analysisMetricLabelRhythmTargetIoiConsistency,
      AnalysisMetricId.rhythmTargetSubdivisionConsistency =>
        _l10n.analysisMetricLabelRhythmTargetSubdivisionConsistency,
      AnalysisMetricId.rhythmTargetBeatPhaseConsistency =>
        _l10n.analysisMetricLabelRhythmTargetBeatPhaseConsistency,
      AnalysisMetricId.rhythmTargetLongestStableIoiStreak =>
        _l10n.analysisMetricLabelRhythmTargetLongestStableIoiStreak,
      AnalysisMetricId.rhythmTargetAccentPositionConsistency =>
        _l10n.analysisMetricLabelRhythmTargetAccentPositionConsistency,
      AnalysisMetricId.rhythmTargetSwingRatio =>
        _l10n.analysisMetricLabelRhythmTargetSwingRatio,
      AnalysisMetricId.rhythmInferredIoiConsistency =>
        _l10n.analysisMetricLabelRhythmInferredIoiConsistency,
      AnalysisMetricId.rhythmInferredSubdivisionConsistency =>
        _l10n.analysisMetricLabelRhythmInferredSubdivisionConsistency,
      AnalysisMetricId.rhythmInferredBeatPhaseConsistency =>
        _l10n.analysisMetricLabelRhythmInferredBeatPhaseConsistency,
      AnalysisMetricId.rhythmInferredLongestStableIoiStreak =>
        _l10n.analysisMetricLabelRhythmInferredLongestStableIoiStreak,
      AnalysisMetricId.rhythmInferredAccentPositionConsistency =>
        _l10n.analysisMetricLabelRhythmInferredAccentPositionConsistency,
      AnalysisMetricId.dynamicsStrokeStrengthCv =>
        _l10n.analysisMetricLabelDynamicsStrokeStrengthCv,
      AnalysisMetricId.dynamicsDownUpMedianRatio =>
        _l10n.analysisMetricLabelDynamicsDownUpMedianRatio,
      AnalysisMetricId.dynamicsDrift => _l10n.analysisMetricLabelDynamicsDrift,
      AnalysisMetricId.dynamicsOutlierRatio =>
        _l10n.analysisMetricLabelDynamicsOutlierRatio,
      AnalysisMetricId.dynamicsAccentAccuracy =>
        _l10n.analysisMetricLabelDynamicsAccentAccuracy,
      AnalysisMetricId.dynamicsQuietRegionRatio =>
        _l10n.analysisMetricLabelDynamicsQuietRegionRatio,
      AnalysisMetricId.dynamicsClippedEventRatio =>
        _l10n.analysisMetricLabelDynamicsClippedEventRatio,
      AnalysisMetricId.pitchNoteHitRatio =>
        _l10n.analysisMetricLabelPitchNoteHitRatio,
      AnalysisMetricId.pitchMedianCentsError =>
        _l10n.analysisMetricLabelPitchMedianCentsError,
      AnalysisMetricId.pitchP90CentsError =>
        _l10n.analysisMetricLabelPitchP90CentsError,
      AnalysisMetricId.pitchStabilityCents =>
        _l10n.analysisMetricLabelPitchStabilityCents,
      AnalysisMetricId.pitchNoteTransitionTiming =>
        _l10n.analysisMetricLabelPitchNoteTransitionTiming,
      AnalysisMetricId.pitchSustainedNoteDuration =>
        _l10n.analysisMetricLabelPitchSustainedNoteDuration,
      AnalysisMetricId.pitchUnwantedDropoutRatio =>
        _l10n.analysisMetricLabelPitchUnwantedDropoutRatio,
      AnalysisMetricId.techniqueChordChangeGap =>
        _l10n.analysisMetricLabelTechniqueChordChangeGap,
      AnalysisMetricId.techniqueConfidenceCollapseDuration =>
        _l10n.analysisMetricLabelTechniqueConfidenceCollapseDuration,
      AnalysisMetricId.techniqueUnexpectedExtraOnsets =>
        _l10n.analysisMetricLabelTechniqueUnexpectedExtraOnsets,
      AnalysisMetricId.techniqueSustainedNoteDropout =>
        _l10n.analysisMetricLabelTechniqueSustainedNoteDropout,
      AnalysisMetricId.techniqueAttackInstability =>
        _l10n.analysisMetricLabelTechniqueAttackInstability,
      _ => metricId,
    };
  }

  @override
  String notApplicableStatusLabel() => _l10n.analysisOverviewNotApplicable;

  @override
  String notApplicableValuePlaceholder() =>
      _l10n.analysisOverviewMetricValueNotApplicable;

  @override
  String overviewTitle(AnalysisDocument document) =>
      _l10n.analysisOverviewTitle;

  @override
  String unavailableReason(CapabilityUnavailableReason reason) =>
      switch (reason) {
        CapabilityUnavailableReason.clipTooShort =>
          _l10n.analysisCapabilityUnavailableClipTooShort,
        CapabilityUnavailableReason.insufficientEvents =>
          _l10n.analysisCapabilityUnavailableInsufficientEvents,
        CapabilityUnavailableReason.inputTooNoisy =>
          _l10n.analysisCapabilityUnavailableInputTooNoisy,
        CapabilityUnavailableReason.inputClipped =>
          _l10n.analysisCapabilityUnavailableInputClipped,
        CapabilityUnavailableReason.polyphonicInput =>
          _l10n.analysisCapabilityUnavailablePolyphonicInput,
        CapabilityUnavailableReason.backingTrackDominant =>
          _l10n.analysisCapabilityUnavailableBackingTrackDominant,
        CapabilityUnavailableReason.confidenceTooLow =>
          _l10n.analysisCapabilityUnavailableConfidenceTooLow,
        CapabilityUnavailableReason.modelUnavailable =>
          _l10n.analysisCapabilityUnavailableModelUnavailable,
        CapabilityUnavailableReason.unsupportedFormat =>
          _l10n.analysisCapabilityUnavailableUnsupportedFormat,
        CapabilityUnavailableReason.unsupportedSampleRate =>
          _l10n.analysisCapabilityUnavailableUnsupportedSampleRate,
        CapabilityUnavailableReason.noReferenceTarget =>
          _l10n.analysisCapabilityUnavailableNoReferenceTarget,
        CapabilityUnavailableReason.cancelled =>
          _l10n.analysisCapabilityUnavailableCancelled,
        CapabilityUnavailableReason.internalFailure =>
          _l10n.analysisCapabilityUnavailableInternalFailure,
      };

  @override
  String unavailableStatusLabel() => _l10n.analysisOverviewUnavailable;

  @override
  String unavailableTip(CapabilityUnavailableReason reason) => switch (reason) {
    CapabilityUnavailableReason.clipTooShort =>
      _l10n.analysisOverviewUnavailableTipClipTooShort,
    CapabilityUnavailableReason.insufficientEvents =>
      _l10n.analysisOverviewUnavailableTipInsufficientEvents,
    CapabilityUnavailableReason.inputTooNoisy =>
      _l10n.analysisOverviewUnavailableTipInputTooNoisy,
    CapabilityUnavailableReason.inputClipped =>
      _l10n.analysisOverviewUnavailableTipInputClipped,
    CapabilityUnavailableReason.polyphonicInput =>
      _l10n.analysisOverviewUnavailableTipPolyphonicInput,
    CapabilityUnavailableReason.backingTrackDominant =>
      _l10n.analysisOverviewUnavailableTipBackingTrackDominant,
    CapabilityUnavailableReason.confidenceTooLow =>
      _l10n.analysisOverviewUnavailableTipConfidenceTooLow,
    CapabilityUnavailableReason.modelUnavailable =>
      _l10n.analysisOverviewUnavailableTipModelUnavailable,
    CapabilityUnavailableReason.unsupportedFormat =>
      _l10n.analysisOverviewUnavailableTipUnsupportedFormat,
    CapabilityUnavailableReason.unsupportedSampleRate =>
      _l10n.analysisOverviewUnavailableTipUnsupportedSampleRate,
    CapabilityUnavailableReason.noReferenceTarget =>
      _l10n.analysisOverviewUnavailableTipNoReferenceTarget,
    CapabilityUnavailableReason.cancelled =>
      _l10n.analysisOverviewUnavailableTipCancelled,
    CapabilityUnavailableReason.internalFailure =>
      _l10n.analysisOverviewUnavailableTipInternalFailure,
  };

  @override
  String unavailableValuePlaceholder() =>
      _l10n.analysisOverviewMetricValueUnavailable;

  @override
  String warningHeadline(AnalysisWarning warning) {
    final kindLabel = switch (warning.kind) {
      AnalysisWarningKind.inputQuality =>
        _l10n.analysisOverviewWarningInputQuality,
      AnalysisWarningKind.capability => _l10n.analysisOverviewWarningCapability,
      AnalysisWarningKind.processing => _l10n.analysisOverviewWarningProcessing,
      AnalysisWarningKind.migration => _l10n.analysisOverviewWarningMigration,
    };
    return kindLabel;
  }
}
