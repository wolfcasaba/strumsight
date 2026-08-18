import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

ExerciseCandidate executionCandidate({
  String contentRevision = 'content.v1',
  Map<ExerciseCapability, CapabilitySupport>? capabilityOverrides,
}) => ExerciseCandidate(
  exerciseId: 'practice.strum.v1',
  source: CandidateSource.practiceCatalog,
  skillTargets: const <String>['rhythm.quarterNotes'],
  prerequisites: const <String>['guitar.tuned'],
  supportedDurations: SupportedDurations.exact(const Duration(minutes: 5)),
  difficultyRange: DifficultyRange.exact('beginner'),
  capabilities: <ExerciseCapability, CapabilitySupport>{
    ...allCapabilitiesUnsupported(),
    ExerciseCapability.requiresMicrophone: CapabilitySupport.supported,
    ExerciseCapability.supportsTempo: CapabilitySupport.supported,
    ExerciseCapability.supportsLoop: CapabilitySupport.supported,
    ...?capabilityOverrides,
  },
  loadProfile: const ExerciseLoadProfile.all(LoadLevel.low),
  offlineAvailable: true,
  contentRevision: contentRevision,
);

ExercisePrescription executionPrescription({
  String contentRevision = 'content.v1',
  Map<ExerciseCapability, CapabilitySupport>? capabilityOverrides,
}) => ExercisePrescription(
  candidate: executionCandidate(
    contentRevision: contentRevision,
    capabilityOverrides: capabilityOverrides,
  ),
  activeDuration: const Duration(minutes: 5),
  restDuration: const Duration(minutes: 1),
  tempoBpm: 72,
  repetition: RepetitionPrescription(target: 4, maximum: 6),
  loopCount: 1,
  hardElapsedLimit: const Duration(minutes: 6),
  successCriteria: SuccessCriteria(
    kind: SuccessCriterionKind.tempoSustained,
    description: 'Keep the prescribed tempo.',
    requiredCapabilities: const <ExerciseCapability>{
      ExerciseCapability.supportsTempo,
    },
  ),
);

PracticeBlock executionBlock({
  String contentRevision = 'content.v1',
  Map<ExerciseCapability, CapabilitySupport>? capabilityOverrides,
}) => PracticeBlock(
  id: BlockId('block.execution.1'),
  kind: BlockKind.primaryFocus,
  order: 1,
  prescription: executionPrescription(
    contentRevision: contentRevision,
    capabilityOverrides: capabilityOverrides,
  ),
  reasonCodes: const <String>['goal.primary'],
  evidenceRefs: const <String>['evidence.rhythm'],
  status: PracticeItemStatus.ready,
  estimatedElapsed: const Duration(minutes: 6),
);

PlanCompilerAvailability executionAvailability({
  String contentRevision = 'content.v1',
  Map<ExerciseCapability, CapabilitySupport>? capabilityOverrides,
}) => PlanCompilerAvailability(
  exerciseId: 'practice.strum.v1',
  contentRevision: contentRevision,
  capabilities: <ExerciseCapability, CapabilitySupport>{
    ...allCapabilitiesUnsupported(),
    ExerciseCapability.requiresMicrophone: CapabilitySupport.supported,
    ExerciseCapability.supportsTempo: CapabilitySupport.supported,
    ExerciseCapability.supportsLoop: CapabilitySupport.supported,
    ...?capabilityOverrides,
  },
);

PracticeSessionConfig matchingSessionConfig() => const PracticeSessionConfig(
  definitionId: 'practice.strum.v1',
  definitionSnapshotVersion: 1,
  effectiveTempo: Tempo(72),
  countInBars: 0,
  loopCount: 1,
  metronomeEnabled: true,
  accentEnabled: false,
  backingEnabled: false,
  scoringProfileId: 'default',
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: false,
  sessionTimeout: Duration(minutes: 6),
  reducedMotion: false,
);

PlanExecutionContext executionContext() => PlanExecutionContext(
  planId: PlanId('plan.execution.1'),
  revisionId: RevisionId('revision.execution.1'),
  dayId: DayId('day.execution.1'),
  blockId: BlockId('block.execution.1'),
);

PracticeOutcomeContext outcomeContext({
  String outcomeId = 'outcome.execution.1',
}) => PracticeOutcomeContext(
  id: OutcomeId(outcomeId),
  planId: PlanId('plan.execution.1'),
  revisionId: RevisionId('revision.execution.1'),
  dayId: DayId('day.execution.1'),
  blockId: BlockId('block.execution.1'),
  startedAt: DateTime.utc(2026, 8, 18, 12),
  completedAt: DateTime.utc(2026, 8, 18, 12, 6),
  activeDuration: const Duration(minutes: 5),
);

PracticeSessionResult completedSession({
  PracticeFinishReason finishReason = PracticeFinishReason.completedAllTargets,
}) => PracticeSessionResult(
  id: 'practice-session.execution.1',
  activeDuration: const Duration(minutes: 5),
  pausedDuration: Duration.zero,
  attempts: const <PracticeAttemptResult>[],
  finishReason: finishReason,
  highestStableTempo: null,
  coachingSummary: const <String>[],
);
