import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../controllers/overview_view_model.dart';

/// Recording-quality summary. All numeric values are pre-formatted by the
/// view model — this widget only arranges them into a labelled list and
/// surfaces the user-facing headlines for any domain-published warnings.
final class SignalQualityCard extends StatelessWidget {
  const SignalQualityCard({
    required this.card,
    required this.semanticLabel,
    required this.titleLabel,
    required this.peakTemplate,
    required this.rmsTemplate,
    required this.noiseFloorTemplate,
    required this.clippedTemplate,
    required this.silentTemplate,
    super.key,
  });

  final OverviewSignalQualityCard card;

  /// Title and templates are pre-resolved so the widget stays trivially
  /// testable from fixtures — there is no `AppLocalizations.of` lookup.
  final String semanticLabel;
  final String titleLabel;
  final String peakTemplate;
  final String rmsTemplate;
  final String noiseFloorTemplate;
  final String clippedTemplate;
  final String silentTemplate;

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
                    child: Text(
                      titleLabel,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _row(peakTemplate.replaceAll('{value}', card.peakDbfsText)),
              _row(rmsTemplate.replaceAll('{value}', card.rmsDbfsText)),
              _row(
                noiseFloorTemplate.replaceAll(
                  '{value}',
                  card.noiseFloorDbfsText,
                ),
              ),
              _row(
                clippedTemplate.replaceAll('{value}', card.clippedRatioText),
              ),
              _row(
                silentTemplate.replaceAll('{value}', card.silentRatioText),
              ),
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
      peakTemplate: l10n.analysisOverviewSignalQualityPeak,
      rmsTemplate: l10n.analysisOverviewSignalQualityRms,
      noiseFloorTemplate: l10n.analysisOverviewSignalQualityNoiseFloor,
      clippedTemplate: l10n.analysisOverviewSignalQualityClipped,
      silentTemplate: l10n.analysisOverviewSignalQualitySilent,
    );
  }
}
