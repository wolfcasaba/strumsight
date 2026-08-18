import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/adaptive_practice_plan.dart';
import '../../domain/model/practice_block.dart';
import '../../domain/model/practice_day.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/policy/scheduling_policy.dart';

/// A compact week projection which keeps rest, unavailable and completed days
/// distinct from a learner-missed session.
class WeeklyPlanScreen extends StatelessWidget {
  const WeeklyPlanScreen({required this.plan, required this.today, super.key});

  final AdaptivePracticePlan? plan;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (plan == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.weeklyPlanTitle)),
        body: Center(child: Text(l10n.todayPlanEmptyBody)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.weeklyPlanTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final day in plan!.days)
            Card(
              key: Key('weekly-plan-day-${day.id.value}'),
              color: day.localDate == today
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : null,
              child: ListTile(
                title: Text(day.localDate.toString()),
                subtitle: Text(_dayLabel(l10n, day)),
                trailing: Text('${day.timeBudget.inMinutes}m'),
              ),
            ),
        ],
      ),
    );
  }
}

String _dayLabel(AppLocalizations l10n, PracticeDay day) {
  if (day.reasonCodes.contains(ScheduleDecisionReason.restDay.code)) {
    return l10n.todayPlanRestTitle;
  }
  if (day.reasonCodes.contains(ScheduleDecisionReason.dayUnavailable.code)) {
    return l10n.todayPlanUnavailableTitle;
  }
  if (day.status == PracticeItemStatus.completed) {
    return l10n.todayPlanCompletedTitle;
  }
  return l10n.weeklyPlanScheduled(day.blocks.length);
}
