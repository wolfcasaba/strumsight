/// Shared, parameterizable builders for the E07-R17 review domain
/// (ADR 0303, §0.0).
///
/// Every builder is a thin wrapper over the already-validated
/// `public.dart` domain constructors — no domain decision lives here,
/// only fixture assembly. The review domain is deterministic, so the
/// fixtures only encode shape and tag them with a stable
/// `(kind, targetId)` identity.
library;

import 'package:strumsight/features/practice_generator/public.dart';

/// Build a [ReviewTarget] with the supplied [kind] and [targetId].
ReviewTarget buildReviewTarget({
  required ReviewTargetKind kind,
  required String targetId,
}) => ReviewTarget(kind: kind, targetId: targetId);

/// Build a [ReviewItem] with the supplied parameters. The default
/// interval is one day so the policy always has a positive baseline
/// to evolve from.
ReviewItem buildReviewItem({
  required ReviewTargetKind kind,
  required String targetId,
  int intervalDays = 1,
  required LocalDate dueDate,
  bool replacementRequired = false,
}) => ReviewItem(
  target: buildReviewTarget(kind: kind, targetId: targetId),
  currentInterval: Duration(days: intervalDays),
  dueDate: dueDate,
  replacementRequired: replacementRequired,
);

/// Build a [SelectableReviewItem] with the supplied [minutes] cost.
SelectableReviewItem buildSelectableReviewItem({
  required ReviewTargetKind kind,
  required String targetId,
  required int minutes,
  int intervalDays = 1,
  required LocalDate dueDate,
  bool replacementRequired = false,
}) => SelectableReviewItem(
  item: buildReviewItem(
    kind: kind,
    targetId: targetId,
    intervalDays: intervalDays,
    dueDate: dueDate,
    replacementRequired: replacementRequired,
  ),
  estimatedMinutes: minutes,
);

/// Add [days] whole calendar days to a [LocalDate] without touching
/// [DateTime] so the policy's "today + interval" math survives
/// retrospectively on this side of the test as well.
LocalDate addLocalDays(LocalDate start, int days) {
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
