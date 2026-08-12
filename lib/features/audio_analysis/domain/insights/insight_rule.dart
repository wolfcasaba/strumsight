import '../analysis_capability.dart';
import '../analysis_document.dart';
import '../analysis_hotspot.dart';
import '../analysis_metric.dart';
import '../analysis_metric_catalog.dart';
import 'recommended_action.dart';

enum EvidenceInsightPriority { critical, high, medium, low }

enum EvidenceInsightKind { improvement, strength, nextAction, qualityWarning }

/// Immutable, localized, evidence-backed output of an [AnalysisInsightRule].
final class EvidenceBackedAnalysisInsight {
  EvidenceBackedAnalysisInsight({
    required this.ruleId,
    required this.ruleVersion,
    required this.priority,
    required this.kind,
    required List<String> factIds,
    required List<String> evidenceIds,
    required this.messageKey,
    required Map<String, String> messageArgs,
    required this.confidence,
    required this.recommendedAction,
  }) : factIds = List<String>.unmodifiable(factIds),
       evidenceIds = List<String>.unmodifiable(evidenceIds),
       messageArgs = Map<String, String>.unmodifiable(messageArgs) {
    if (ruleId.trim().isEmpty || ruleVersion < 1 || messageKey.trim().isEmpty) {
      throw ArgumentError('Insight identity and message key must be valid.');
    }
    if (this.factIds.isEmpty || this.evidenceIds.isEmpty) {
      throw ArgumentError('Insights require fact and evidence references.');
    }
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence');
    }
  }

  final String ruleId;
  final int ruleVersion;
  final EvidenceInsightPriority priority;
  final EvidenceInsightKind kind;
  final List<String> factIds;
  final List<String> evidenceIds;
  final String messageKey;
  final Map<String, String> messageArgs;
  final double confidence;
  final RecommendedAnalysisAction recommendedAction;
}

/// Input supplied by a later analysis integration. It deliberately exposes
/// only publishable document facts, never Lab-only technique proxy output.
final class AnalysisInsightContext {
  AnalysisInsightContext({
    required this.document,
    this.timingTolerance = const Duration(milliseconds: 20),
    this.timingEvidence,
    this.strokeBalance,
    this.previousComparison,
  }) {
    if (timingTolerance.isNegative) {
      throw ArgumentError.value(timingTolerance, 'timingTolerance');
    }
    if (document.metrics.any((metric) => metric.id.startsWith('technique.'))) {
      throw ArgumentError('Lab-only technique metrics are not insight inputs.');
    }
  }

  final AnalysisDocument document;
  final Duration timingTolerance;
  final TimingInsightEvidence? timingEvidence;
  final StrokeBalanceInsightEvidence? strokeBalance;
  final PreviousMetricComparison? previousComparison;

