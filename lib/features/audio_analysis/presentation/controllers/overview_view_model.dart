import 'package:meta/meta.dart';

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_document.dart';
import '../../domain/analysis_insight.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/analysis_warning.dart';
import '../../domain/insights/insight_rule.dart';
import '../../domain/signal_quality_report.dart';

/// Five-state presentation view of one metric — bounded to the SDD §25.5
/// surface. The fifth (`lowConfidence`) is a UI specialization of the
/// domain-published `unavailable + confidenceTooLow` pair, NOT a separate
/// confidence computation. All states carry a non-empty text label so the
/// screen never encodes status with colour alone.
enum OverviewMetricCardState {
  available,
  degraded,
  unavailable,
  lowConfidence,
  notApplicable,
}

/// Formatted metric card content for the overview screen.
///
/// All fields are immutable; the view model produces one of these per
/// metric, plus a list of warnings when the domain published any.
@immutable
final class OverviewMetricCard {
  const OverviewMetricCard({
    required this.metricId,
    required this.metricLabel,
    required this.unit,
    required this.state,
    required this.valueText,
    required this.confidence,
    required this.statusLabel,
    required this.reasonText,
    required this.tipText,
    required this.isUsable,
  });

  final String metricId;
  final String metricLabel;
  final String unit;
  final OverviewMetricCardState state;

  /// Localised, pre-formatted value (e.g. "82 ms" / "67%" / "—"). Never an
  /// empty string; the unavailable and notApplicable states always render
  /// a placeholder dash.
  final String valueText;

  /// Raw 0..1 confidence as published by the domain. The card displays this
  /// only as a numeric Lab-mode label; the default user view maps the value
  /// to a three-step textual scale via [statusLabel].
  final double confidence;

  /// Human-readable status label such as "Magas megbízhatóság" / "Közepes
  /// megbízhatóság" / "Bizonytalan mérés" / "Nem mérhető" / "Nem elérhető".
  /// Always non-empty — never colour-only.
  final String statusLabel;

  /// Short explanation shown for unavailable/lowConfidence: the reason the
  /// domain published. Empty string for available/degraded/notApplicable.
  final String reasonText;

  /// Single-line actionable advice that pairs with [reasonText]. Empty
  /// string for available/degraded/notApplicable. Never null so tests can
  /// assert without null-checks.
  final String tipText;

  /// Domain truth: a metric is usable when its status is available or
  /// degraded AND a non-null value is published. The presentation never
  /// re-evaluates this — the screen consumes it verbatim.
  final bool isUsable;
}

/// One primary insight slot, mapped from the insight list. At most four
/// slots render (improvement, strength, nextAction, qualityWarning); the
/// rest are accessible via [OverviewViewModel.details].
@immutable
final class OverviewInsightCard {
  const OverviewInsightCard({
    required this.title,
    required this.body,
    required this.kindLabel,
    required this.actionLabel,
    required this.actionTooltip,
  });

  final String title;
  final String body;
  final String kindLabel;
  final String actionLabel;

  /// Explanation shown when the action is disabled — the overview never
  /// performs an action because the perzisztált document carries only the
  /// coarse [AnalysisRecommendedAction] enum and not the full
  /// [RecommendedAnalysisAction] payload the rule produced.
  final String actionTooltip;
}

/// Aggregated signal-quality card content. The values are formatted from
/// [SignalQualityReport] in pure presentation units; the domain never
  /// produces a percent or "good/bad" verdict for this card.
@immutable
final class OverviewSignalQualityCard {
  const OverviewSignalQualityCard({
    required this.peakDbfsText,
    required this.rmsDbfsText,
    required this.noiseFloorDbfsText,
    required this.clippedRatioText,
    required this.silentRatioText,
    required this.warningHeadlines,
  });

  final String peakDbfsText;
  final String rmsDbfsText;
  final String noiseFloorDbfsText;
  final String clippedRatioText;
  final String silentRatioText;

  /// User-facing headlines for the worst [AnalysisWarning]s the domain
  /// published. Empty when the input was clean.
  final List<String> warningHeadlines;
}

/// Input-summary row used by the overview header. Never includes raw audio
/// paths or fingerprints.
@immutable
final class OverviewHeader {
  const OverviewHeader({
    required this.title,
    required this.subtitle,
    required this.durationText,
    required this.completionLabel,
  });

  final String title;
  final String subtitle;
  final String durationText;
  final String completionLabel;
}

