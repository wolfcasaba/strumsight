import 'package:flutter/foundation.dart';

import '../../../core/foundation/json_validation.dart';

/// Today's best of the 60-second strum challenge, persisted locally as ONE
/// small object document (the streak pattern). A new day replaces it; nothing
/// accumulates.
@immutable
class StrumChallengeBest {
  const StrumChallengeBest({
    required this.dateKey,
    required this.bestScore,
    required this.bestPatterns,
    required this.attempts,
  });

  /// The local calendar day this record belongs to, `yyyy-MM-dd`.
  final String dateKey;

  /// The best `RhythmAttempt.credited` of the day.
  final int bestScore;

  /// The full-pattern count of the run that set [bestScore].
  final int bestPatterns;

  /// Reportable runs finished today.
  final int attempts;

  /// The `yyyy-MM-dd` key of [now]'s LOCAL calendar day.
  static String dateKeyOf(DateTime now) {
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Map<String, dynamic> toJson() => {
    'dateKey': dateKey,
    'bestScore': bestScore,
    'bestPatterns': bestPatterns,
    'attempts': attempts,
  };

  /// Decode the persisted record. Every counter is validated as non-negative;
  /// a malformed record is rejected as a whole and the caller starts fresh.
  factory StrumChallengeBest.fromJson(Map<String, dynamic> j) =>
      StrumChallengeBest(
        dateKey: requireString(j, 'dateKey', maxLength: 10),
        bestScore: requireInt(j, 'bestScore'),
        bestPatterns: requireInt(j, 'bestPatterns'),
        attempts: requireInt(j, 'attempts'),
      );

  @override
  bool operator ==(Object other) =>
      other is StrumChallengeBest &&
      other.dateKey == dateKey &&
      other.bestScore == bestScore &&
      other.bestPatterns == bestPatterns &&
      other.attempts == attempts;

  @override
  int get hashCode => Object.hash(dateKey, bestScore, bestPatterns, attempts);
}
