/// Deterministic learner profiles used by the E07-R30 planner evaluation.
library;

import 'package:strumsight/features/practice_generator/application/service/shadow_plan_generator.dart';
import 'package:strumsight/features/practice_generator/public.dart';

final class GoldenPlannerProfile {
  const GoldenPlannerProfile({
    required this.id,
    required this.input,
    required this.expectedCandidateIds,
  });

  final String id;
  final ShadowPlanInput input;

  /// The checked-in, executable candidate truth for this learner profile.
  final List<String> expectedCandidateIds;
}

List<GoldenPlannerProfile> goldenProfiles() => <GoldenPlannerProfile>[
  _profile(
    id: 'starter-rhythm',
    skillId: 'rhythm.quarterNotes',
    exerciseId: 'rhythm.quarterNotes.steady',
    maximumMinutes: 20,
    performance: 0.45,
  ),
  _profile(
    id: 'chord-transition',
    skillId: 'chord.gToC',
    exerciseId: 'chord.gToC.controlled',
    maximumMinutes: 30,
    performance: 0.62,
    requiresMicrophone: true,
  ),
  _profile(
    id: 'micro-strumming',
    skillId: 'strumming.downUp',
    exerciseId: 'strumming.downUp.micro',
    maximumMinutes: 10,
    performance: 0.31,
  ),
];

GoldenPlannerProfile _profile({
  required String id,
  required String skillId,
  required String exerciseId,
  required int maximumMinutes,
  required double performance,
  bool requiresMicrophone = false,
}) {
  final date = LocalDate(2026, 8, 24);
  final availability = WeeklyAvailability(<DailyAvailability>[
    DailyAvailability(
      date: date,
      status: AvailabilityStatus.available,
      minimumMinutes: 0,
      targetMinutes: maximumMinutes,
      maximumMinutes: maximumMinutes,
      maximumStrength: ConstraintStrength.hard,
    ),
  ]);
  final capabilities = allCapabilitiesUnsupported()
    ..[ExerciseCapability.supportsTempo] = CapabilitySupport.supported;
  if (requiresMicrophone) {
    capabilities[ExerciseCapability.requiresMicrophone] =
        CapabilitySupport.supported;
  }
  final candidate = ExerciseCandidate(
    exerciseId: exerciseId,
    source: CandidateSource.practiceCatalog,
    skillTargets: <String>[skillId],
    prerequisites: const <String>['fixture.baseline'],
    supportedDurations: SupportedDurations.exact(const Duration(minutes: 5)),
    difficultyRange: DifficultyRange.exact('beginner'),
    capabilities: capabilities,
    loadProfile: const ExerciseLoadProfile.all(LoadLevel.low),
    offlineAvailable: true,
    contentRevision: 'content.v1',
  );
  final request = PracticeGenerationRequest(
    id: GenerationRequestId('request.$id'),
    createdAt: DateTime.utc(2026, 8, 24),
    locale: 'en',
    generationMode: GenerationMode.starter,
    planHorizonDays: 1,
    availability: availability,
    constraints: LearnerConstraints(const <LearnerConstraint>[]),
    goals: <PracticeGoal>[
      PracticeGoal(
        id: GoalId('goal.$id'),
        type: PracticeGoalType.technique,
        priority: GoalPriority.primary,
        status: PracticeGoalStatus.active,
        createdAt: DateTime.utc(2026, 8, 24),
        skillIds: <String>[skillId],
      ),
    ],
  );
  return GoldenPlannerProfile(
    id: id,
    input: ShadowPlanInput(
      request: request,
      catalog: PracticeCatalogSnapshot(
        catalogRevision: 'catalog.v1',
        contentRevision: 'content.v1',
        candidates: <ExerciseCandidate>[candidate],
      ),
      evidence: <SkillEvidence>[
        SkillEvidence(
          skillId: skillId,
          source: EvidenceSource.learn,
          sourceOutcomeId: OutcomeId('outcome.$id'),
          measurementVersion: 1,
          measuredAt: DateTime.utc(2026, 8, 20),
          capturedAt: DateTime.utc(2026, 8, 24),
          confidence: 0.9,
          performance: PerformanceEvidence(
            metricCode: 'fixture.accuracy',
            value: performance,
          ),
        ),
      ],
      asOf: DateTime.utc(2026, 8, 24),
      planId: PlanId('plan.$id'),
      initialRevisionId: RevisionId('revision.$id'),
      candidateContext: requiresMicrophone
          ? CandidateRuntimeContext(
              confirmedDeviceCapabilityIdentities: <String>[
                CandidateRuntimeContext.identityOf(candidate),
              ],
            )
          : null,
    ),
    expectedCandidateIds: <String>[exerciseId],
  );
}