/// Pure presentation view of one [AnalysisDocument]. The view model is
/// **formatting only**: it reads the document, groups metrics, picks one
/// metric per category, and formats numbers and confidence. It NEVER
/// compares confidence against a threshold — every state comes from the
/// domain-published [CapabilityStatus] (and for the fifth state, from the
/// `unavailable + confidenceTooLow` reason published by the domain).
@immutable
final class OverviewViewModel {
  const OverviewViewModel._({
    required this.header,
    required this.signalQuality,
    required this.primaryMetrics,
    required this.insights,
    required this.details,
  });

  final OverviewHeader header;
  final OverviewSignalQualityCard signalQuality;
  final List<OverviewMetricCard> primaryMetrics;
  final List<OverviewInsightCard> insights;

  /// All metric cards (every published metric, not just the four primary
  /// ones). The detail screen reads this verbatim.
  final List<OverviewMetricCard> details;

  /// Build a view model from a domain document. The [labels] callback
  /// resolves all localised strings; the formatter itself contains zero
  /// string literals so test fixtures can drive it deterministically.
  factory OverviewViewModel.from(
    AnalysisDocument document, {
    required OverviewLabels labels,
  }) {
    final header = OverviewHeader(
      title: labels.overviewTitle(document),
      subtitle: labels.inputSubtitle(document.input),
      durationText: labels.formatDuration(document.timeline.duration),
      completionLabel: labels.completionLabel(document.completion),
    );

    final signalQuality = OverviewSignalQualityCard(
      peakDbfsText: labels.formatDbfs(document.signalQuality.peakDbfs),
      rmsDbfsText: labels.formatDbfs(document.signalQuality.rmsDbfs),
      noiseFloorDbfsText: labels.formatDbfs(
        document.signalQuality.noiseFloorDbfs,
      ),
      clippedRatioText: labels.formatRatio(
        document.signalQuality.clippedSampleRatio,
      ),
      silentRatioText: labels.formatRatio(document.signalQuality.silentRatio),
      warningHeadlines: <String>[
        for (final warning in document.signalQuality.warnings)
          if (warning.severity == AnalysisWarningSeverity.warning ||
              warning.severity == AnalysisWarningSeverity.error)
            labels.warningHeadline(warning),
      ],
    );

    final allCards = <OverviewMetricCard>[
      for (final metric in document.metrics) _formatMetric(metric, labels),
    ];

    final primaryIds = _primaryMetricIds();
    final primaryMetrics = <OverviewMetricCard>[
      for (final id in primaryIds)
        if (allCards.any((card) => card.metricId == id))
          allCards.firstWhere((card) => card.metricId == id),
    ];

    final insights = _formatInsights(document, labels);

    return OverviewViewModel._(
      header: header,
      signalQuality: signalQuality,
      primaryMetrics: primaryMetrics,
      insights: insights,
      details: allCards,
    );
  }

  static List<String> _primaryMetricIds() => <String>[
    AnalysisMetricId.timingMeanAbsoluteError,
    AnalysisMetricId.rhythmRushDragBias,
    AnalysisMetricId.dynamicsStrokeStrengthCv,
    AnalysisMetricId.harmonyChordCoverage,
  ];

  static OverviewMetricCard _formatMetric(
    AnalysisMetricResult metric,
    OverviewLabels labels,
  ) {
    final state = _stateForMetric(metric);
    final valueText = switch (metric.status) {
      CapabilityStatus.notApplicable => labels.notApplicableValuePlaceholder,
      CapabilityStatus.unavailable => labels.unavailableValuePlaceholder,
      _ => labels.formatMetricValue(metric),
    };
    final statusLabel = _statusLabel(state, labels);
    final reasonText =
        state == OverviewMetricCardState.unavailable ||
            state == OverviewMetricCardState.lowConfidence
        ? labels.unavailableReason(metric.unavailableReason!)
        : '';
    final tipText =
        state == OverviewMetricCardState.unavailable ||
            state == OverviewMetricCardState.lowConfidence
        ? labels.unavailableTip(metric.unavailableReason!)
        : '';
    return OverviewMetricCard(
      metricId: metric.id,
      metricLabel: labels.metricLabel(metric.id),
      unit: metric.unit,
      state: state,
      valueText: valueText,
      confidence: metric.confidence,
      statusLabel: statusLabel,
      reasonText: reasonText,
      tipText: tipText,
      isUsable:
          metric.value != null &&
          (metric.status == CapabilityStatus.available ||
              metric.status == CapabilityStatus.degraded),
    );
  }

