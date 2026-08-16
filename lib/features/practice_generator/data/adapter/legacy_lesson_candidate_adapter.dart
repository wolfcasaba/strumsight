/// Caller-fed legacy Learn lesson → executable candidate transformation.
library;

import 'package:strumsight/features/learn/public.dart' show Lesson;

import '../../domain/model/exercise_candidate.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/practice_catalog_snapshot.dart';
import 'legacy_mapping_table.dart';

/// Caller-supplied catalog metadata missing from the public [Lesson] value.
final class LegacyLessonCatalogEntry {
  const LegacyLessonCatalogEntry({
    required this.lesson,
    required this.prerequisites,
    required this.offlineAvailable,
    required this.contentRevision,
    required this.loadProfile,
  });

  final Lesson lesson;
  final Iterable<String>? prerequisites;
  final bool? offlineAvailable;
  final String? contentRevision;
  final ExerciseLoadProfile? loadProfile;
}

/// The pure result of adapting caller-provided legacy lessons.
final class LegacyLessonCandidateAdaptation {
  const LegacyLessonCandidateAdaptation({
    required this.candidates,
    required this.warnings,
  });

  final List<ExerciseCandidate> candidates;
  final List<CandidateExclusionWarning> warnings;
}

/// Uses only explicit lesson-id mappings; it never infers skills from names.
final class LegacyLessonCandidateAdapter {
  const LegacyLessonCandidateAdapter({
    this.mappingTable = LegacyMappingTable.builtIn,
  });

  final LegacyMappingTable mappingTable;

  LegacyLessonCandidateAdaptation adapt(
    Iterable<LegacyLessonCatalogEntry> entries,
  ) {
    final candidates = <ExerciseCandidate>[];
    final warnings = <CandidateExclusionWarning>[];

    for (final entry in entries) {
      final lesson = entry.lesson;
      final lookup = mappingTable.lookup(lesson.id);
      final metadataWarning = _missingMetadataWarning(entry, lookup.skillId);
      if (metadataWarning != null) {
        warnings.add(metadataWarning);
        continue;
      }

      final capabilities = allCapabilitiesUnsupported();
      capabilities[ExerciseCapability.supportsOffline] = entry.offlineAvailable!
          ? CapabilitySupport.supported
          : CapabilitySupport.unsupported;

      candidates.add(
        ExerciseCandidate(
          exerciseId: lesson.id,
          source: CandidateSource.legacyLesson,
          skillTargets: <String>[lookup.skillId!],
          prerequisites: entry.prerequisites!,
          supportedDurations: SupportedDurations.exact(_lessonDuration(lesson)),
          difficultyRange: DifficultyRange.exact(lesson.difficulty.name),
          capabilities: capabilities,
          loadProfile: entry.loadProfile!,
          offlineAvailable: entry.offlineAvailable!,
          contentRevision: entry.contentRevision!,
        ),
      );
    }

    return LegacyLessonCandidateAdaptation(
      candidates: List<ExerciseCandidate>.unmodifiable(candidates),
      warnings: List<CandidateExclusionWarning>.unmodifiable(warnings),
    );
  }

  CandidateExclusionWarning? _missingMetadataWarning(
    LegacyLessonCatalogEntry entry,
    String? skillId,
  ) {
    if (skillId == null || skillId.trim().isEmpty) {
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
    LegacyLessonCatalogEntry entry,
    CandidateExclusionReason reason,
    String detail,
  ) => CandidateExclusionWarning(
    reason: reason,
    source: CandidateSource.legacyLesson.code,
    exerciseId: entry.lesson.id,
    detail: detail,
  );
}

Duration _lessonDuration(Lesson lesson) => Duration(
  microseconds:
      (lesson.totalBeats * Duration.microsecondsPerMinute / lesson.bpm).round(),
);
