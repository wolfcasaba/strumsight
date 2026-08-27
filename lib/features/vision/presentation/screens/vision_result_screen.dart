import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/feedback/insight_code.dart';
import '../../domain/vision_session_result.dart';
import '../theme/vision_theme_scope.dart';

/// UI-47 Vision Result, composed inline from `VisionSessionScreen` when a
/// session reaches [VisionSessionStatus.completed] — this feature has no
/// registered route (§0.0/B10: `lib/app/routing/` is out of this round's
/// scope; the SDD's `/coach/vision/result/:sessionId` route is left for a
/// later routing round).
///
/// Never renders a categorical technique verdict for a low-confidence
/// insight (A4): below [lowConfidenceThreshold] the neutral
/// [AppLocalizations.visionResultLowConfidenceMetric] replaces the
/// insight's own stable/focus/improved wording.
class VisionResultScreen extends StatelessWidget {
  const VisionResultScreen({
    required this.result,
    required this.onStartCorrectivePractice,
    super.key,
  });

  final VisionSessionResult result;
  final VoidCallback onStartCorrectivePractice;

  /// Below this confidence, an insight's categorical wording is withheld
  /// (A4). A presentation-only constant — evidence-side thresholds live in
  /// `domain/feedback/feedback_policy.dart`, unrelated to this decision.
  static const double lowConfidenceThreshold = 0.5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VisionThemeScope(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.visionResultTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.visionResultFrameRetentionNotSaved,
              key: const Key('vision-result-frame-retention'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SsMetricCard(
                  label: l10n.visionResultDurationLabel,
                  value: result.duration.inMinutes,
                  unit: l10n.visionResultDurationUnit,
                ),
                const SizedBox(width: 12),
                SsMetricCard(
                  label: l10n.visionResultFramesObservedLabel,
                  value: result.observedFrameCount,
                  unit: l10n.visionResultFramesUnit,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SsSection(
              title: l10n.visionResultMetricsTitle,
              child: result.sessionSummary.isEmpty
                  ? Text(
                      l10n.visionResultNoInsights,
                      key: const Key('vision-result-no-insights'),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final insight in result.sessionSummary)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _InsightTile(l10n: l10n, insight: insight),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            // Feature-local, not `SsConfidenceLegend` (§0.0/B5 fallback
            // rule): that component's entries lay out as an unbreakable
            // `Row` inside a `Wrap`, which overflows once a localized label
            // ("Közepes megbízhatóság") no longer fits one line at a large
            // text scale (measured while writing this round's A9 golden).
            // Each row here uses `Expanded` so its label wraps instead.
            _ConfidenceLegend(
              title: l10n.visionResultConfidenceLegendTitle,
              entries: [
                (Icons.check_circle_outline, l10n.dsStatusBadgeConfidenceHigh),
                (
                  Icons.remove_circle_outline,
                  l10n.dsStatusBadgeConfidenceMedium,
                ),
                (Icons.error_outline, l10n.dsStatusBadgeConfidenceLow),
              ],
            ),
            const SizedBox(height: 16),
            SsCoachActionCard(
              l10n: l10n,
              title: l10n.visionResultPrimaryActionTitle,
              message: l10n.visionResultPrimaryActionMessage,
              actionLabel: l10n.visionResultPrimaryAction,
              onAction: onStartCorrectivePractice,
              provenance: SsProvenanceKind.local,
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.l10n, required this.insight});

  final AppLocalizations l10n;
  final VisionInsight insight;

  @override
  Widget build(BuildContext context) {
    final isLowConfidence =
        insight.confidence < VisionResultScreen.lowConfidenceThreshold;
    final message = isLowConfidence
        ? l10n.visionResultLowConfidenceMetric
        : _categoricalMessage(l10n, insight.code);
    final tier = insight.confidence >= 0.7
        ? SsStatusBadgeKind.confidenceHigh
        : insight.confidence >= VisionResultScreen.lowConfidenceThreshold
        ? SsStatusBadgeKind.confidenceMedium
        : SsStatusBadgeKind.confidenceLow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SsInsightCard(
          l10n: l10n,
          title: _category(l10n, insight.code),
          message: message,
          provenance: SsProvenanceKind.local,
        ),
        const SizedBox(height: 4),
        SsStatusBadge(l10n: l10n, kind: tier),
      ],
    );
  }

  static String _category(AppLocalizations l10n, InsightCode code) =>
      switch (code) {
        InsightCode.frettingStable ||
        InsightCode.frettingFocus ||
        InsightCode.frettingImproved => l10n.visionResultCategoryFretting,
        InsightCode.pickingStable ||
        InsightCode.pickingFocus ||
        InsightCode.pickingImproved => l10n.visionResultCategoryPicking,
        InsightCode.postureStable ||
        InsightCode.postureFocus ||
        InsightCode.postureImproved => l10n.visionResultCategoryPosture,
        InsightCode.setupNotObservable => l10n.visionResultCategorySetup,
        InsightCode.experimentalObservation =>
          l10n.visionResultCategoryExperimental,
      };

  static String _categoricalMessage(AppLocalizations l10n, InsightCode code) =>
      switch (code) {
        InsightCode.setupNotObservable => l10n.visionInsightSetupNotObservable,
        InsightCode.frettingStable => l10n.visionInsightFrettingStable,
        InsightCode.frettingFocus => l10n.visionInsightFrettingFocus,
        InsightCode.frettingImproved => l10n.visionInsightFrettingImproved,
        InsightCode.pickingStable => l10n.visionInsightPickingStable,
        InsightCode.pickingFocus => l10n.visionInsightPickingFocus,
        InsightCode.pickingImproved => l10n.visionInsightPickingImproved,
        InsightCode.postureStable => l10n.visionInsightPostureStable,
        InsightCode.postureFocus => l10n.visionInsightPostureFocus,
        InsightCode.postureImproved => l10n.visionInsightPostureImproved,
        InsightCode.experimentalObservation =>
          l10n.visionInsightExperimentalObservation,
      };
}

class _ConfidenceLegend extends StatelessWidget {
  const _ConfidenceLegend({required this.title, required this.entries});

  final String title;
  final List<(IconData, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          for (final (icon, label) in entries)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 14, color: theme.colorScheme.onSurface),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(label, style: theme.textTheme.labelSmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
