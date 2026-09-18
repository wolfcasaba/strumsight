import 'package:flutter/foundation.dart';

import '../../../core/foundation/json_validation.dart';

/// Persisted practice-streak state. Days are stored as an integer **epoch day**
/// — the user's LOCAL calendar date, anchored at UTC midnight (`EpochDay`,
/// ADR 0583) — so streak maths is pure integer arithmetic and consecutive
/// local days are exactly 1 apart, with no timezone/DST drift inside the logic
/// (see streak_logic.dart).
///
/// The anchor is deliberately UTC and not local midnight: local midnight east
/// of UTC falls *before* the epoch-day boundary, which is what made the old
/// conversion store `trueDay - 1` there. Schema 23 repairs the days written
/// that way.
@immutable
class StreakData {
  const StreakData({
    this.current = 0,
    this.longest = 0,
    this.lastPracticeDay = -1,
    this.freezes = 0,
    this.totalDays = 0,
  });

  /// Consecutive practice days ending on [lastPracticeDay].
  final int current;

  /// Best streak ever reached.
  final int longest;

  /// Epoch day of the most recent practice, or -1 if never practiced.
  final int lastPracticeDay;

  /// Available streak-freezes (each covers one missed day). Trophy's data:
  /// streak-freeze lifts the average streak +48% — the highest-leverage knob.
  final int freezes;

  /// Total distinct days practiced (drives freeze awards).
  final int totalDays;

  bool get hasStreak => current > 0;

  StreakData copyWith({
    int? current,
    int? longest,
    int? lastPracticeDay,
    int? freezes,
    int? totalDays,
  }) => StreakData(
    current: current ?? this.current,
    longest: longest ?? this.longest,
    lastPracticeDay: lastPracticeDay ?? this.lastPracticeDay,
    freezes: freezes ?? this.freezes,
    totalDays: totalDays ?? this.totalDays,
  );

  Map<String, dynamic> toJson() => {
    'current': current,
    'longest': longest,
    'last': lastPracticeDay,
    'freezes': freezes,
    'total': totalDays,
  };

  /// Decode the persisted streak (Kör 7 §7.1). Every counter is validated as
  /// non-negative; `last` keeps its "-1 = never practised" sentinel.
  factory StreakData.fromJson(Map<String, dynamic> j) => StreakData(
    current: optionalInt(j, 'current', fallback: 0),
    longest: optionalInt(j, 'longest', fallback: 0),
    lastPracticeDay: optionalInt(j, 'last', fallback: -1, min: -1),
    freezes: optionalInt(j, 'freezes', fallback: 0),
    totalDays: optionalInt(j, 'total', fallback: 0),
  );

  @override
  bool operator ==(Object other) =>
      other is StreakData &&
      other.current == current &&
      other.longest == longest &&
      other.lastPracticeDay == lastPracticeDay &&
      other.freezes == freezes &&
      other.totalDays == totalDays;

  @override
  int get hashCode =>
      Object.hash(current, longest, lastPracticeDay, freezes, totalDays);
}
