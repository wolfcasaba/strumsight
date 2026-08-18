/// Bounded, deterministic review queue for the AI Practice Generator
/// (ADR 0303, SDD Ch8 Kör 17).
///
/// The queue answers one question: given a today's snapshot of due
/// [ReviewItem]s, the day's total budget and the review slice of it,
/// and the set of review targets the catalog currently knows about,
/// which items should be scheduled today and which ones should be
/// flagged because the underlying content has been deleted?
///
/// Non-negotiable contracts (ADR 0303, brief §5):
///   * the queue never fills the day — `reviewBudgetMinutes <
///     totalDailyMinutes` is enforced at construction,
///   * the queue does not re-implement
///     [WeeklyScheduler]'s review-ratio policy; it only enforces the
///     per-day budget,
///   * targets missing from the current-target set are KEPT in the
///     output and flagged with [ReviewItem.replacementRequired]
///     instead of being silently dropped or thrown,
///   * deduplication is performed on the typed
///     `(ReviewTargetKind, targetId)` pair — the order of the
///     supplied items does not change the result.
library;

import '../model/review_item.dart';

/// The bounded, deterministic review queue (ADR 0303).
final class ReviewQueue {
  ReviewQueue({
    required this.totalDailyMinutes,
    required this.reviewBudgetMinutes,
  }) {
    if (totalDailyMinutes < 0) {
      throw ArgumentError.value(
        totalDailyMinutes,
        'totalDailyMinutes',
        'must not be negative',
      );
    }
    if (reviewBudgetMinutes < 0) {
      throw ArgumentError.value(
        reviewBudgetMinutes,
        'reviewBudgetMinutes',
        'must not be negative',
      );
    }
    if (reviewBudgetMinutes >= totalDailyMinutes) {
      throw ArgumentError.value(
        reviewBudgetMinutes,
        'reviewBudgetMinutes',
        'must be strictly less than totalDailyMinutes ($totalDailyMinutes); '
            'the review slot cannot fill the day',
      );
    }
  }

  /// The day's total active minutes. The review queue does not own
  /// it — it is a guard so the queue cannot swallow the day.
  final int totalDailyMinutes;

  /// The maximum number of minutes the queue may emit for review
  /// today. The constructor enforces the strict upper bound the ADR
  /// requires.
  final int reviewBudgetMinutes;

  /// Build today's review selection.
  ///
  /// [candidates] are the [SelectableReviewItem]s the caller already
  /// collected (already filtered to "due today or earlier" higher up
  /// the pipeline). [availableTargetIds] is the set of
  /// `kind|targetId` strings the catalog currently knows about; any
  /// candidate whose dedupKey is missing from the set is preserved
  /// in the [ReviewQueueDecision.replacementRequired] bucket — never
  /// silently dropped and never thrown (ADR 0303 decision 2, A6).
  /// The order of [candidates] is irrelevant; the queue sorts by
  /// the deterministic `(dueDate, target.dedupKey)` pair.
  ReviewQueueDecision select({
    required Iterable<SelectableReviewItem> candidates,
    required Set<String> availableTargetIds,
  }) {
    _validateCandidates(candidates);
    _validateAvailableTargetIds(availableTargetIds);

    final dedup = _deduplicate(candidates);

    final sorted = dedup.values.toList()
      ..sort((a, b) {
        final due = a.item.dueDate.compareTo(b.item.dueDate);
        if (due != 0) return due;
        return a.item.target.dedupKey.compareTo(b.item.target.dedupKey);
      });

    final selected = <SelectableReviewItem>[];
    final deferred = <SelectableReviewItem>[];
    final replacementRequired = <SelectableReviewItem>[];
    var remainingMinutes = reviewBudgetMinutes;

    for (final candidate in sorted) {
      final isInCatalog = availableTargetIds.contains(
        candidate.item.target.dedupKey,
      );
      if (!isInCatalog) {
        replacementRequired.add(candidate);
        continue;
      }

      // Bounded review budget (A1). The queue never expands it and
      // never silently drops the deferred candidate — when the
      // budget is exhausted, the rest of the queue is deferred.
      if (remainingMinutes == 0) {
        deferred.add(candidate);
        continue;
      }
      if (candidate.estimatedMinutes > remainingMinutes) {
        deferred.add(candidate);
        continue;
      }

      selected.add(candidate);
      remainingMinutes -= candidate.estimatedMinutes;
    }

    return ReviewQueueDecision(
      selected: List<SelectableReviewItem>.unmodifiable(selected),
      deferred: List<SelectableReviewItem>.unmodifiable(deferred),
      replacementRequired: List<SelectableReviewItem>.unmodifiable(
        replacementRequired,
      ),
      totalDailyMinutes: totalDailyMinutes,
      reviewBudgetMinutes: reviewBudgetMinutes,
    );
  }

