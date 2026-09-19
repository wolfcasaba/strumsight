/// `KeyValueStore`-backed [CatchUpNoticeLog] — the production binding for
/// the "offered once, not nagged" rule of ADR 0269 §5.
library;

import '../../../../core/storage/key_value_store.dart';
import '../../application/port/catch_up_notice_log.dart';

/// Persists the acknowledged revision keys as a bounded string list.
///
/// Dedicated namespace, deliberately distinct from
/// `ss.practice_generator.plan.*` (`LocalPracticePlanRepository`),
/// `ss.practice_generator.evidence.*` (`LocalPracticeEvidenceRepository`)
/// and `ss.practice_generator.generation_draft`
/// (`GenerationDraftRepository`), so a bad write here can never collide
/// with a plan, an outcome or a wizard draft.
///
/// The list is bounded to [maxEntries] newest-first entries. It records a
/// UI acknowledgement, not user content: an old plan revision that falls
/// off the end can only cause the explainer to be offered once more, which
/// is the safe direction — nothing the learner authored is stored here, so
/// nothing can be lost by the trim.
final class StoredCatchUpNoticeLog implements CatchUpNoticeLog {
  StoredCatchUpNoticeLog({required this.keyValueStore, int maxEntries = 20})
    : maxEntries = _positive(maxEntries, 'maxEntries');

  final KeyValueStore keyValueStore;

  /// How many acknowledged revision keys are kept, newest first.
  final int maxEntries;

  static const String storageKey = 'ss.practice_generator.catch_up.offered';

  /// The last write that failed, or `null` when none has.
  ///
  /// A failed write is NOT swallowed into silence: it is recorded here, and
  /// its only user-visible consequence is that the explainer is offered
  /// again on the next visit — the honest, non-destructive downgrade. It is
  /// deliberately not raised as an error state on the plan screen: a
  /// preference write failing is nothing the learner can act on, and an
  /// alarm there would itself be the pressure ADR 0269 §5 forbids.
  StorageException? lastWriteFailure;

  @override
  bool wasAcknowledged(String revisionKey) => _read().contains(revisionKey);

  @override
  Future<void> acknowledge(String revisionKey) async {
    final current = _read();
    if (current.contains(revisionKey)) return;
    final next = <String>[revisionKey, ...current];
    try {
      await keyValueStore.writeStringList(
        storageKey,
        next.length <= maxEntries ? next : next.sublist(0, maxEntries),
      );
      lastWriteFailure = null;
    } on StorageException catch (failure) {
      lastWriteFailure = failure;
    }
  }

  /// A type-mismatched or absent value reads as "nothing acknowledged yet"
  /// — the [KeyValueStore] contract's own `null`-instead-of-throw rule.
  List<String> _read() =>
      keyValueStore.readStringList(storageKey) ?? const <String>[];
}

int _positive(int value, String name) {
  if (value < 1) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
  return value;
}
