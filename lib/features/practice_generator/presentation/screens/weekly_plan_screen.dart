import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
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
      final colors = Theme.of(context).extension<SsColorScheme>()!;
      final typography = Theme.of(context).extension<SsTypography>()!;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.weeklyPlanTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(SsSpacing.space6),
            child: Text(
              l10n.todayPlanEmptyBody,
              textAlign: TextAlign.center,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.weeklyPlanTitle)),
      body: ListView.separated(
        padding: const EdgeInsets.all(SsSpacing.space4),
        itemCount: plan!.days.length,
        separatorBuilder: (_, _) => const SizedBox(height: SsSpacing.space2),
        itemBuilder: (context, index) {
          final day = plan!.days[index];
          return _WeeklyDayCard(
            key: Key('weekly-plan-day-${day.id.value}'),
            day: day,
            isToday: day.localDate == today,
            l10n: l10n,
          );
        },
      ),
    );
  }
}

/// A single day row — icon, date + status label, remaining time budget.
/// Kept as a hand-styled [Container] (not [SsContentCard]): the row shows
/// THREE independent pieces of information (date, status label, minutes)
/// that the legacy `ListTile` kept visually distinct via title/subtitle/
/// trailing; `SsContentCard` only exposes title+message, so folding the
/// status label and the minute count into one string would blur two
/// currently-separate facts (§5.1 — no information loss).
class _WeeklyDayCard extends StatelessWidget {
  const _WeeklyDayCard({
    super.key,
    required this.day,
    required this.isToday,
    required this.l10n,
  });

  final PracticeDay day;
  final bool isToday;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Container(
      decoration: BoxDecoration(
        color: isToday ? colors.brand.withValues(alpha: 0.12) : colors.surface,
        borderRadius: BorderRadius.circular(SsRadius.md),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(SsSpacing.space4),
      child: Row(
        children: [
          Icon(
            _dayIcon(day),
            color: colors.textSecondary,
            semanticLabel: _daySemanticLabel(l10n, day),
          ),
          const SizedBox(width: SsSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.localDate.toString(),
                  style: typography.titleMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: SsSpacing.space1),
                Text(
                  _dayLabel(l10n, day),
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: SsSpacing.space2),
          Text(
            '${day.timeBudget.inMinutes}m',
            style: typography.labelLarge.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

IconData _dayIcon(PracticeDay day) {
  if (day.reasonCodes.contains(ScheduleDecisionReason.restDay.code)) {
    return Icons.bedtime_outlined;
  }
  if (day.reasonCodes.contains(ScheduleDecisionReason.dayUnavailable.code)) {
    return Icons.event_busy_outlined;
  }
  if (day.status == PracticeItemStatus.completed) {
    return Icons.check_circle_outline;
  }
  return Icons.event_note_outlined;
}

String _daySemanticLabel(AppLocalizations l10n, PracticeDay day) {
  if (day.reasonCodes.contains(ScheduleDecisionReason.restDay.code)) {
    return l10n.practicePlanStatusRestLabel;
  }
  if (day.reasonCodes.contains(ScheduleDecisionReason.dayUnavailable.code)) {
    return l10n.practicePlanStatusUnavailableLabel;
  }
  if (day.status == PracticeItemStatus.completed) {
    return l10n.practicePlanStatusCompletedLabel;
  }
  return l10n.practicePlanStatusPlannedLabel;
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
