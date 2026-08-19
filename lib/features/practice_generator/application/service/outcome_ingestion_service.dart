/// Caller-fed outcome validation and deterministic review scheduling.
library;

import '../../data/adapter/practice_outcome_adapter.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/review_item.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/policy/spaced_repetition_policy.dart';

/// The controlled result of attempting to ingest one outcome.
enum OutcomeIngestionStatus { processed, duplicate, staleRevision }

/// Immutable result returned to the caller that owns persistence.
final class OutcomeIngestionResult {
  OutcomeIngestionResult({
    required this.status,
    required Iterable<ReviewItem> reviewItems,
    required this.canAdapt,
  }) : reviewItems = List<ReviewItem>.unmodifiable(reviewItems);

  final OutcomeIngestionStatus status;
  final List<ReviewItem> reviewItems;

  /// Only learner-performance outcomes may feed a later adaptation decision.
  final bool canAdapt;
}

/// Applies the review-policy portion of SDD Ch8 §26.4 without persistence.
///
/// The caller supplies all mutable state: the active revision, already
/// processed outcome identities, review queue and local calendar day. This
/// boundary deliberately does not import a repository.
final class OutcomeIngestionService {
  OutcomeIngestionService({SpacedRepetitionPolicy? reviewPolicy})
    : _reviewPolicy = reviewPolicy ?? SpacedRepetitionPolicy.defaultPolicy;

  final SpacedRepetitionPolicy _reviewPolicy;

  OutcomeIngestionResult ingest({
    required PracticeOutcome outcome,
    required RevisionId activeRevisionId,
    required Set<String> processedOutcomeIds,
    required Iterable<ReviewItem> reviewItems,
    required LocalDate today,
  }) {
    final originalItems = List<ReviewItem>.unmodifiable(reviewItems);
    if (outcome.revisionId != activeRevisionId) {
      return OutcomeIngestionResult(
        status: OutcomeIngestionStatus.staleRevision,
        reviewItems: originalItems,
        canAdapt: false,
      );
    }
    if (processedOutcomeIds.contains(outcome.id.value)) {
      return OutcomeIngestionResult(
        status: OutcomeIngestionStatus.duplicate,
        reviewItems: originalItems,
        canAdapt: false,
      );
    }
    if (outcome.completionState == PracticeCompletionState.failedTechnical) {
      return OutcomeIngestionResult(
        status: OutcomeIngestionStatus.processed,
        reviewItems: originalItems,
        canAdapt: false,
      );
    }

    final reviewOutcome = _reviewOutcome(outcome.completionState);
    final updatedItems = <ReviewItem>[];
    for (final item in originalItems) {
      final decision = _reviewPolicy.evaluate(
        item: item,
        outcome: reviewOutcome,
        today: today,
      );
      updatedItems.add(
        ReviewItem(
          target: item.target,
          currentInterval: decision.newInterval,
          dueDate: decision.newDueDate,
          replacementRequired: item.replacementRequired,
        ),
      );
    }
    return OutcomeIngestionResult(
      status: OutcomeIngestionStatus.processed,
      reviewItems: updatedItems,
      canAdapt:
          outcome.completionState == PracticeCompletionState.completed ||
          outcome.completionState == PracticeCompletionState.partial,
    );
  }

  ReviewOutcome _reviewOutcome(PracticeCompletionState state) =>
      switch (state) {
        PracticeCompletionState.completed => ReviewOutcome.success,
        PracticeCompletionState.partial => ReviewOutcome.partial,
        PracticeCompletionState.skipped ||
        PracticeCompletionState.cancelled ||
        PracticeCompletionState.unavailable ||
        PracticeCompletionState.failedTechnical => ReviewOutcome.unknown,
      };
}
