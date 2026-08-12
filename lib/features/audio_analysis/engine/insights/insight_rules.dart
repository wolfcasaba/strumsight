import '../../domain/analysis_metric_catalog.dart';
import '../../domain/insights/insight_rule.dart';
import '../../domain/insights/recommended_action.dart';

const _ruleVersion = 1;
const _biasThresholdMs = 20.0;
const _upstrokeWeakMultiplier = 1.2;
const _lowQualityClippedRatio = 0.05;

const _timingMeanIds = <String>[
  AnalysisMetricId.timingTargetMeanAbsoluteError,
  AnalysisMetricId.timingFreeplayMeanAbsoluteError,
];
const _timingMedianIds = <String>[
  AnalysisMetricId.timingTargetMedianAbsoluteError,
  AnalysisMetricId.timingFreeplayMedianAbsoluteError,
];
const _timingP90Ids = <String>[
  AnalysisMetricId.timingTargetP90AbsoluteError,
  AnalysisMetricId.timingFreeplayP90AbsoluteError,
];
const _timingBiasIds = <String>[
  AnalysisMetricId.timingTargetSignedBias,
  AnalysisMetricId.timingFreeplaySignedBias,
];
const _timingRequiredIds = <String>[..._timingMeanIds, ..._timingBiasIds];

/// The nine initial deterministic rules specified for E06-R20.
List<AnalysisInsightRule> buildInitialInsightRules() =>
    const <AnalysisInsightRule>[
      RushBiasInsightRule(),
      DragBiasInsightRule(),
      LargeTimingOutlierInsightRule(),
      SecondHalfDriftInsightRule(),
      WeakUpstrokeInsightRule(),
      ChordTransitionHotspotInsightRule(),
      LowSignalQualityInsightRule(),
      CompatibleImprovementInsightRule(),
      InsufficientDataInsightRule(),
    ];

String? _firstUsableId(AnalysisInsightContext context, List<String> ids) {
  for (final id in ids) {
    if (context.scalar(id) != null) return id;
  }
  return null;
}

final class RushBiasInsightRule implements AnalysisInsightRule {
  const RushBiasInsightRule();
  @override
  String get id => 'timing.rush_bias';
  @override
  int get version => _ruleVersion;
  @override
  EvidenceInsightPriority get priority => EvidenceInsightPriority.high;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context) {
    final metricId = _firstUsableId(context, _timingBiasIds);
    if (metricId == null) return null;
    final value = context.scalar(metricId);
    if (value == null || value > -_biasThresholdMs) return null;
    final evidence = context.firstEvidenceFor(<String>[metricId]);
    if (evidence == null) return null;
    return context.insight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.improvement,
      factIds: <String>[metricId],
      evidenceIds: <String>[evidence],
      messageKey: 'analysisInsightRushBias',
      messageArgs: <String, String>{
        'milliseconds': value.abs().toStringAsFixed(1),
      },
      confidence: context.metric(metricId)!.confidence,
      recommendedAction: RepeatSlowerAction(metricId: metricId),
    );
  }
}

final class DragBiasInsightRule implements AnalysisInsightRule {
  const DragBiasInsightRule();
  @override
  String get id => 'timing.drag_bias';
  @override
  int get version => _ruleVersion;
  @override
  EvidenceInsightPriority get priority => EvidenceInsightPriority.high;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context) {
    final metricId = _firstUsableId(context, _timingBiasIds);
    if (metricId == null) return null;
    final value = context.scalar(metricId);
    if (value == null || value < _biasThresholdMs) return null;
    final evidence = context.firstEvidenceFor(<String>[metricId]);
    if (evidence == null) return null;
    return context.insight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.improvement,
      factIds: <String>[metricId],
      evidenceIds: <String>[evidence],
      messageKey: 'analysisInsightDragBias',
      messageArgs: <String, String>{'milliseconds': value.toStringAsFixed(1)},
      confidence: context.metric(metricId)!.confidence,
      recommendedAction: RepeatSlowerAction(metricId: metricId),
    );
  }
}

