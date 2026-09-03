/// Tutor Profile screen (E04-R22 §3, design-system migration E15-R09).
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
///
/// The two [TextFormField]s stay plain Material widgets rather than
/// [SsTextField]: this screen rebuilds them on every Riverpod `watch` via
/// `initialValue` (no owned [TextEditingController]), and [SsTextField]'s
/// `TextField`-only API has no `initialValue` — wiring a controller here
/// would mean owning per-keystroke controller state this
/// `ConsumerWidget` (stateless by design) doesn't have today, which is a
/// behaviour change this visual-only round is not scoped to make.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/components/actions/ss_button.dart';
import '../../../../core/design_system/components/surfaces/ss_section.dart';
import '../../../../core/design_system/foundations/ss_colors.dart';
import '../../../../core/design_system/foundations/ss_spacing.dart';
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
            padding: const EdgeInsets.all(SsSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.tutorProfileIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: SsSpacing.space4),
                SsSection(
                  title: l10n.tutorProfileStudentSection,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
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
                        const SizedBox(height: SsSpacing.space2),
                        Text(
                          key: const Key('tutorProfileWeeklyMinutesError'),
                          weeklyErrorText,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).extension<SsColorScheme>()!.danger,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: SsSpacing.space4),
                SsSection(
                  title: l10n.tutorProfileGuitarSection,
                  child: TextFormField(
                    key: const Key('tutorProfileGuitarName'),
                    decoration: InputDecoration(
                      labelText: l10n.tutorProfileGuitarNameLabel,
                    ),
                    initialValue: profile.guitar.name.value,
                    onChanged: profileController.setGuitarName,
                  ),
                ),
                const SizedBox(height: SsSpacing.space4),
                SsSection(
                  title: l10n.tutorProfileGoalsSection,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final goal in goals)
                        ListTile(
                          key: Key('tutorProfileGoal:${goal.id}'),
                          title: Text(goal.statement),
                          trailing: IconButton(
                            key: Key('tutorProfileGoalRemove:${goal.id}'),
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () =>
                                goalsController.removeGoal(goal.id),
                          ),
                        ),
                      const SizedBox(height: SsSpacing.space2),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SsButton(
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
                          icon: Icons.add,
                          label: l10n.tutorProfileAddGoalAction,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
