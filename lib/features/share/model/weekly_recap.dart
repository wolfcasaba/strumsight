import 'dart:math' as math;

import '../../progress/model/practice_entry.dart';

/// One week of practice, rolled up for the shareable "Strum Wrapped" card
/// (RAG chunk 017 rec #5 — the Duolingo-Wrapped-style recap is the category's
/// strongest install hook). Pure and clock-injected like `PracticeStats`.
class WeeklyRecap {
  const WeeklyRecap({
    required this.minutes,
    required this.sessions,
    required this.strokes,
    required this.daysPracticed,
    required this.bestDay,
    required this.averageAccuracy,
    required this.streak,
  });

  /// Roll up the 7 days ending at [today] (inclusive, epoch days).
  factory WeeklyRecap.fromEntries(
    List<PracticeEntry> entries, {
    required int today,
    int streak = 0,
  }) {
    final start = today - 6;
    final week =
        entries.where((e) => e.day >= start && e.day <= today).toList();
    var seconds = 0, strokes = 0;
    final byDay = <int, int>{};
    double accSum = 0;
    var accN = 0;
    for (final e in week) {
      seconds += e.seconds;
      strokes += e.strokes;
      byDay[e.day] = (byDay[e.day] ?? 0) + e.seconds;
      final a = e.directionAccuracy;
      if (a != null) {
        accSum += a;
        accN++;
      }
    }
    int? best;
    var bestSeconds = 0;
    byDay.forEach((day, s) {
      if (s > bestSeconds) {
        bestSeconds = s;
        best = day;
      }
    });
    return WeeklyRecap(
      // Floor at 1 when ANY practice happened: a 27-second first win must
      // never brag "0 minutes" (r158 edge; rounding stays honest above that).
      minutes: seconds == 0 ? 0 : math.max(1, (seconds / 60).round()),
      sessions: week.length,
      strokes: strokes,
      daysPracticed: byDay.keys.length,
      bestDay: best,
      averageAccuracy: accN == 0 ? null : accSum / accN,
      streak: streak,
    );
  }

  final int minutes;
  final int sessions;
  final int strokes;

  /// Distinct days with practice this week (0–7).
  final int daysPracticed;

  /// Epoch day of the most-practised day, or null for an empty week.
  final int? bestDay;

  /// Mean strum-direction accuracy over the week's scored runs (the moat
  /// metric), or null when nothing was scored.
  final double? averageAccuracy;

  /// The CURRENT streak at share time (not clamped to the week).
  final int streak;

  bool get isEmpty => sessions == 0;
}