final class LargeTimingOutlierInsightRule implements AnalysisInsightRule {
  const LargeTimingOutlierInsightRule();
  @override
  String get id => 'timing.large_outliers';
  @override
  int get version => _ruleVersion;
  @override
  EvidenceInsightPriority get priority => EvidenceInsightPriority.medium;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context) {
    final medianId = _firstUsableId(context, _timingMedianIds);
    final p90Id = _firstUsableId(context, _timingP90Ids);
    if (medianId == null || p90Id == null) return null;
    final median = context.scalar(medianId);
    final p90 = context.scalar(p90Id);
    if (median == null ||
        p90 == null ||
        median > context.timingTolerance.inMicroseconds / 1000 ||
        p90 < 3 * median) {
      return null;
    }
    final evidence = context.firstEvidenceFor(<String>[medianId, p90Id]);
    if (evidence == null) return null;
    return context.insight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.improvement,
      factIds: <String>[medianId, p90Id],
      evidenceIds: <String>[evidence],
      messageKey: 'analysisInsightLargeTimingOutliers',
      messageArgs: <String, String>{'p90Milliseconds': p90.toStringAsFixed(1)},
      confidence:
          (context.metric(medianId)!.confidence +
              context.metric(p90Id)!.confidence) /
          2,
      recommendedAction: RepeatSlowerAction(metricId: p90Id),
    );
  }
}

final class SecondHalfDriftInsightRule implements AnalysisInsightRule {
  const SecondHalfDriftInsightRule();
  @override
  String get id => 'timing.second_half_drift';
  @override
  int get version => _ruleVersion;
  @override
  EvidenceInsightPriority get priority => EvidenceInsightPriority.medium;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context) {
    final metricId = _firstUsableId(context, _timingMeanIds);
    final evidence = context.timingEvidence;
    if (metricId == null ||
        evidence == null ||
        evidence.firstHalfMatchedEventIds.length < 4 ||
        evidence.secondHalfMatchedEventIds.length < 4 ||
        evidence.secondHalfMeanAbsoluteErrorMs <
            1.5 * evidence.firstHalfMeanAbsoluteErrorMs) {
      return null;
    }
    final evidenceIds = <String>[
      ...evidence.firstHalfMatchedEventIds,
      ...evidence.secondHalfMatchedEventIds,
    ];
    return context.insight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.improvement,
      factIds: <String>[metricId],
      evidenceIds: evidenceIds,
      messageKey: 'analysisInsightSecondHalfDrift',
      messageArgs: <String, String>{
        'milliseconds': evidence.secondHalfMeanAbsoluteErrorMs.toStringAsFixed(
          1,
        ),
      },
      confidence: context.metric(metricId)!.confidence,
      recommendedAction: RepeatSlowerAction(metricId: metricId),
    );
  }
}

final class WeakUpstrokeInsightRule implements AnalysisInsightRule {
  const WeakUpstrokeInsightRule();
  @override
  String get id => 'dynamics.weak_upstroke';
  @override
  int get version => _ruleVersion;
  @override
  EvidenceInsightPriority get priority => EvidenceInsightPriority.medium;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context) {
    const metricId = AnalysisMetricId.dynamicsDownUpMedianRatio;
    final ratio = context.scalar(metricId);
    final evidence = context.strokeBalance;
    if (ratio == null ||
        evidence == null ||
        evidence.upstrokeEventIds.isEmpty ||
        ratio < evidence.targetDownUpMedianRatio * _upstrokeWeakMultiplier) {
      return null;
    }
    return context.insight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.improvement,
      factIds: const <String>[metricId],
      evidenceIds: evidence.upstrokeEventIds,
      messageKey: 'analysisInsightWeakUpstroke',
      messageArgs: <String, String>{'ratio': ratio.toStringAsFixed(2)},
      confidence: context.metric(metricId)!.confidence,
      recommendedAction: RepeatSlowerAction(metricId: metricId),
    );
  }
}

