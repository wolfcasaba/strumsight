/// Versioned, deterministic configuration for the [SpacedRepetitionPolicy]
/// (ADR 0303, SDD Ch8 Kör 17).
///
/// The policy deliberately uses a small, named ladder of intervals
/// instead of a tuned formula. Each step has a reason that the user or
/// the review surface can repeat back: "nothing changed — your last
/// attempt was uncertain", "interval doubled — you nailed it",
/// "interval shrunk — partial credit", "next attempt is tomorrow —
/// struggle". The policy is therefore auditable and explainable
/// (ADR 0255, §5.4).
///
/// Determinism: the policy never reads a clock, never generates
/// randomness, and never consults a [DateTime]. The review queue
/// supplies today's [LocalDate] as the anchor for the next due date
/// (ADR 0303 decision 3).
library;

import '../model/review_item.dart';
import '../model/weekly_availability.dart';

/// The configured ladder of days the policy walks along.
///
/// The bounds are chosen so that:
///   * the minimum is one day (a failure has a next attempt tomorrow),
///   * the maximum is the length of a "for the long haul" item,
///   * the partial step sits between the failure and the unchanged
///     band so the policy always has room to move in either direction.
final class ReviewIntervalLadder {
  const ReviewIntervalLadder({
    this.minimumIntervalDays = 1,
    this.partialIntervalDays = 3,
    this.unchangedIntervalDays = 7,
    this.maximumIntervalDays = 60,
  }) : assert(minimumIntervalDays >= 1, 'minimumIntervalDays >= 1'),
       assert(
         partialIntervalDays > minimumIntervalDays,
         'partialIntervalDays > minimumIntervalDays',
       ),
       assert(
         unchangedIntervalDays > partialIntervalDays,
         'unchangedIntervalDays > partialIntervalDays',
       ),
       assert(
         maximumIntervalDays > unchangedIntervalDays,
         'maximumIntervalDays > unchangedIntervalDays',
       );

  final int minimumIntervalDays;
  final int partialIntervalDays;
  final int unchangedIntervalDays;
  final int maximumIntervalDays;

  ReviewIntervalLadder withBounds({
    int? minimumIntervalDays,
    int? partialIntervalDays,
    int? unchangedIntervalDays,
    int? maximumIntervalDays,
  }) => ReviewIntervalLadder(
    minimumIntervalDays: minimumIntervalDays ?? this.minimumIntervalDays,
    partialIntervalDays: partialIntervalDays ?? this.partialIntervalDays,
    unchangedIntervalDays: unchangedIntervalDays ?? this.unchangedIntervalDays,
    maximumIntervalDays: maximumIntervalDays ?? this.maximumIntervalDays,
  );

  /// Convert a day count into a [Duration] the [ReviewItem] can store.
  Duration toDuration(int days) => Duration(days: days);

  /// Clamp a day count into the inclusive [minimumIntervalDays,
  /// maximumIntervalDays] range. The policy uses this so a value that
  /// jumps above the cap stays visible at the cap and never becomes
  /// "infinity".
  int clamp(int days) {
    if (days < minimumIntervalDays) return minimumIntervalDays;
    if (days > maximumIntervalDays) return maximumIntervalDays;
    return days;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewIntervalLadder &&
          other.minimumIntervalDays == minimumIntervalDays &&
          other.partialIntervalDays == partialIntervalDays &&
          other.unchangedIntervalDays == unchangedIntervalDays &&
          other.maximumIntervalDays == maximumIntervalDays;

  @override
  int get hashCode => Object.hash(
    minimumIntervalDays,
    partialIntervalDays,
    unchangedIntervalDays,
    maximumIntervalDays,
  );
}

/// Outcome of running the [SpacedRepetitionPolicy] on a single
/// [ReviewItem]. The result carries the new interval, the next due
/// date, and the reason that explains the move — the same triplet
/// the user can be told.
enum ReviewIntervalReason {
  /// The user nailed the attempt — interval grew.
  success('review.reason.success'),

  /// Partial credit — interval shrank toward the partial band.
  partial('review.reason.partial'),

  /// The user failed the attempt — interval dropped to the minimum
  /// band so the item is revisited soon.
  failure('review.reason.failure'),

  /// The measurement was uncertain — interval stayed the same.
  unknown('review.reason.unknown');

  const ReviewIntervalReason(this.code);

  final String code;

  static ReviewIntervalReason fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      throw ArgumentError.value(
        code,
        'code',
        'ReviewIntervalReason code must not be empty',
      );
    }
    for (final value in values) {
      if (value.code == code) return value;
    }
    throw ArgumentError.value(
      code,
      'code',
      'Unknown ReviewIntervalReason code: $code',
    );
  }

  @override
  String toString() => code;
}

/// The new state of a single review item after a [ReviewOutcome] is
/// applied (ADR 0303).
final class ReviewIntervalDecision {
  const ReviewIntervalDecision({
    required this.previousInterval,
    required this.newInterval,
    required this.previousDueDate,
    required this.newDueDate,
    required this.reason,
  });

  /// The interval the item had before the policy ran. Kept for
  /// provenance so the caller can audit the move.
  final Duration previousInterval;

  /// The interval the item has after the policy ran. Always positive
  /// and at most [ReviewIntervalLadder.maximumIntervalDays].
  final Duration newInterval;

  /// The due date the item had before the policy ran.
  final LocalDate previousDueDate;

  /// The due date the item has after the policy ran. For "unknown"
  /// this is [previousDueDate]; for the other outcomes it is
  /// `today + newInterval`.
  final LocalDate newDueDate;