  AnalysisMetricResult? metric(String id) {
    if (id.startsWith('technique.')) return null;
    for (final item in document.metrics) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool isUsable(AnalysisMetricResult? metric) =>
      metric != null &&
      (metric.status == CapabilityStatus.available ||
          metric.status == CapabilityStatus.degraded) &&
      metric.value != null;

  double? scalar(String id) {
    final result = metric(id);
    if (!isUsable(result)) return null;
    return switch (result!.value) {
      ScalarMetricValue(:final value) => value,
      PercentageMetricValue(:final value) => value,
      DurationMetricValue(:final value) => value.inMicroseconds / 1000,
      ScoreMetricValue(:final value) => value,
      _ => null,
    };
  }

  String? firstEvidenceFor(
    Iterable<String> factIds, {
    bool allowDocumentFallback = false,
  }) {
    for (final id in factIds) {
      final evidence = metric(id)?.evidence;
      if (evidence != null &&
          evidence.isNotEmpty &&
          hasEvidence(evidence.first)) {
        return evidence.first;
      }
    }
    if (!allowDocumentFallback) return null;
    for (final event in document.timeline.events) {
      return event.id;
    }
    for (final segment in document.timeline.chordSegments) {
      return segment.id;
    }
    for (final hotspot in document.hotspots) {
      return hotspot.id;
    }
    return null;
  }

  bool hasEvidence(String id) => _evidenceIds.contains(id);

  EvidenceBackedAnalysisInsight? insight({
    required String ruleId,
    required int ruleVersion,
    required EvidenceInsightPriority priority,
    required EvidenceInsightKind kind,
    required List<String> factIds,
    required List<String> evidenceIds,
    required String messageKey,
    Map<String, String> messageArgs = const <String, String>{},
    required double confidence,
    required RecommendedAnalysisAction recommendedAction,
  }) {
    if (factIds.isEmpty || evidenceIds.isEmpty) return null;
    if (factIds.any((id) => metric(id) == null) ||
        evidenceIds.any((id) => !hasEvidence(id))) {
      return null;
    }
    return EvidenceBackedAnalysisInsight(
      ruleId: ruleId,
      ruleVersion: ruleVersion,
      priority: priority,
      kind: kind,
      factIds: factIds,
      evidenceIds: evidenceIds,
      messageKey: messageKey,
      messageArgs: messageArgs,
      confidence: confidence,
      recommendedAction: recommendedAction,
    );
  }

  Set<String> get _evidenceIds => <String>{
    ...document.timeline.events.map((event) => event.id),
    ...document.timeline.chordSegments.map((segment) => segment.id),
    ...document.hotspots.map((hotspot) => hotspot.id),
  };
}

/// Evidence calculated by a future alignment integration. The rule does not
/// infer these values from a summary metric because that would invent facts.
final class TimingInsightEvidence {
  TimingInsightEvidence({
    required this.firstHalfMeanAbsoluteErrorMs,
    required this.secondHalfMeanAbsoluteErrorMs,
    required List<String> firstHalfMatchedEventIds,
    required List<String> secondHalfMatchedEventIds,
  }) : firstHalfMatchedEventIds = List<String>.unmodifiable(
         firstHalfMatchedEventIds,
       ),
       secondHalfMatchedEventIds = List<String>.unmodifiable(
         secondHalfMatchedEventIds,
       ) {
    if (!firstHalfMeanAbsoluteErrorMs.isFinite ||
        !secondHalfMeanAbsoluteErrorMs.isFinite ||
        firstHalfMeanAbsoluteErrorMs < 0 ||
        secondHalfMeanAbsoluteErrorMs < 0) {
      throw ArgumentError('Timing evidence must be finite and non-negative.');
    }
  }

  final double firstHalfMeanAbsoluteErrorMs;
  final double secondHalfMeanAbsoluteErrorMs;
  final List<String> firstHalfMatchedEventIds;
  final List<String> secondHalfMatchedEventIds;
}

final class StrokeBalanceInsightEvidence {
  StrokeBalanceInsightEvidence({
    required this.targetDownUpMedianRatio,
    required List<String> upstrokeEventIds,
  }) : upstrokeEventIds = List<String>.unmodifiable(upstrokeEventIds) {
    if (!targetDownUpMedianRatio.isFinite || targetDownUpMedianRatio <= 0) {
      throw ArgumentError.value(
        targetDownUpMedianRatio,
        'targetDownUpMedianRatio',
      );
    }
  }

  final double targetDownUpMedianRatio;
  final List<String> upstrokeEventIds;
}

final class PreviousMetricComparison {
  PreviousMetricComparison({
    required this.metricId,
    required this.previousValue,
    required this.currentValue,
    required this.minimumMeaningfulDelta,
    required this.higherIsBetter,
    required List<String> evidenceIds,
  }) : evidenceIds = List<String>.unmodifiable(evidenceIds) {
    if (!previousValue.isFinite ||
        !currentValue.isFinite ||
        !minimumMeaningfulDelta.isFinite ||
        minimumMeaningfulDelta < 0) {
      throw ArgumentError('Comparison values must be finite.');
    }
  }

  final String metricId;
  final double previousValue;
  final double currentValue;
  final double minimumMeaningfulDelta;
  final bool higherIsBetter;
  final List<String> evidenceIds;

  bool get hasMeaningfulImprovement => higherIsBetter
      ? currentValue - previousValue >= minimumMeaningfulDelta
      : previousValue - currentValue >= minimumMeaningfulDelta;
}

abstract interface class AnalysisInsightRule {
  String get id;
  int get version;
  EvidenceInsightPriority get priority;

  EvidenceBackedAnalysisInsight? evaluate(AnalysisInsightContext context);
}

AnalysisHotspot? firstChordTransitionHotspot(AnalysisInsightContext context) {
  final hotspots =
      context.document.hotspots
          .where((hotspot) => hotspot.kind == AnalysisHotspotKind.harmony)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  return hotspots.isEmpty ? null : hotspots.first;
}

bool isPublicMetricId(String id) =>
    AnalysisMetricId.contains(id) && !id.startsWith('technique.');
