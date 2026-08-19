/// Shared, deliberately small inputs for PlannerAssist boundary tests.
library;

import 'package:strumsight/features/practice_generator/public.dart';

const plannerAssistGoal = 'goal.rhythm';
const plannerAssistSkill = 'rhythm.offbeatUpstroke';
const plannerAssistCandidate = 'practiceCatalog:exercise.offbeat';

PracticeCatalogSnapshot buildPlannerAssistCatalog() => PracticeCatalogSnapshot(
  catalogRevision: 'catalog.assist.v1',
  contentRevision: 'content.assist.v1',
  candidates: <ExerciseCandidate>[
    ExerciseCandidate(
      exerciseId: 'exercise.offbeat',
      source: CandidateSource.practiceCatalog,
      skillTargets: const <String>[plannerAssistSkill],
      prerequisites: const <String>['guitar.tuned'],
      supportedDurations: SupportedDurations.exact(const Duration(minutes: 5)),
      difficultyRange: DifficultyRange.exact('beginner'),
      capabilities: allCapabilitiesUnsupported(),
      loadProfile: const ExerciseLoadProfile.all(LoadLevel.low),
      offlineAvailable: true,
      contentRevision: 'content.assist.v1',
    ),
  ],
);

PlannerAssistRequest buildPlannerAssistRequest({
  String learnerNote = 'I want steadier upstrokes.',
}) => PlannerAssistRequest(
  requestId: 'planner-assist-request-1',
  locale: 'en',
  learnerNote: learnerNote,
  allowlist: PlannerAssistAllowlist(
    goalIds: const <String>[plannerAssistGoal],
    skillIds: const <String>[plannerAssistSkill],
    candidateIds: const <String>[plannerAssistCandidate],
  ),
);

Map<String, Object?> validPlannerAssistResponse() => <String, Object?>{
  'schemaVersion': 1,
  'locale': 'en',
  'goalIds': <Object?>[plannerAssistGoal],
  'skillIds': <Object?>[plannerAssistSkill],
  'candidateIds': <Object?>[plannerAssistCandidate],
  'rationale': 'Build relaxed offbeat control before increasing speed.',
  'requiresLearnerConfirmation': true,
  'blocks': <Object?>[
    <String, Object?>{
      'candidateId': plannerAssistCandidate,
      'minutes': 5,
      'rationale': 'Use the existing exercise for a short focused block.',
    },
  ],
};
