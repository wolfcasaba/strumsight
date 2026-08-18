import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_goal.dart';

/// Goal choices for the first setup step, including an explicit unknown value.
class PracticeGoalPicker extends StatelessWidget {
  const PracticeGoalPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final PracticeGoalType? selected;
  final ValueChanged<PracticeGoalType?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RadioGroup<PracticeGoalType>(
      groupValue: selected,
      onChanged: onChanged,
      child: Column(
        children: [
          RadioListTile<PracticeGoalType>(
            key: const Key('plan-goal-rhythm'),
            value: PracticeGoalType.rhythm,
            title: Text(l10n.planSetupGoalRhythm),
          ),
          RadioListTile<PracticeGoalType>(
            key: const Key('plan-goal-custom'),
            value: PracticeGoalType.custom,
            title: Text(l10n.planSetupGoalCustom),
          ),
          TextButton(
            key: const Key('plan-goal-unknown'),
            onPressed: () => onChanged(null),
            child: Text(l10n.planSetupUnknown),
          ),
        ],
      ),
    );
  }
}
