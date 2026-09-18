/// The app's ONE calendar-day ↔ epoch-day conversion (ADR 0583).
///
/// An **epoch day** is the count of whole days since 1970-01-01 on the UTC
/// timeline. The calendar date is read in **local** time (the day the user
/// experienced) and then anchored at UTC midnight, so:
///
/// * consecutive local calendar days are exactly 1 apart — streak and history
///   maths stays pure integer arithmetic, with no DST or timezone drift;
/// * the integer is the *true* epoch day in every timezone.
///
/// The bug this type replaces: `DateTime(y, m, d).millisecondsSinceEpoch ~/
/// Duration.millisecondsPerDay` anchored the date at **local** midnight, which
/// east of UTC falls *before* the epoch-day boundary, so the truncating
/// division answered `trueDay - 1` (measured on a UTC+2 box: 2026-09-18 →
/// 20713, true 20714). West of UTC it happened to be right, which is why the
/// off-by-one survived four copy-pasted definitions.
abstract final class EpochDay {
  /// The epoch day of the bare calendar date [year]-[month]-[day].
  ///
  /// This is the primitive: a calendar date carries no time and no zone, so
  /// the anchor is UTC midnight and the result depends on nothing else.
  static int ofCalendarDate(int year, int month, int day) =>
      DateTime.utc(year, month, day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// The epoch day of the calendar date [when] falls on in **local** time.
  static int of(DateTime when) {
    final local = when.toLocal();
    return ofCalendarDate(local.year, local.month, local.day);
  }

  /// The epoch day [instant] falls on for a device whose clock is [utcOffset]
  /// from UTC.
  ///
  /// The deterministic seam (AGENTS.md §10 — "determinisztikus clock fake"):
  /// [of] is this function evaluated at the device's own offset, so a test can
  /// pin the east-of-UTC and west-of-UTC behaviour without the box's timezone.
  static int ofInstant(DateTime instant, Duration utcOffset) {
    final shifted = instant.toUtc().add(utcOffset);
    return ofCalendarDate(shifted.year, shifted.month, shifted.day);
  }

  /// The UTC-midnight instant that names [epochDay] — the inverse used wherever
  /// an epoch day has to become a `DateTime` again (weekday rendering).
  static DateTime utcMidnightOf(int epochDay) =>
      DateTime.fromMillisecondsSinceEpoch(
        epochDay * Duration.millisecondsPerDay,
        isUtc: true,
      );

  /// The **local** start of [epochDay] — the inverse that round-trips through
  /// [of] in every timezone (`of(localStartOf(d)) == d`), unlike
  /// [utcMidnightOf], whose local calendar date is the previous day west of
  /// UTC. Use this when the reconstructed instant is fed back into a
  /// local-calendar conversion.
  static DateTime localStartOf(int epochDay) {
    final utc = utcMidnightOf(epochDay);
    return DateTime(utc.year, utc.month, utc.day);
  }
}