final class ChordTransitionHotspotInsightRule implements AnalysisInsightRule {
  const ChordTransitionHotspotInsightRule();
  @override
  String get id => 'harmony.chord_transition_hotspot';
  @override
  int get version => _ruleVersion;
  @override
  EvidenceInsightPriority get priority => EvidenceInsightPriority.high;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context) {
    final hotspot = firstChordTransitionHotspot(context);
    if (hotspot == null || hotspot.metricIds.isEmpty) return null;
    final facts = hotspot.metricIds.where(isPublicMetricId).toList();
    if (facts.isEmpty) return null;
    return context.insight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.improvement,
      factIds: facts,
      evidenceIds: <String>[hotspot.id],
      messageKey: 'analysisInsightChordTransitionHotspot',
      messageArgs: <String, String>{'hotspotId': hotspot.id},
      confidence: hotspot.confidence,
      recommendedAction: OpenChordTransitionExerciseAction(
        hotspotId: hotspot.id,
      ),
    );
  }
}

final class LowSignalQualityInsightRule implements AnalysisInsightRule {
  const LowSignalQualityInsightRule();
  @override
  String get id => 'quality.low_signal';
  @override
  int get version => _ruleVersion;
  @override
  EvidenceInsightPriority get priority => EvidenceInsightPriority.critical;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context) {
    const metricId = AnalysisMetricId.dynamicsClippedEventRatio;
    final ratio = context.scalar(metricId);
    if (ratio == null || ratio < _lowQualityClippedRatio) return null;
    final evidence = context.firstEvidenceFor(const <String>[metricId]);
    if (evidence == null) return null;
    return context.insight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.qualityWarning,
      factIds: const <String>[metricId],
      evidenceIds: <String>[evidence],
      messageKey: 'analysisInsightLowSignalQuality',
      messageArgs: <String, String>{'ratio': ratio.toStringAsFixed(2)},
      confidence: context.metric(metricId)!.confidence,
      recommendedAction: const CalibrateInputAction(),
    );
  }
}

final class CompatibleImprovementInsightRule implements AnalysisInsightRule {
  const CompatibleImprovementInsightRule();
  @override
  String get id => 'comparison.compatible_improvement';
  @override
  int get version => _ruleVersion;
  @override
  EvidenceInsightPriority get priority => EvidenceInsightPriority.low;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context) {
    final comparison = context.previousComparison;
    if (comparison == null ||
        !isPublicMetricId(comparison.metricId) ||
        !context.isUsable(context.metric(comparison.metricId)) ||
        !comparison.hasMeaningfulImprovement) {
      return null;
    }
    return context.insight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.strength,
      factIds: <String>[comparison.metricId],
      evidenceIds: comparison.evidenceIds,
      messageKey: 'analysisInsightCompatibleImprovement',
      messageArgs: <String, String>{
        'metricId': comparison.metricId,
        'delta': (comparison.currentValue - comparison.previousValue)
            .abs()
            .toStringAsFixed(2),
      },
      confidence: context.metric(comparison.metricId)!.confidence,
      recommendedAction: CompareWithPreviousAction(
        metricId: comparison.metricId,
      ),
    );
  }
}

final class InsufficientDataInsightRule implements AnalysisInsightRule {
  const InsufficientDataInsightRule();
  @override
  String get id => 'data.insufficient';
  @override
  int get version => _ruleVersion;
  @override
  EvidenceInsightPriority get priority => EvidenceInsightPriority.critical;

  @override
  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context) {
    final unavailable = _timingRequiredIds
        .where((id) => context.metric(id) != null)
        .where((id) => !context.isUsable(context.metric(id)))
        .toList();
    if (unavailable.isEmpty) return null;
    final evidence = context.firstEvidenceFor(
      unavailable,
      allowDocumentFallback: true,
    );
    if (evidence == null) return null;
    return context.insight(
      ruleId: id,
      ruleVersion: version,
      priority: priority,
      kind: EvidenceInsightKind.nextAction,
      factIds: unavailable,
      evidenceIds: <String>[evidence],
      messageKey: 'analysisInsightInsufficientData',
      confidence: 1,
      recommendedAction: const CalibrateInputAction(),
    );
  }
}
