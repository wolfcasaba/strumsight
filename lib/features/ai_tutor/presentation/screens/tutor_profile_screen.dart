/// Tutor Profile screen (E04-R22 §3).
///
/// Edits the in-memory `StudentProfile` and `GuitarProfile` pair held by
/// [tutorProfileControllerProvider], and the `LearningGoal` list held by
/// [tutorLearningGoalControllerProvider]. All mutations go through the
/// models' own validators — invalid input (e.g. weekly minutes outside
/// the supported range) is captured into `TutorProfileState.lastValidationCode`
/// and the screen surfaces a localized error message.
///
/// Pure presentation: no persistence, no networking, no domain work
/// beyond the model's own constructor + helpers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/learning_goal.dart';
import '../../domain/models/student_profile.dart';
import '../providers/tutor_privacy_providers.dart';

class TutorProfileScreen extends ConsumerWidget {
  const TutorProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(tutorProfileControllerProvider);
    final goals = ref.watch(tutorLearningGoalControllerProvider);
    final profileController = ref.read(tutorProfileControllerProvider.notifier);
    final goalsController = ref.read(
      tutorLearningGoalControllerProvider.notifier,
    );

    final weeklyErrorText = switch (profile.lastValidationCode) {
      StudentProfileValidationCode.weeklyPracticeMinutesOutOfRange =>
        l10n.tutorProfileWeeklyMinutesOutOfRange,
      _ when profile.lastValidationCode != null =>
        l10n.tutorProfileValidationFailed,
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tutorProfileTitle)),
      body: SafeArea(
        child: Semantics(
          container: true,
          label: l10n.tutorProfileScreenSemantics,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.tutorProfileIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.tutorProfileStudentSection,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('tutorProfileWeeklyMinutes'),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.tutorProfileWeeklyMinutesLabel,
                    helperText: l10n.tutorProfileWeeklyMinutesHelper,
                  ),
                  initialValue:
                      (profile.student.weeklyPracticeMinutes.value ?? '')
                          .toString(),
                  onChanged: (raw) {
                    final value = int.tryParse(raw);
                    profileController.setWeeklyMinutes(value);
                  },
                ),
                if (weeklyErrorText != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    key: const Key('tutorProfileWeeklyMinutesError'),
                    weeklyErrorText,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  l10n.tutorProfileGuitarSection,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('tutorProfileGuitarName'),
                  decoration: InputDecoration(
                    labelText: l10n.tutorProfileGuitarNameLabel,
                  ),
                  initialValue: profile.guitar.name.value,
                  onChanged: profileController.setGuitarName,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.tutorProfileGoalsSection,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final goal in goals)
                  ListTile(
                    key: Key('tutorProfileGoal:${goal.id}'),
                    title: Text(goal.statement),
                    trailing: IconButton(
                      key: Key('tutorProfileGoalRemove:${goal.id}'),
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => goalsController.removeGoal(goal.id),
                    ),
                  ),
                FilledButton.icon(
                  key: const Key('tutorProfileAddGoal'),
                  onPressed: () {
                    final now = DateTime.now().toUtc();
                    final id = 'g-${now.microsecondsSinceEpoch}';
                    goalsController.addGoal(
                      LearningGoal(
                        id: id,
                        statement: l10n.tutorProfileNewGoalPlaceholder,
                        category: LearningGoalCategory.improveRhythm,
                        priority: LearningGoalPriority.medium,
                        status: LearningGoalStatus.active,
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: Text(l10n.tutorProfileAddGoalAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
