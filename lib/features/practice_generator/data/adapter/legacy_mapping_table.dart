/// Versioned, explicit legacy lesson → skill mapping (ADR 0293 §2, §4).
///
/// This is the ONLY place a legacy lesson id may resolve to a skill id. A
/// lesson id absent from [LegacyMappingTable.entries] has no mapping — the
/// adapters reading this table must not fall back to a name/chord/difficulty
/// heuristic (SDD Ch8 §5.1). [version] is a positive, deliberately-bumped
/// number that becomes the produced evidence's `measurementVersion`
/// provenance (ADR 0293 §4): a later mapping revision is then distinguishable
/// from an actual change in the learner.
///
/// A mapping is one lesson → **at most one** skill (never many): the R05
/// [PracticeEvidenceRepository] deduplicates globally on a `SkillEvidence`'s
/// `sourceOutcomeId`, so an adapter that emitted more than one evidence per
/// outcome would silently lose every evidence past the first (E07-R07 review
/// F2). A lesson touching more than one skill needs more than one explicit,
/// caller-supplied outcome id — never a single outcome fanned out here.
library;

/// One lesson's explicit skill mapping. A `null` [skillId] is a deliberate
/// "known lesson, no skill signal" entry — still not an inference target.
final class LegacySkillMapping {
  const LegacySkillMapping({required this.lessonId, required this.skillId});

  final String lessonId;
  final String? skillId;
}

/// The result of looking up a lesson id in a [LegacyMappingTable]:
/// distinguishes "no entry at all" ([found] `false`) from "entry present but
/// with no skill signal" ([found] `true`, [skillId] `null`) — the two
/// distinct §6.1 boundary cells a single nullable return value cannot tell
/// apart.
final class LegacyMappingLookup {
  const LegacyMappingLookup._found(this.skillId) : found = true;
  const LegacyMappingLookup.unmapped() : found = false, skillId = null;

  final bool found;
  final String? skillId;
}

final class LegacyMappingTable {
  const LegacyMappingTable({required this.version, required this.entries})
    : assert(version > 0, 'LegacyMappingTable.version must be positive');

  /// Positive version carried into every evidence this table's mapping
  /// produces (ADR 0293 §4).
  final int version;

  final List<LegacySkillMapping> entries;

  /// The mapping lookup for [lessonId] (see [LegacyMappingLookup]).
  LegacyMappingLookup lookup(String lessonId) {
    for (final entry in entries) {
      if (entry.lessonId == lessonId) {
        return LegacyMappingLookup._found(entry.skillId);
      }
    }
    return const LegacyMappingLookup.unmapped();
  }

  /// The mapping shipped with the app. Deliberately small and explicit —
  /// grow it one measured lesson id at a time, never by pattern — and
  /// pinned to the actual public `Lessons.all` ids (`learn/model/lesson.dart`,
  /// E07-R07 review F1), never a plausible-looking placeholder.
  static const LegacyMappingTable builtIn = LegacyMappingTable(
    version: 2,
    entries: <LegacySkillMapping>[
      LegacySkillMapping(lessonId: 'first-strums', skillId: 'chord.gMajor'),
      LegacySkillMapping(lessonId: 'two-chord-change', skillId: 'chord.cMajor'),
      LegacySkillMapping(lessonId: 'eighth-drive', skillId: 'chord.dMajor'),
    ],
  );
}
