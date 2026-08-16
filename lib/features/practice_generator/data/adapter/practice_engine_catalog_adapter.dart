/// Caller-fed Practice Engine definition → candidate transformation.
library;

import 'package:strumsight/features/practice/public.dart'
    show BeatPosition, PracticeDefinition, PracticeScoreDimension;

import '../../domain/model/exercise_candidate.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/practice_catalog_snapshot.dart';

/// Caller-supplied metadata absent from Practice Engine's public definition.
///
/// This adapter intentionally does not read Practice Engine repositories or
/// providers. A future wiring round owns fetching this metadata and forming
/// these entries.
final class PracticeCatalogEntry {
  const PracticeCatalogEntry({
    required this.definition,
    required this.prerequisites,
    required this.offlineAvailable,
    required this.contentRevision,
    required this.loadProfile,
  });

  final PracticeDefinition definition;
  final Iterable<String>? prerequisites;
  final bool? offlineAvailable;
  final String? contentRevision;
  final ExerciseLoadProfile? loadProfile;
}

/// The pure result of adapting caller-provided Practice Engine entries.
final class PracticeCatalogAdaptation {
  const PracticeCatalogAdaptation({
    required this.candidates,
    required this.warnings,
  });

  final List<ExerciseCandidate> candidates;
  final List<CandidateExclusionWarning> warnings;
}

/// Converts only supplied [PracticeDefinition] values; it performs no I/O.
final class PracticeEngineCatalogAdapter {
  const PracticeEngineCatalogAdapter();

  PracticeCatalogAdaptation adapt(Iterable<PracticeCatalogEntry> entries) {
    final candidates = <ExerciseCandidate>[];
    final warnings = <CandidateExclusionWarning>[];

    for (final entry in entries) {
      final warning = _missingMetadataWarning(entry);
      if (warning != null) {
        warnings.add(warning);
        continue;
      }

      final definition = entry.definition;
      final capabilities = allCapabilitiesUnsupported();
      capabilities[ExerciseCapability.requiresMicrophone] =
          CapabilitySupport.supported;
      capabilities[ExerciseCapability.supportsTempo] =
          CapabilitySupport.supported;
      capabilities[ExerciseCapability.supportsLoop] =
          CapabilitySupport.supported;
      capabilities[ExerciseCapability.supportsDirectionScoring] =
          definition.scoringProfile.weights.containsKey(
            PracticeScoreDimension.direction,
          )
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported;
      capabilities[ExerciseCapability.supportsChordScoring] =
          definition.scoringProfile.weights.containsKey(
            PracticeScoreDimension.chord,
          )
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported;
      capabilities[ExerciseCapability.supportsOffline] = entry.offlineAvailable!
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported;

      candidates.add(
        ExerciseCandidate(
          exerciseId: definition.id,
          source: CandidateSource.practiceCatalog,
          skillTargets: definition.skillTags,
          prerequisites: entry.prerequisites!,
          supportedDurations: SupportedDurations.exact(
            _definitionDuration(definition),
          ),
          difficultyRange: DifficultyRange.exact(definition.difficulty.code),
          capabilities: capabilities,
          loadProfile: entry.loadProfile!,
          offlineAvailable: entry.offlineAvailable!,
          contentRevision: entry.contentRevision!,
        ),
      );
    }

    return PracticeCatalogAdaptation(
      candidates: List<ExerciseCandidate>.unmodifiable(candidates),
      warnings: List<CandidateExclusionWarning>.unmodifiable(warnings),
    );
  }

  CandidateExclusionWarning? _missingMetadataWarning(
    PracticeCatalogEntry entry,
  ) {
    final definition = entry.definition;
    if (definition.skillTags.isEmpty ||
        definition.skillTags.any((skill) => skill.trim().isEmpty)) {
      return _warning(
        entry,
        CandidateExclusionReason.missingPrerequisite,
        'skillTargets',
      );
    }
    if (entry.prerequisites == null ||
        entry.prerequisites!.isEmpty ||
        entry.prerequisites!.any(
          (prerequisite) => prerequisite.trim().isEmpty,
        )) {
      return _warning(
        entry,
        CandidateExclusionReason.missingPrerequisite,
        'prerequisites',
      );
    }
    if (entry.offlineAvailable == null) {
      return _warning(
        entry,
        CandidateExclusionReason.offlineUnavailable,
        'offlineAvailable',
      );
    }
    if (entry.contentRevision == null ||
        entry.contentRevision!.trim().isEmpty) {
      return _warning(
        entry,
        CandidateExclusionReason.revisionMissing,
        'contentRevision',
      );
    }
    if (entry.loadProfile == null) {
      return _warning(
        entry,
        CandidateExclusionReason.missingPrerequisite,
        'loadProfile',
      );
    }
    return null;
  }

  CandidateExclusionWarning _warning(
    PracticeCatalogEntry entry,
    CandidateExclusionReason reason,
    String detail,
  ) => CandidateExclusionWarning(
    reason: reason,
    source: CandidateSource.practiceCatalog.code,
    exerciseId: entry.definition.id,
    detail: detail,
  );
}

Duration _definitionDuration(PracticeDefinition definition) {
  final microseconds =
      definition.totalBeats.ticks *
      Duration.microsecondsPerMinute /
      BeatPosition.ticksPerBeat /
      definition.defaultTempo.bpm;
  return Duration(microseconds: microseconds.round());
}
