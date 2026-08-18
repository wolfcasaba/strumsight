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
    super.key,
  });

  final List<DailyAvailability> days;
  final ValueChanged<List<DailyAvailability>> onChanged;

  static final LocalDate _monday = LocalDate(2026, 8, 17);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAvailable = days.any(
      (day) =>
          day.date == _monday && day.status == AvailabilityStatus.available,
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
                    date: _monday,
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
}
