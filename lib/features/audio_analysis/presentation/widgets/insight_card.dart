import 'package:flutter/material.dart';

import '../controllers/overview_view_model.dart';

/// Single insight card. The action button is intentionally **disabled** —
/// the perzisztált document only carries the coarse [AnalysisRecommendedAction]
/// enum and not the full [RecommendedAnalysisAction] payload the rule
/// produced, so the overview cannot navigate or perform anything yet
/// (brief §5 döntés 7). The [actionTooltip] explains the disabled state.
final class InsightCard extends StatelessWidget {
  const InsightCard({required this.card, super.key});

  final OverviewInsightCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          container: true,
          label: '${card.kindLabel}: ${card.body}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      card.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(card.body, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Tooltip(
                message: card.actionTooltip,
                child: OutlinedButton(
                  onPressed: null,
                  child: Text(card.actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
