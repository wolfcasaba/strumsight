import 'package:strumsight/features/streak/public.dart';

import '../tutor_context_snapshot.dart';

/// Public-safe scalar state supplied by the Streak feature's public provider.
final class StreakContextInput {
  const StreakContextInput({
    required this.currentDays,
    required this.longestDays,
    required this.bankedFreezes,
    required this.practicedToday,
    this.dailyChallenge,
  });

  final int currentDays;
  final int longestDays;
  final int bankedFreezes;
  final bool practicedToday;
  final DailyChallenge? dailyChallenge;
}

/// Projects a small streak summary without depending on Streak internals.
final class StreakContextAdapter {
  const StreakContextAdapter({this.schemaVersion});

  final String? schemaVersion;

  TutorContextField? adapt(StreakContextInput input) {
    if (schemaVersion == null) return null;
    return TutorContextField.available(
      key: TutorContextFieldKey.streak,
      values: <String, Object?>{
        'currentDays': input.currentDays,
        'longestDays': input.longestDays,
        'bankedFreezes': input.bankedFreezes,
        'practicedToday': input.practicedToday,
        if (input.dailyChallenge != null) ...<String, Object?>{
          'dailyChallengeDay': input.dailyChallenge!.day,
          'dailyChallengeName': input.dailyChallenge!.name,
          'dailyChallengeStrumCount': input.dailyChallenge!.pattern.length,
        },
      },
      provenance: ContextProvenance(
        sourceFeature: ContextSourceFeature.streak,
        schemaVersion: schemaVersion,
      ),
    );
  }
}
