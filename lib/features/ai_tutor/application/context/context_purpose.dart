import 'tutor_context_snapshot.dart';

/// The user intent that determines the minimum data exposed to the tutor.
enum ContextPurpose {
  generalQuestion,
  sessionDebrief,
  progressReview,
  practicePlanning,
  songHelp,
  profileUpdate;

  /// Explicit deny-by-default field policy for this request intent.
  Set<TutorContextFieldKey> get allowedFields => switch (this) {
    ContextPurpose.generalQuestion => const {
      TutorContextFieldKey.studentProfile,
      TutorContextFieldKey.guitarProfile,
      TutorContextFieldKey.activeGoals,
      TutorContextFieldKey.skillEvidence,
      TutorContextFieldKey.progress,
      TutorContextFieldKey.settings,
    },
    ContextPurpose.sessionDebrief => const {
      TutorContextFieldKey.studentProfile,
      TutorContextFieldKey.practice,
      TutorContextFieldKey.analyze,
      TutorContextFieldKey.songTrainer,
      TutorContextFieldKey.skillEvidence,
      TutorContextFieldKey.settings,
    },
    ContextPurpose.progressReview => const {
      TutorContextFieldKey.studentProfile,
      TutorContextFieldKey.activeGoals,
      TutorContextFieldKey.skillEvidence,
      TutorContextFieldKey.progress,
      TutorContextFieldKey.streak,
    },
    ContextPurpose.practicePlanning => const {
      TutorContextFieldKey.studentProfile,
      TutorContextFieldKey.guitarProfile,
      TutorContextFieldKey.activeGoals,
      TutorContextFieldKey.skillEvidence,
      TutorContextFieldKey.practice,
      TutorContextFieldKey.progress,
      TutorContextFieldKey.settings,
    },
    ContextPurpose.songHelp => const {
      TutorContextFieldKey.studentProfile,
      TutorContextFieldKey.guitarProfile,
      TutorContextFieldKey.songTrainer,
      TutorContextFieldKey.analyze,
      TutorContextFieldKey.settings,
    },
    ContextPurpose.profileUpdate => const {
      TutorContextFieldKey.studentProfile,
      TutorContextFieldKey.guitarProfile,
      TutorContextFieldKey.activeGoals,
      TutorContextFieldKey.settings,
    },
  };
}
