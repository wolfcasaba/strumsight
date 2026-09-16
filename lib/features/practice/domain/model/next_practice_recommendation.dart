import 'practice_definition.dart';
import 'practice_history_entry.dart';

/// Why [NextPracticeRecommendation.definition] is the next thing to play —
/// every reason maps to one honest, learner-facing sentence in the UI.
enum NextPracticeReason {
  /// No history at all: the easiest entry of the catalog.
  firstSession,

  /// The last session's target coverage was below
  /// [recommendNextPractice]'s consolidation threshold: the same definition
  /// again, so the skill locks in before moving on.
  repeatToConsolidate,

  /// The last session was solid: the first definition the learner has not
  /// played yet, easiest first.
  advance,

  /// Everything in the catalog has been played: the definition whose most
  /// recent coverage is the lowest.
  revisitWeakest,
}

/// The one concrete next step the hub's recommended card and the result
/// screen's "Next" action share.
final class NextPracticeRecommendation {
  const NextPracticeRecommendation({
    required this.definition,
    required this.reason,
    this.basedOn,
  });

  final PracticeDefinition definition;
  final NextPracticeReason reason;

  /// The history entry the decision was made from (`null` for
  /// [NextPracticeReason.firstSession]).
  final PracticeHistoryEntry? basedOn;
}
