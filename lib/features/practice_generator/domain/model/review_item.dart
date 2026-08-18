/// Spaced-repetition surface model for the AI Practice Generator (ADR 0303,
/// SDD Ch8 Kör 17).
///
/// The model is deliberately tiny and explains itself: a [ReviewTarget] is a
/// stable `kind + targetId` identity; a [ReviewOutcome] is the typed result
/// of a single review attempt; a [ReviewItem] is the lifecycle record that
/// the queue and the policy speak through. Nothing in this file reads a
/// clock, generates randomness, or imports Flutter.
library;

import 'weekly_availability.dart';

/// The kind of content a [ReviewTarget] points at.
///
/// Stable string codes so a persisted review item survives an enum rename
/// (ADR 0257 §4). Codes also feed the dedup key — the queue treats
/// `(kind, targetId)` as the only deduplication identity.
enum ReviewTargetKind {
  chordTransition('chordTransition'),
  strummingPattern('strummingPattern'),
  lesson('lesson'),
  songSection('songSection');

  const ReviewTargetKind(this.code);

  final String code;

  static ReviewTargetKind fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      throw ArgumentError.value(
        code,
        'code',
        'ReviewTargetKind code must not be empty',
      );
    }
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'Unknown ReviewTargetKind code: $code',
    );
  }

  @override
  String toString() => code;
}

/// A stable, deduplication-native identity for one reviewable piece of
/// content (ADR 0303 decision 1).
///
/// The review queue treats `(kind, targetId)` as the single identity it
/// deduplicates against. Two [ReviewTarget]s with the same kind and target
/// id refer to the same content no matter which path produced them.
final class ReviewTarget {
  ReviewTarget({required this.kind, required String targetId})
    : targetId = _requireText(targetId, 'targetId');

  final ReviewTargetKind kind;
  final String targetId;

  /// Stable key the queue uses for deduplication. The two parts are
  /// joined by a separator that cannot appear inside a kind code or in
  /// a target id (whitespace is rejected by [_requireText]).
  String get dedupKey => '${kind.code}|$targetId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewTarget && other.kind == kind && other.targetId == targetId;

  @override
  int get hashCode => Object.hash(kind, targetId);

  @override
  String toString() => 'ReviewTarget(${kind.code}, $targetId)';
}

/// The typed outcome of a single review attempt.
///
/// The four values match the §6.1 boundary cells:
///   * [success] — high confidence, achieved → interval grows,
///   * [partial] — partial achievement → interval stays in a middle band,
///   * [failure] — high confidence, not achieved → interval shortens,
///   * [unknown] — low confidence / insufficient data → interval unchanged
///     (ADR 0303 decision 3, ADR 0261 §2: `unknown` is not weakness).
enum ReviewOutcome {
  success('success'),
  partial('partial'),
  failure('failure'),
  unknown('unknown');

  const ReviewOutcome(this.code);

  final String code;

  static ReviewOutcome fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      throw ArgumentError.value(
        code,
        'code',
        'ReviewOutcome code must not be empty',
      );
    }
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'Unknown ReviewOutcome code: $code',
    );
  }

  @override
  String toString() => code;
}

/// The lifecycle record the review queue and policy speak through.
///
/// A [ReviewItem] is the queue's atom: it pairs one [ReviewTarget] with
/// the data the policy needs to schedule the next attempt (the current
/// interval, the next due date, and the [replacementRequired] flag for
/// content that has been deleted from the catalog).
///
/// Durations are kept in whole days because the due date is a
/// [LocalDate]; the queue has a separate [SelectableReviewItem] for the
/// runtime minute cost an item would consume.
final class ReviewItem {
  ReviewItem({
    required this.target,
    required this.currentInterval,
    required this.dueDate,
    this.replacementRequired = false,
  }) {
    if (currentInterval.inDays < 0) {
      throw ArgumentError.value(
        currentInterval.inDays,
        'currentInterval',
        'must not be negative',
      );
    }
    if (currentInterval.inDays == 0) {
      throw ArgumentError.value(
        currentInterval.inDays,
        'currentInterval',
        'must be a positive whole number of days; a brand-new item needs '
            'an initial interval rather than zero',
      );
    }
  }

  final ReviewTarget target;
  final Duration currentInterval;
  final LocalDate dueDate;
  final bool replacementRequired;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewItem &&
          other.target == target &&
          other.currentInterval == currentInterval &&
          other.dueDate == dueDate &&
          other.replacementRequired == replacementRequired;

  @override
  int get hashCode =>
      Object.hash(target, currentInterval, dueDate, replacementRequired);
}

/// A [ReviewItem] plus the runtime minute cost it would consume when
/// scheduled today.
///
/// The queue picks items in stable order up to
/// [ReviewQueue.reviewBudgetMinutes]; the minute cost is what the queue
/// sums against its budget. The cost is not part of the model's
/// identity — two items with the same target but different minutes
/// remain the same logical review entry.
final class SelectableReviewItem {
  const SelectableReviewItem({
    required this.item,
    required this.estimatedMinutes,
  });

  final ReviewItem item;
  final int estimatedMinutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectableReviewItem &&
          other.item == item &&
          other.estimatedMinutes == estimatedMinutes;

  @override
  int get hashCode => Object.hash(item, estimatedMinutes);
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}
