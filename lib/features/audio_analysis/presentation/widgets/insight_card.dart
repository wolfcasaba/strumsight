import 'package:flutter/material.dart';

import '../../domain/analysis_insight.dart';
import '../controllers/overview_view_model.dart';

/// Single insight card.
///
/// R22 (audit MI3): the action button is LIVE whenever the caller wires
/// [onAction]. The perzisztált document keeps only the coarse
/// [AnalysisRecommendedAction] — not the rule's full payload — which is
/// still enough to reach the tool the insight asks for
/// (`presentation/insight_action_route.dart`). A caller with no destination
/// to offer leaves [onAction] null; the button then stays disabled behind
/// the [OverviewInsightCard.actionTooltip] explanation instead of
/// pretending to act.
final class InsightCard extends StatelessWidget {
  const InsightCard({required this.card, this.onAction, super.key});

  final OverviewInsightCard card;

  /// Invoked with [OverviewInsightCard.action] when the CTA is tapped.
  /// `null` keeps the CTA disabled and tooltip-explained.
  final ValueChanged<AnalysisRecommendedAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onAction = this.onAction;
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
              if (onAction == null)
                Tooltip(
                  message: card.actionTooltip,
                  child: OutlinedButton(
                    onPressed: null,
                    child: Text(card.actionLabel),
                  ),
                )
              else
                OutlinedButton(
                  key: Key('insight-action-${card.action.name}'),
                  onPressed: () => onAction(card.action),
                  child: Text(card.actionLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
