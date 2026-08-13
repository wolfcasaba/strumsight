import '../../domain/analysis_capability.dart';
import '../../domain/analysis_document.dart';
import '../../domain/analysis_insight.dart';
import '../../domain/analysis_metric.dart';

/// One metric published on the share card. Never built from an
/// [CapabilityStatus.unavailable] metric — `unavailable` is never a
/// value-shaped fact (ADR 0201).
final class ShareCardMetric {
  const ShareCardMetric({
    required this.metricId,
    required this.value,
    required this.unit,
    required this.isDegraded,
  });

  final String metricId;
  final AnalysisMetricValue value;
  final String unit;

  /// True when the source metric's status is [CapabilityStatus.degraded] —
  /// the card must mark this rather than presenting it as a plain fact.
  final bool isDegraded;
}

/// The single highlighted insight, if any. Only ever built from a
/// [AnalysisInsightKind.observation] or [AnalysisInsightKind.recommendation]
/// — never [AnalysisInsightKind.caution] (SDD §27.5 OD-03: no insight beats
/// a negative one).
final class ShareCardInsight {
  ShareCardInsight({
    required this.messageKey,
    Map<String, String> messageArgs = const <String, String>{},
    required this.priority,
  }) : messageArgs = Map<String, String>.unmodifiable(messageArgs);

  final String messageKey;
  final Map<String, String> messageArgs;
  final AnalysisInsightPriority priority;
}

/// Structured share-card content (OD-02: structured data + localised text,
/// not a rendered image, in this round).
final class ShareCardContent {
  ShareCardContent({required List<ShareCardMetric> metrics, this.insight})
    : metrics = List<ShareCardMetric>.unmodifiable(metrics);

  final List<ShareCardMetric> metrics;
  final ShareCardInsight? insight;
}

/// Builds the share-card content from a full [AnalysisDocument] — never
/// from the already-redacted [AnalysisExport], so a future card layout
/// change cannot accidentally widen the export allowlist.
final class ShareCardBuilder {
  const ShareCardBuilder();

  /// Below this confidence, a metric is never shown as an unqualified fact
  /// (ADR 0201, review MAJOR — [AnalysisMetricResult] permits
  /// [CapabilityStatus.available] at any confidence, including zero, so this
  /// builder cannot trust `status` alone). Matches the engine's own
  /// `minimumDegradedConfidence` floor (`capability_thresholds.dart`) — a
  /// metric this uncertain is marked exactly like a [CapabilityStatus
  /// .degraded] one, never presented plainly.
  static const double _minPlainFactConfidence = 0.4;

  ShareCardContent build(AnalysisDocument document) {
    final metrics = <ShareCardMetric>[
      for (final metric in document.metrics)
        if (_isPublishable(metric))
          ShareCardMetric(
            metricId: metric.id,
            value: metric.value!,
            unit: metric.unit,
            isDegraded:
                metric.status == CapabilityStatus.degraded ||
                metric.confidence < _minPlainFactConfidence,
          ),
    ];

    final candidates =
        document.insights
            .where((insight) => insight.kind != AnalysisInsightKind.caution)
            .toList()
          ..sort((a, b) => _rank(b.priority).compareTo(_rank(a.priority)));

    return ShareCardContent(
      metrics: metrics,
      insight: candidates.isEmpty
          ? null
          : ShareCardInsight(
              messageKey: candidates.first.messageKey,
              messageArgs: candidates.first.messageArgs,
              priority: candidates.first.priority,
            ),
    );
  }

  bool _isPublishable(AnalysisMetricResult metric) =>
      (metric.status == CapabilityStatus.available ||
          metric.status == CapabilityStatus.degraded) &&
      metric.value != null;

  static int _rank(AnalysisInsightPriority priority) => switch (priority) {
    AnalysisInsightPriority.high => 2,
    AnalysisInsightPriority.medium => 1,
    AnalysisInsightPriority.low => 0,
  };
}