  /// Map a domain [CapabilityStatus] to the presentation card state.
  ///
  /// The fifth state (`lowConfidence`) is triggered by the exact domain
  /// reason [CapabilityUnavailableReason.confidenceTooLow] — the presentation
  /// never compares the confidence number against a threshold.
  static OverviewMetricCardState _stateForMetric(AnalysisMetricResult metric) {
    if (metric.status == CapabilityStatus.notApplicable) {
      return OverviewMetricCardState.notApplicable;
    }
    if (metric.status == CapabilityStatus.available) {
      return OverviewMetricCardState.available;
    }
    if (metric.status == CapabilityStatus.degraded) {
      return OverviewMetricCardState.degraded;
    }
    if (metric.unavailableReason ==
        CapabilityUnavailableReason.confidenceTooLow) {
      return OverviewMetricCardState.lowConfidence;
    }
    return OverviewMetricCardState.unavailable;
  }

  static String _statusLabel(
    OverviewMetricCardState state,
    OverviewLabels labels,
  ) {
    return switch (state) {
      OverviewMetricCardState.available => labels.confidenceHigh(),
      OverviewMetricCardState.degraded => labels.confidenceMedium(),
      OverviewMetricCardState.lowConfidence => labels.confidenceLow(),
      OverviewMetricCardState.notApplicable => labels.notApplicableStatusLabel(),
      OverviewMetricCardState.unavailable => labels.unavailableStatusLabel(),
    };
  }

  static List<OverviewInsightCard> _formatInsights(
    AnalysisDocument document,
    OverviewLabels labels,
  ) {
    // Maximum-policy slot allocation (SDD §25.6): improvement, strength,
    // nextAction, qualityWarning — one per slot. The first item of each
    // kind wins; ties resolve by ruleId ascending.
    final byKind = <AnalysisInsightKind, AnalysisInsight?>{
      AnalysisInsightKind.observation: null,
      AnalysisInsightKind.recommendation: null,
      AnalysisInsightKind.caution: null,
    };
    for (final insight in document.insights) {
      byKind.putIfAbsent(insight.kind, () => null);
      if (byKind[insight.kind] == null) {
        byKind[insight.kind] = insight;
      }
    }
    final slots = <(AnalysisInsightKind, AnalysisInsight?)>[
      (AnalysisInsightKind.recommendation, byKind[AnalysisInsightKind.recommendation]),
      (AnalysisInsightKind.observation, byKind[AnalysisInsightKind.observation]),
      (AnalysisInsightKind.recommendation, _nextAlternate(byKind[AnalysisInsightKind.recommendation], document)),
      (AnalysisInsightKind.caution, byKind[AnalysisInsightKind.caution]),
    ];
    return <OverviewInsightCard>[
      for (final (kind, insight) in slots)
        if (insight != null) _formatInsight(insight, kind, labels),
    ];
  }

  static AnalysisInsight? _nextAlternate(
    AnalysisInsight? first,
    AnalysisDocument document,
  ) {
    if (first == null) return null;
    for (final insight in document.insights) {
      if (insight.id != first.id) return insight;
    }
    return null;
  }

  static OverviewInsightCard _formatInsight(
    AnalysisInsight insight,
    AnalysisInsightKind kind,
    OverviewLabels labels,
  ) {
    final body = labels.insightMessage(insight.messageKey, insight.messageArgs);
    return OverviewInsightCard(
      title: labels.insightKindTitle(kind),
      body: body,
      kindLabel: labels.insightKindLabel(kind),
      actionLabel: labels.actionLabel(insight.recommendedAction),
      actionTooltip: labels.actionDisabledTooltip(insight.recommendedAction),
    );
  }
}

/// Callback surface the formatter uses to resolve every localised string
/// and number format. Implementations live in the presentation layer
/// (typically a thin shim around `AppLocalizations`); the formatter never
/// touches `intl`, `AppLocalizations`, or any locale directly.
abstract interface class OverviewLabels {
  String overviewTitle(AnalysisDocument document);
  String inputSubtitle(AnalysisInputSummary input);
  String formatDuration(Duration duration);
  String completionLabel(AnalysisCompletion completion);

  String formatDbfs(double dbfs);
  String formatRatio(double ratio);

  String formatMetricValue(AnalysisMetricResult metric);
  String metricLabel(String metricId);

  String confidenceHigh();
  String confidenceMedium();
  String confidenceLow();
  String notApplicableStatusLabel();
  String notApplicableValuePlaceholder();
  String unavailableStatusLabel();
  String unavailableValuePlaceholder();

  String unavailableReason(CapabilityUnavailableReason reason);
  String unavailableTip(CapabilityUnavailableReason reason);
  String warningHeadline(AnalysisWarning warning);

  String insightMessage(String messageKey, Map<String, String> args);
  String insightKindLabel(AnalysisInsightKind kind);
  String insightKindTitle(AnalysisInsightKind kind);

  String actionLabel(AnalysisRecommendedAction action);
  String actionDisabledTooltip(AnalysisRecommendedAction action);
}
