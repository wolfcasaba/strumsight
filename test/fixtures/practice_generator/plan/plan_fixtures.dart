import 'package:strumsight/features/practice_generator/public.dart';

ExerciseCandidate resolveCandidate(String exerciseId) {
  if (exerciseId != 'exercise.rhythm') {
    throw ArgumentError.value(exerciseId, 'exerciseId', 'unknown fixture');
  }
  final capabilities = allCapabilitiesUnsupported()
    ..[ExerciseCapability.supportsTempo] = CapabilitySupport.supported;
  return ExerciseCandidate(
    exerciseId: exerciseId,
    source: CandidateSource.practiceCatalog,
    skillTargets: const <String>['rhythm.quarterNotes'],
    prerequisites: const <String>['guitar.tuned'],
    supportedDurations: SupportedDurations(
      minimum: const Duration(minutes: 1),
      maximum: const Duration(minutes: 10),
    ),
    difficultyRange: DifficultyRange.exact('beginner'),
    capabilities: capabilities,
    loadProfile: const ExerciseLoadProfile.all(LoadLevel.low),
    offlineAvailable: true,
    contentRevision: 'content.v1',
  );
}

ExercisePrescription prescription() => ExercisePrescription(
  candidate: resolveCandidate('exercise.rhythm'),
  activeDuration: const Duration(minutes: 5),
  restDuration: const Duration(minutes: 1),
  tempoBpm: 72,
  repetition: RepetitionPrescription(target: 4, maximum: 6),
  loopCount: 1,
  hardElapsedLimit: const Duration(minutes: 6),
  successCriteria: SuccessCriteria(
    kind: SuccessCriterionKind.tempoSustained,
    description: 'Hold the tempo.',
    requiredCapabilities: const <ExerciseCapability>{
      ExerciseCapability.supportsTempo,
    },
  ),
);

PracticeBlock block({PracticeItemStatus status = PracticeItemStatus.planned}) =>
    PracticeBlock(
      id: BlockId('block.1'),
      kind: BlockKind.primaryFocus,
      order: 1,
      prescription: prescription(),
      reasonCodes: const <String>['goal.primary'],
      evidenceRefs: const <String>['evidence.tempo-accuracy'],
      status: status,
      estimatedElapsed: const Duration(minutes: 6),
    );

PracticeDay day({PracticeItemStatus status = PracticeItemStatus.planned}) =>
    PracticeDay(
      id: DayId('day.1'),
      localDate: LocalDate(2026, 8, 17),
      status: status,
      timeBudget: const Duration(minutes: 20),
      blocks: <PracticeBlock>[block()],
      primaryFocusSkillIds: const <String>['rhythm.quarterNotes'],
      reasonCodes: const <String>['goal.primary'],
    );

PracticeGoal goal() => PracticeGoal(
  id: GoalId('goal.1'),
  type: PracticeGoalType.rhythm,
  priority: GoalPriority.primary,
  status: PracticeGoalStatus.active,
  createdAt: DateTime.utc(2026, 8, 16),
  skillIds: const <String>['rhythm.quarterNotes'],
  userNote: 'private note',
);

AdaptivePracticePlan plan({String title = 'Fixture plan'}) =>
    AdaptivePracticePlan(
      id: PlanId('plan.1'),
      schemaVersion: 1,
      status: PlanStatus.active,
      title: title,
      createdAt: DateTime.utc(2026, 8, 16),
      startDate: LocalDate(2026, 8, 17),
      endDate: LocalDate(2026, 8, 23),
      goals: <PracticeGoal>[goal()],
      days: <PracticeDay>[day()],
      activeRevisionId: RevisionId('revision.1'),
      generationProvenance: GenerationRequestId('request.1'),
      policyVersions: const <String, String>{
        'catalog': 'catalog.v1',
        'content': 'content.v1',
      },
    );

PlanRevision revision({
  required int number,
  PlanRevision? previous,
  AdaptivePracticePlan? snapshot,
}) => PlanRevision(
  id: RevisionId('revision.$number'),
  planId: PlanId('plan.1'),
  number: number,
  createdAt: DateTime.utc(2026, 8, 16),
  reason: PlanRevisionReason.initialGeneration,
  snapshot: snapshot ?? plan(),
  previous: previous,
);