  // -- private helpers ----------------------------------------------------

  Map<String, SelectableReviewItem> _deduplicate(
    Iterable<SelectableReviewItem> candidates,
  ) {
    final dedup = <String, SelectableReviewItem>{};
    for (final candidate in candidates) {
      final key = candidate.item.target.dedupKey;
      // The first occurrence wins; identical targets arriving on
      // multiple paths are intentionally collapsed here.
      dedup.putIfAbsent(key, () => candidate);
    }
    return dedup;
  }
}

void _validateCandidates(Iterable<SelectableReviewItem> candidates) {
  for (final candidate in candidates) {
    if (candidate.estimatedMinutes < 0) {
      throw ArgumentError.value(
        candidate.estimatedMinutes,
        'estimatedMinutes',
        'must not be negative',
      );
    }
  }
}

void _validateAvailableTargetIds(Set<String> availableTargetIds) {
  if (availableTargetIds.isEmpty) return;
  for (final key in availableTargetIds) {
    if (key.trim().isEmpty) {
      throw ArgumentError.value(
        key,
        'availableTargetIds',
        'must not contain empty or blank entries',
      );
    }
  }
}

/// The output of one [ReviewQueue.select] call.
///
/// The three buckets are disjoint and exhaustive:
///   * [selected] — items the queue schedules today within the
///     budget;
///   * [deferred] — items that fit the catalog but did not fit the
///     budget; the queue emits them so the caller can roll earlier
///     attempts into tomorrow;
///   * [replacementRequired] — items whose target is not in the
///     catalog snapshot; they are KEPT (never silently dropped) so
///     the caller can decide what to substitute.
final class ReviewQueueDecision {
  const ReviewQueueDecision({
    required this.selected,
    required this.deferred,
    required this.replacementRequired,
    required this.totalDailyMinutes,
    required this.reviewBudgetMinutes,
  });

  final List<SelectableReviewItem> selected;
  final List<SelectableReviewItem> deferred;
  final List<SelectableReviewItem> replacementRequired;
  final int totalDailyMinutes;
  final int reviewBudgetMinutes;

  /// The minutes the selected items consume. Useful for diagnostics —
  /// always within the budget enforced at construction.
  int get selectedMinutes =>
      selected.fold(0, (sum, item) => sum + item.estimatedMinutes);

  /// The minutes the deferred items would have consumed if the
  /// budget had allowed them. Excludes the
  /// [replacementRequired] items because the catalog cannot run
  /// them.
  int get deferredMinutes =>
      deferred.fold(0, (sum, item) => sum + item.estimatedMinutes);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewQueueDecision &&
          other.totalDailyMinutes == totalDailyMinutes &&
          other.reviewBudgetMinutes == reviewBudgetMinutes &&
          _sameList(other.selected, selected) &&
          _sameList(other.deferred, deferred) &&
          _sameList(other.replacementRequired, replacementRequired);

  @override
  int get hashCode => Object.hash(
    totalDailyMinutes,
    reviewBudgetMinutes,
    Object.hashAll(selected),
    Object.hashAll(deferred),
    Object.hashAll(replacementRequired),
  );
}

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
