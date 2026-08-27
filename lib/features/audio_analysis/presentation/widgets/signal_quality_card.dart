import 'package:flutter/material.dart';

import 'package:strumsight/l10n/app_localizations.dart';

import '../../../../core/design_system/public.dart';
import '../controllers/overview_view_model.dart';

/// Recording-quality summary. All numeric values are pre-formatted by the
/// view model — this widget only arranges them into a labelled list and
/// surfaces the user-facing headlines for any domain-published warnings.
final class SignalQualityCard extends StatelessWidget {
  const SignalQualityCard({
    required this.card,
    required this.semanticLabel,
    required this.titleLabel,
    required this.peakValue,
    required this.rmsValue,
    required this.noiseFloorValue,
    required this.clippedValue,
    required this.silentValue,
    required this.peakTemplate,
    required this.rmsTemplate,
    required this.noiseFloorTemplate,
    required this.clippedTemplate,
    required this.silentTemplate,
    required this.overallScoreSemantic,
    super.key,
  });

  final OverviewSignalQualityCard card;

  /// Already-resolved labels and value templates — the widget performs no
  /// `AppLocalizations.of` lookup so tests can drive it from fixtures.
  final String semanticLabel;
  final String titleLabel;
  final String peakValue;
  final String rmsValue;
  final String noiseFloorValue;
  final String clippedValue;
  final String silentValue;
  final String peakTemplate;
  final String rmsTemplate;
  final String noiseFloorTemplate;
  final String clippedTemplate;
  final String silentTemplate;
  final String overallScoreSemantic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          container: true,
          label: semanticLabel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.graphic_eq,
                    size: 18,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(titleLabel, style: theme.textTheme.titleSmall),
                  ),
                  SsScoreRing(
                    state: card.overallMeasured
                        ? SsScoreRingState.measured
                        : SsScoreRingState.unavailable,
                    ratio: card.overallRatio,
                    label: card.overallScoreText,
                    semanticLabel: overallScoreSemantic,
                    size: 32,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _row(peakTemplate.replaceAll('{value}', peakValue)),
              _row(rmsTemplate.replaceAll('{value}', rmsValue)),
              _row(noiseFloorTemplate.replaceAll('{value}', noiseFloorValue)),
              _row(clippedTemplate.replaceAll('{value}', clippedValue)),
              _row(silentTemplate.replaceAll('{value}', silentValue)),
              if (card.warningHeadlines.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                for (final headline in card.warningHeadlines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.warning_amber_outlined, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            headline,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text),
    );
  }
}

/// Convenience builder that resolves every label through
/// [AppLocalizations]. Wrap the widget tree in a [Builder] when using this
/// factory; the helper exists purely to keep call sites short.
class SignalQualityCardFromL10n extends StatelessWidget {
  const SignalQualityCardFromL10n({required this.card, super.key});

  final OverviewSignalQualityCard card;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SignalQualityCard(
      card: card,
      semanticLabel: l10n.analysisOverviewSignalQualitySemantic,
      titleLabel: l10n.analysisOverviewSignalQualityTitle,
      peakValue: card.peakDbfsText,
      rmsValue: card.rmsDbfsText,
      noiseFloorValue: card.noiseFloorDbfsText,
      clippedValue: card.clippedRatioText,
      silentValue: card.silentRatioText,
      peakTemplate: l10n.analysisOverviewSignalQualityPeak('{value}'),
      rmsTemplate: l10n.analysisOverviewSignalQualityRms('{value}'),
      noiseFloorTemplate: l10n.analysisOverviewSignalQualityNoiseFloor(
        '{value}',
      ),
      clippedTemplate: l10n.analysisOverviewSignalQualityClipped('{value}'),
      silentTemplate: l10n.analysisOverviewSignalQualitySilent('{value}'),
      overallScoreSemantic: l10n.analysisOverviewSignalQualityScoreSemantic(
        card.overallScoreText,
      ),
    );
  }
}