  /// The reason the policy chose. The mapping is one-to-one with
  /// the [ReviewOutcome]:
  ///   * [ReviewOutcome.success] → [ReviewIntervalReason.success],
  ///   * [ReviewOutcome.partial] → [ReviewIntervalReason.partial],
  ///   * [ReviewOutcome.failure] → [ReviewIntervalReason.failure],
  ///   * [ReviewOutcome.unknown] → [ReviewIntervalReason.unknown].
  final ReviewIntervalReason reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewIntervalDecision &&
          other.previousInterval == previousInterval &&
          other.newInterval == newInterval &&
          other.previousDueDate == previousDueDate &&
          other.newDueDate == newDueDate &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(
    previousInterval,
    newInterval,
    previousDueDate,
    newDueDate,
    reason,
  );
}

/// Versioned, deterministic reviewer of one [ReviewItem] against one
/// [ReviewOutcome] (ADR 0303 decision 3, §5.4).
///
/// The policy is a pure function. It reads no clock, no
/// [DateTime], and no source of randomness. It uses the explicit
/// `today` [LocalDate] to anchor the next due date so the timezone
/// the policy runs under cannot change the result (A5, A8).
///
/// The ladder is configured by the [ReviewIntervalLadder] so the
/// steps are tweakable without rewriting the algorithm.
final class SpacedRepetitionPolicy {
  SpacedRepetitionPolicy({
    String version = 'spaced-repetition-policy-v1',
    this.ladder = const ReviewIntervalLadder(),
  }) : version = _requireText(version, 'version');

  /// Stable identifier retained by [ReviewIntervalDecision] as
  /// audit provenance.
  final String version;

  /// The named interval ladder the policy uses.
  final ReviewIntervalLadder ladder;

  static final SpacedRepetitionPolicy defaultPolicy = SpacedRepetitionPolicy();

  /// Run the policy on a single review item.
  ///
  /// `today` is the local calendar day the result is anchored to —
  /// the queue must hand it in explicitly. The
  /// `previousInterval` is the interval the item had before the
  /// attempt; the policy never reads it from a clock.
  ReviewIntervalDecision evaluate({
    required ReviewItem item,
    required ReviewOutcome outcome,
    required LocalDate today,
  }) {
    final previousInterval = item.currentInterval;
    final previousDueDate = item.dueDate;

    final decision = switch (outcome) {
      ReviewOutcome.unknown => _unchanged(previousInterval, previousDueDate),
      ReviewOutcome.success => _advance(previousInterval, today),
      ReviewOutcome.partial => _partial(previousInterval, today),
      ReviewOutcome.failure => _shorten(previousInterval, today),
    };

    return ReviewIntervalDecision(
      previousInterval: previousInterval,
      newInterval: decision.interval,
      previousDueDate: previousDueDate,
      newDueDate: decision.dueDate,
      reason: decision.reason,
    );
  }

  // -- private helpers ----------------------------------------------------

  _Result _unchanged(Duration previousInterval, LocalDate previousDueDate) {
    // ADR 0303 decision 3 + brief §5.2: `unknown` does not penalise.
    // The interval and the due date stay exactly what they were.
    return _Result(
      interval: previousInterval,
      dueDate: previousDueDate,
      reason: ReviewIntervalReason.unknown,
    );
  }

  _Result _advance(Duration previousInterval, LocalDate today) {
    // Walk toward the maximum, doubling by named step. The walk is
    // capped at the maximum, not "ceiling + 1".
    final nextDays = ladder.clamp(previousInterval.inDays * 2);
    return _Result(
      interval: ladder.toDuration(nextDays),
      dueDate: _addDays(today, nextDays),
      reason: ReviewIntervalReason.success,
    );
  }

  _Result _partial(Duration previousInterval, LocalDate today) {
    // Partial shorts toward the partial band but never crosses the
    // floor. The shrink is linear (midpoint between current and the
    // partial anchor) so the move is auditable.
    final partialAnchor = ladder.partialIntervalDays;
    final shrunk = (previousInterval.inDays + partialAnchor) ~/ 2;
    final nextDays = ladder.clamp(shrunk);
    return _Result(
      interval: ladder.toDuration(nextDays),
      dueDate: _addDays(today, nextDays),
      reason: ReviewIntervalReason.partial,
    );
  }

  _Result _shorten(Duration previousInterval, LocalDate today) {
    // Failure lands the next attempt at the minimum. The next
    // interval is the minimum; the due date is today + the minimum.
    return _Result(
      interval: ladder.toDuration(ladder.minimumIntervalDays),
      dueDate: _addDays(today, ladder.minimumIntervalDays),
      reason: ReviewIntervalReason.failure,
    );
  }
}

class _Result {
  const _Result({
    required this.interval,
    required this.dueDate,
    required this.reason,
  });

  final Duration interval;
  final LocalDate dueDate;
  final ReviewIntervalReason reason;
}

/// Add [days] whole calendar days to a [LocalDate] without touching
/// [DateTime] (ADR 0303 decision 3, A5/A8).
///
/// The implementation uses the same conservative month-length table
/// as the scheduling fixtures: the policy never crosses a leap
/// second, never reads an instant, and never goes near a timezone.
LocalDate _addDays(LocalDate start, int days) {
  if (days == 0) return start;
  final monthLengths = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var year = start.year;
  var month = start.month;
  var day = start.day + days;
  while (true) {
    final isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    final length = month == 2 && isLeap ? 29 : monthLengths[month - 1];
    if (day <= length) break;
    day -= length;
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
  }
  while (day <= 0) {
    month -= 1;
    if (month <= 0) {
      month = 12;
      year -= 1;
    }
    final isLeap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    final length = month == 2 && isLeap ? 29 : monthLengths[month - 1];
    day += length;
  }
  return LocalDate(year, month, day);
}

String _requireText(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty or blank');
  }
  return trimmed;
}
