import '../model/practice_definition.dart';
import '../model/practice_difficulty.dart';
import '../model/practice_mode.dart';

/// Read-only access to authored [PracticeDefinition]s.
///
/// All methods are synchronous because the built-in catalog is `const` data
/// and the contract intentionally has no IO. Implementations must return
/// unmodifiable lists in a stable, deterministic order (the catalog's own
/// declaration order) and must not mutate or re-order the input.
abstract interface class PracticeCatalogRepository {
  /// Every definition in the catalog, in deterministic declaration order.
  List<PracticeDefinition> all();

  /// The definition with [id], or `null` when none exists. Never throws on
  /// an unknown id and never falls back to a guess.
  PracticeDefinition? byId(String id);

  /// Every definition whose [PracticeDefinition.mode] equals [mode], in
  /// declaration order. Empty list when no match exists.
  List<PracticeDefinition> byMode(PracticeMode mode);

  /// Every definition whose [PracticeDefinition.difficulty] equals
  /// [difficulty], in declaration order. Empty list when no match exists.
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty);
}
