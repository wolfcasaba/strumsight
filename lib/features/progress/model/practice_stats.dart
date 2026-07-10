import 'package:flutter/foundation.dart';

import 'practice_entry.dart';

/// One day's rolled-up practice, used by the weekly chart.
@immutable
class DayTotal {
  const DayTotal({required this.day, required this.seconds, required this.sessions});

  /// Epoch day (local midnight).
  final int day;

  /// Total practice seconds recorded on this day.
  final int seconds;

  /// Distinct practice moments recorded on this day.
  final int sessions;

  bool get isEmpty => sessions == 0;
}

/// Pure, testable rollups over the raw [PracticeEntry] history. Everything the
/// Progress dashboard shows is derived here so the widget stays dumb and the
/// maths is unit-tested with an injectable `today`.
@immutable
class PracticeStats {
  const PracticeStats(this.entries);

  final List<PracticeEntry> entries;

  int get totalSessions => entries.length;

  int get totalSeconds =>
      entries.fold(0, (sum, e) => sum + (e.seconds < 0 ? 0 : e.seconds));

  int get totalStrokes =>
      entries.fold(0, (sum, e) => sum + (e.strokes < 0 ? 0 : e.strokes));

  /// Distinct calendar days that hold at least one entry.
  int get daysPracticed => entries.map((e) => e.day).toSet().length;

  int sessionsFrom(PracticeSource source) =>
      entries.where((e) => e.source == source).length;

  /// Total practice seconds recorded on [day] (an epoch day). Drives the daily
  /// goal ring.
  int secondsForDay(int day) => entries
      .where((e) => e.day == day)
      .fold(0, (sum, e) => sum + (e.seconds < 0 ? 0 : e.seconds));

  /// Average strum-direction accuracy across scored runs (0..1), or null if none
  /// scored yet. THE headline "better than competitors" metric.
  double? get averageDirectionAccuracy {
    final scored =
        entries.where((e) => e.directionAccuracy != null).toList(growable: false);
    if (scored.isEmpty) return null;
    final sum = scored.fold<double>(0, (s, e) => s + e.directionAccuracy!);
    return sum / scored.length;
  }

  /// Best single scored strum-direction accuracy (0..1), or null if none.
  double? get bestDirectionAccuracy {
    double? best;
    for (final e in entries) {
      final a = e.directionAccuracy;
      if (a != null && (best == null || a > best)) best = a;
    }
    return best;
  }

  /// The last [days] calendar days ending at [today] (inclusive), oldest-first,
  /// each with its rolled-up seconds/sessions (zero-filled for idle days). Drives
  /// the weekly bar chart.
  List<DayTotal> lastDays(int today, {int days = 7}) {
    final secByDay = <int, int>{};
    final sessByDay = <int, int>{};
    for (final e in entries) {
      secByDay[e.day] = (secByDay[e.day] ?? 0) + (e.seconds < 0 ? 0 : e.seconds);
      sessByDay[e.day] = (sessByDay[e.day] ?? 0) + 1;
    }
    return [
      for (var i = days - 1; i >= 0; i--)
        DayTotal(
          day: today - i,
          seconds: secByDay[today - i] ?? 0,
          sessions: sessByDay[today - i] ?? 0,
        ),
    ];
  }
}
