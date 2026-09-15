/// The production [PracticeCatalogReader]: the SHIPPED Practice Engine
/// catalog, adapted into a revisioned [PracticeCatalogSnapshot] (E17-R05,
/// ADR 0524 / §5.1).
///
/// The Practice feature already carries the app's one exercise catalog
/// (`practiceCatalogProvider`, `practice/public.dart`). This reader turns
/// exactly those authored definitions into planner candidates through the
/// existing [PracticeEngineCatalogAdapter] — it never declares a second,
/// generator-specific exercise list (§5.1: two truths for one exercise set
/// would diverge). The per-definition metadata the adapter needs but the
/// public [PracticeDefinition] does not carry is DERIVED from each
/// definition's own authored fields (difficulty, source, schema version),
/// never from a constant standing in for a missing source.
library;

import 'package:strumsight/features/practice/public.dart'
    show PracticeDefinition, PracticeDifficulty, PracticeSource;

import '../../application/port/practice_catalog_reader.dart';
import '../../domain/model/exercise_candidate.dart';
import '../../domain/model/practice_catalog_snapshot.dart';
import 'practice_engine_catalog_adapter.dart';

/// Reads the live Practice Engine definitions supplied by the caller.
///
/// [definitions] is the catalog list the composition root resolves from
/// `practiceCatalogProvider` — the reader owns no Practice repository
/// access of its own, so an override of that provider (a test's empty
/// catalog, say) flows through unchanged (acceptance A2).
final class PracticeEngineCatalogReader implements PracticeCatalogReader {
  const PracticeEngineCatalogReader({
    required this.definitions,
    this.adapter = const PracticeEngineCatalogAdapter(),
  });

  final List<PracticeDefinition> definitions;
  final PracticeEngineCatalogAdapter adapter;

  /// Prefix of the prerequisite code derived from a definition's authored
  /// difficulty band — the one prerequisite dimension the shipped catalog
  /// declares. It is deliberately NOT the validator's `guitar.tuned` code:
  /// the app has no tuning-confirmation source to confirm it against, so
  /// declaring it would silently exclude every shipped exercise.
  static const String difficultyPrerequisitePrefix = 'practice.difficulty.';

  @override
  PracticeCatalogSnapshot read() {
    final entries = <PracticeCatalogEntry>[
      for (final definition in definitions)
        PracticeCatalogEntry(
          definition: definition,
          prerequisites: <String>[
            '$difficultyPrerequisitePrefix${definition.difficulty.code}',
          ],
          // Built-in definitions ship inside the app bundle; every other
          // source (lesson, song, analysis, setlist) is caller-fed content
          // whose offline availability the planner must confirm at
          // runtime (`CandidateRuntimeContext.confirmedOfflineIdentities`).
          offlineAvailable: definition.source == PracticeSource.builtin,
          contentRevision: contentRevisionOf(definition),
          loadProfile: ExerciseLoadProfile.all(
            loadLevelForDifficulty(definition.difficulty),
          ),
        ),
    ];
    final adaptation = adapter.adapt(entries);
    return PracticeCatalogSnapshot(
      catalogRevision: catalogRevisionOf(definitions),
      contentRevision: contentRevisionOfCatalog(definitions),
      candidates: adaptation.candidates,
      warnings: adaptation.warnings,
    );
  }

  /// One definition's content revision: its authored schema version. The
  /// id itself already carries the content version suffix (`….v1`), so the
  /// candidate `sortKey` (`source:id:contentRevision`) stays unique.
  static String contentRevisionOf(PracticeDefinition definition) =>
      'schema.v${definition.schemaVersion}';

  /// Catalog MEMBERSHIP revision: changes when a definition is added or
  /// removed (SDD Ch8 §14 — distinct from content changes).
  static String catalogRevisionOf(List<PracticeDefinition> definitions) {
    final ids = definitions.map((definition) => definition.id).toList()..sort();
    return 'practiceCatalog.${ids.length}.${_fnv1a32(ids.join('\n'))}';
  }

  /// Catalog CONTENT revision: changes when any definition's authored
  /// content (schema version) changes while membership stays the same.
  static String contentRevisionOfCatalog(List<PracticeDefinition> definitions) {
    final entries = <String>[
      for (final definition in definitions)
        '${definition.id}@${contentRevisionOf(definition)}',
    ]..sort();
    return 'practiceContent.${_fnv1a32(entries.join('\n'))}';
  }

  /// Authored difficulty → pedagogical load band (SDD Ch8 §14.4 ordering).
  static LoadLevel loadLevelForDifficulty(PracticeDifficulty difficulty) =>
      switch (difficulty) {
        PracticeDifficulty.beginner => LoadLevel.low,
        PracticeDifficulty.intermediate => LoadLevel.medium,
        PracticeDifficulty.advanced => LoadLevel.high,
      };
}

/// Deterministic 32-bit FNV-1a over the UTF-16 code units — stable across
/// runs, devices and Dart VM versions (unlike `String.hashCode`), so a
/// persisted plan's `policyVersions['catalog']` can be compared with a
/// later boot's snapshot.
String _fnv1a32(String input) {
  var hash = 0x811C9DC5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
