/// Shared, parameterizable builders for `PlanValidator`/`PlanRepairer` tests
/// (E07-R11 H3 self-heal, §0.0). Every builder is a thin wrapper over the
/// already-validated `public.dart` domain constructors — no domain decision
/// lives here, only fixture assembly.
library;

import 'package:strumsight/features/practice_generator/public.dart';

const catalogRevision = 'catalog.v1';
const defaultContentRevision = 'content.v1';

ExerciseCandidate buildCandidate({
  String exerciseId = 'exercise.rhythm',
  CandidateSource source = CandidateSource.practiceCatalog,
  String contentRevision = defaultContentRevision,
  bool offlineAvailable = true,
  Iterable<String> prerequisites = const <String>['fixture.baseline'],
  LoadLevel frettingHandLoad = LoadLevel.low,
  Map<ExerciseCapability, CapabilitySupport> capabilityOverrides =
      const <ExerciseCapability, CapabilitySupport>{},
}) {
  final capabilities = allCapabilitiesUnsupported()
    ..[ExerciseCapability.supportsTempo] = CapabilitySupport.supported
    ..addAll(capabilityOverrides);
  return ExerciseCandidate(
    exerciseId: exerciseId,
    source: source,
    skillTargets: const <String>['rhythm.quarterNotes'],
    prerequisites: prerequisites,
    supportedDurations: SupportedDurations(
      minimum: const Duration(minutes: 1),
      maximum: const Duration(minutes: 10),
    ),
    difficultyRange: DifficultyRange.exact('beginner'),
    capabilities: capabilities,
    loadProfile: ExerciseLoadProfile(
      cognitive: LoadLevel.low,
      frettingHand: frettingHandLoad,
      pickingHand: LoadLevel.low,
      repetition: LoadLevel.low,
      novelty: LoadLevel.low,
      concentration: LoadLevel.low,
    ),
    offlineAvailable: offlineAvailable,
    contentRevision: contentRevision,
  );
}

ExercisePrescription buildPrescription(
  ExerciseCandidate candidate, {
  Duration activeDuration = const Duration(minutes: 5),
  Duration restDuration = const Duration(minutes: 1),
}) => ExercisePrescription(
  candidate: candidate,
  activeDuration: activeDuration,
  restDuration: restDuration,
  repetition: RepetitionPrescription(target: 4, maximum: 6),
  loopCount: 1,
  hardElapsedLimit: const Duration(minutes: 10),
  successCriteria: SuccessCriteria(
    kind: SuccessCriterionKind.completion,
    description: 'Complete the exercise.',
    requiredCapabilities: const <ExerciseCapability>{
      ExerciseCapability.supportsTempo,
    },
  ),
);

PracticeBlock buildBlock({
  required String id,
  required int order,
  ExercisePrescription? prescription,
  PracticeItemStatus status = PracticeItemStatus.planned,
  Duration estimatedElapsed = const Duration(minutes: 6),
}) => PracticeBlock(
  id: BlockId(id),
  kind: BlockKind.primaryFocus,
  order: order,
  prescription: prescription ?? buildPrescription(buildCandidate()),
  reasonCodes: const <String>['goal.primary'],
  evidenceRefs: const <String>['evidence.tempo-accuracy'],
  status: status,
  estimatedElapsed: estimatedElapsed,
);

PracticeDay buildDay({
  required String id,
  required LocalDate localDate,
  Iterable<PracticeBlock>? blocks,
  PracticeItemStatus status = PracticeItemStatus.planned,
  Duration timeBudget = const Duration(minutes: 30),
}) => PracticeDay(
  id: DayId(id),
  localDate: localDate,
  status: status,
  timeBudget: timeBudget,
  blocks: blocks ?? <PracticeBlock>[buildBlock(id: '$id.block.1', order: 1)],
  primaryFocusSkillIds: const <String>['rhythm.quarterNotes'],
  reasonCodes: const <String>['goal.primary'],
);

PracticeGoal buildGoal() => PracticeGoal(
  id: GoalId('goal.1'),
  type: PracticeGoalType.rhythm,
  priority: GoalPriority.primary,
  status: PracticeGoalStatus.active,
  createdAt: DateTime.utc(2026, 8, 16),
  skillIds: const <String>['rhythm.quarterNotes'],
);

AdaptivePracticePlan buildPlan({
  String id = 'plan.1',
  Iterable<PracticeDay>? days,
  String revisionId = 'revision.1',
}) => AdaptivePracticePlan(
  id: PlanId(id),
  schemaVersion: 1,
  status: PlanStatus.active,
  title: 'Fixture plan',
  createdAt: DateTime.utc(2026, 8, 16),
  startDate: LocalDate(2026, 8, 17),
  endDate: LocalDate(2026, 8, 23),
  goals: <PracticeGoal>[buildGoal()],
  days: days ?? <PracticeDay>[buildDay(id: 'day.1', localDate: LocalDate(2026, 8, 17))],
  activeRevisionId: RevisionId(revisionId),
  generationProvenance: GenerationRequestId('request.1'),
  policyVersions: const <String, String>{
    'catalog': catalogRevision,
    'content': defaultContentRevision,
  },
);

PracticeCatalogSnapshot buildCatalog({
  Iterable<ExerciseCandidate>? candidates,
}) => PracticeCatalogSnapshot(
  catalogRevision: catalogRevision,
  contentRevision: defaultContentRevision,
  candidates: candidates ?? <ExerciseCandidate>[buildCandidate()],
);

WeeklyAvailability buildAvailability({
  LocalDate? date,
  int maximumMinutes = 120,
  ConstraintStrength maximumStrength = ConstraintStrength.hard,
}) => WeeklyAvailability(<DailyAvailability>[
  DailyAvailability(
    date: date ?? LocalDate(2026, 8, 17),
    status: AvailabilityStatus.available,
    minimumMinutes: 0,
    targetMinutes: maximumMinutes,
    maximumMinutes: maximumMinutes,
    maximumStrength: maximumStrength,
    softExcessMinuteCost: maximumStrength == ConstraintStrength.soft ? 1 : 0,
  ),
]);

PlanValidationContext buildContext({
  PracticeCatalogSnapshot? catalog,
  WeeklyAvailability? availability,
  String repairRevisionId = 'revision.2',
  AdaptivePracticePlan? previousSnapshot,
  Iterable<String> confirmedAssetIdentities = const <String>[],
  Iterable<String> confirmedDeviceCapabilityIdentities = const <String>[],
  Iterable<String> confirmedOfflineIdentities = const <String>[],
  Iterable<String> confirmedTuningIdentities = const <String>[],
  Iterable<String> hardAvoidIdentities = const <String>[],
}) => PlanValidationContext(
  catalog: catalog ?? buildCatalog(),
  availability: availability ?? buildAvailability(),
  repairRevisionId: RevisionId(repairRevisionId),
  previousSnapshot: previousSnapshot,
  confirmedAssetIdentities: confirmedAssetIdentities,
  confirmedDeviceCapabilityIdentities: confirmedDeviceCapabilityIdentities,
  confirmedOfflineIdentities: confirmedOfflineIdentities,
  confirmedTuningIdentities: confirmedTuningIdentities,
  hardAvoidIdentities: hardAvoidIdentities,
);

String identityOf(ExerciseCandidate candidate) =>
    PlanValidationContext.identityOf(candidate);
