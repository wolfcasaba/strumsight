import 'package:flutter/foundation.dart';

/// Persisted practice-streak state. Days are stored as an integer **epoch day**
/// (local-midnight days since the Unix epoch) so streak maths is pure integer
/// arithmetic — no timezone/DST drift inside the logic (see streak_logic.dart).
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
  }) =>
      StreakData(
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

  factory StreakData.fromJson(Map<String, dynamic> j) => StreakData(
        current: (j['current'] as num?)?.toInt() ?? 0,
        longest: (j['longest'] as num?)?.toInt() ?? 0,
        lastPracticeDay: (j['last'] as num?)?.toInt() ?? -1,
        freezes: (j['freezes'] as num?)?.toInt() ?? 0,
        totalDays: (j['total'] as num?)?.toInt() ?? 0,
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
