import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/learner_constraints.dart';
import '../../domain/model/weekly_availability.dart';

/// A compact, semantics-labelled editor for an optional Monday availability.
/// Other unselected days intentionally remain absent, representing unknown.
class AvailabilityEditor extends StatelessWidget {
  const AvailabilityEditor({
    required this.days,
    required this.onChanged,
    required this.referenceDate,
    super.key,
  });

  final List<DailyAvailability> days;
  final ValueChanged<List<DailyAvailability>> onChanged;
  final DateTime referenceDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final monday = _mondayOf(referenceDate);
    final isAvailable = days.any(
      (day) => day.date == monday && day.status == AvailabilityStatus.available,
    );
    return Semantics(
      label: l10n.planSetupMondayAvailability,
      child: SwitchListTile.adaptive(
        key: const Key('plan-availability-monday'),
        title: Text(l10n.planSetupMonday),
        subtitle: Text(
          isAvailable ? l10n.planSetupAvailable : l10n.planSetupUnavailable,
        ),
        value: isAvailable,
        onChanged: (value) => onChanged(
          value
              ? <DailyAvailability>[
                  DailyAvailability(
                    date: monday,
                    status: AvailabilityStatus.available,
                    minimumMinutes: 0,
                    targetMinutes: 20,
                    maximumMinutes: 30,
                    maximumStrength: ConstraintStrength.hard,
                  ),
                ]
              : const <DailyAvailability>[],
        ),
      ),
    );
  }

  static LocalDate _mondayOf(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final monday = startOfDay.subtract(
      Duration(days: date.weekday - DateTime.monday),
    );
    return LocalDate(monday.year, monday.month, monday.day);
  }
}
