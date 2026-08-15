/// Versioned, explicit legacy lesson → skill mapping (ADR 0293 §2, §4).
///
/// This is the ONLY place a legacy lesson id may resolve to a skill id. A
/// lesson id absent from [LegacyMappingTable.entries] has no mapping — the
/// adapters reading this table must not fall back to a name/chord/difficulty
/// heuristic (SDD Ch8 §5.1). [version] is a positive, deliberately-bumped
/// number that becomes the produced evidence's `measurementVersion`
/// provenance (ADR 0293 §4): a later mapping revision is then distinguishable
/// from an actual change in the learner.
library;

/// One lesson's explicit skill mapping. An empty [skillIds] is a deliberate
/// "known lesson, no skill signal" entry — still not an inference target.
final class LegacySkillMapping {
  const LegacySkillMapping({required this.lessonId, required this.skillIds});

  final String lessonId;
  final List<String> skillIds;
}

final class LegacyMappingTable {
  const LegacyMappingTable({required this.version, required this.entries})
    : assert(version > 0, 'LegacyMappingTable.version must be positive');

  /// Positive version carried into every evidence this table's mapping
  /// produces (ADR 0293 §4).
  final int version;

  final List<LegacySkillMapping> entries;

  /// The mapped skill ids for [lessonId], or `null` if [lessonId] has no
  /// entry at all (distinct from an entry with an empty skill list).
  List<String>? skillIdsFor(String lessonId) {
    for (final entry in entries) {
      if (entry.lessonId == lessonId) return entry.skillIds;
    }
    return null;
  }

  /// The mapping shipped with the app. Deliberately small and explicit —
  /// grow it one measured lesson id at a time, never by pattern.
  static const LegacyMappingTable builtIn = LegacyMappingTable(
    version: 1,
    entries: <LegacySkillMapping>[
      LegacySkillMapping(
        lessonId: 'g-major-first-strum',
        skillIds: <String>['chord.gMajor'],
      ),
      LegacySkillMapping(
        lessonId: 'c-to-g-swap',
        skillIds: <String>['chord.cMajor', 'chord.gMajor'],
      ),
      LegacySkillMapping(
        lessonId: 'd-major-basics',
        skillIds: <String>['chord.dMajor'],
      ),
    ],
  );
}
