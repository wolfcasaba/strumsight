/// Shared, parameterizable builders for `CandidateSelector`/`CandidatePolicy`
/// tests (E07-R13 §0.0). Every builder is a thin wrapper over the already
/// validated `public.dart` domain constructors — no domain decision lives
/// here, only fixture assembly.
library;

import 'package:strumsight/features/practice_generator/public.dart';

const candidateCatalogRevision = 'catalog.v1';
const candidateContentRevision = 'content.v1';
const candidateSkill = 'rhythm.quarterNotes';

ExerciseCandidate buildCandidate({
  required String exerciseId,
  CandidateSource source = CandidateSource.practiceCatalog,
  Iterable<String> skillTargets = const <String>[candidateSkill],
  Iterable<String> prerequisites = const <String>['fixture.baseline'],
  Map<ExerciseCapability, CapabilitySupport> capabilityOverrides =
      const <ExerciseCapability, CapabilitySupport>{},
  bool offlineAvailable = true,
  LoadLevel frettingHandLoad = LoadLevel.low,
  DifficultyRange? difficultyRange,
  ExerciseLoadProfile? loadProfile,
  String contentRevision = candidateContentRevision,
}) {
  final capabilities = allCapabilitiesUnsupported()
    ..[ExerciseCapability.supportsTempo] = CapabilitySupport.supported
    ..addAll(capabilityOverrides);
  return ExerciseCandidate(
    exerciseId: exerciseId,
    source: source,
    skillTargets: skillTargets,
    prerequisites: prerequisites,
    supportedDurations: SupportedDurations(
      minimum: const Duration(minutes: 1),
      maximum: const Duration(minutes: 10),
    ),
    difficultyRange: difficultyRange ?? DifficultyRange.exact('beginner'),
    capabilities: capabilities,
    loadProfile:
        loadProfile ??
        ExerciseLoadProfile(
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

PracticeCatalogSnapshot buildCatalog({
  Iterable<ExerciseCandidate>? candidates,
  String catalogRevision = candidateCatalogRevision,
  String contentRevision = candidateContentRevision,
}) => PracticeCatalogSnapshot(
  catalogRevision: catalogRevision,
  contentRevision: contentRevision,
  candidates: candidates ?? <ExerciseCandidate>[],
);

SkillPriority buildPriority({
  String skillId = candidateSkill,
  double score = 0.7,
  String policyVersion = 'priority-policy-v1',
  bool isSafetyOverridden = false,
  Iterable<SkillPriorityFactor>? factors,
}) {
  final resolvedFactors =
      factors ??
      <SkillPriorityFactor>[
        SkillPriorityFactor(
          kind: SkillPriorityFactorKind.skillGap,
          normalizedValue: score,
          contribution: score,
        ),
      ];
  return SkillPriority(
    skillId: skillId,
    score: score,
    policyVersion: policyVersion,
    factors: resolvedFactors,
    isSafetyOverridden: isSafetyOverridden,
  );
}

CandidateRuntimeContext buildContext({
  Iterable<String> hardAvoidIdentities = const <String>[],
  Iterable<String> confirmedAssetIdentities = const <String>[],
  Iterable<String> confirmedDeviceCapabilityIdentities = const <String>[],
  Iterable<String> confirmedOfflineIdentities = const <String>[],
  Iterable<String> confirmedTuningIdentities = const <String>[],
  Iterable<String> recentlyUsedIdentities = const <String>[],
}) => CandidateRuntimeContext(
  hardAvoidIdentities: hardAvoidIdentities,
  confirmedAssetIdentities: confirmedAssetIdentities,
  confirmedDeviceCapabilityIdentities: confirmedDeviceCapabilityIdentities,
  confirmedOfflineIdentities: confirmedOfflineIdentities,
  confirmedTuningIdentities: confirmedTuningIdentities,
  recentlyUsedIdentities: recentlyUsedIdentities,
);

String identityOf(ExerciseCandidate candidate) =>
    CandidateRuntimeContext.identityOf(candidate);
