import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/streak/public.dart';

import '../../domain/quests/challenge_definition.dart';

/// Wraps the shipping legacy [DailyChallenge] generator as a V2 challenge
/// definition (ADR 0387 Decision 1 — legacy adapter HÍVJA, nem reprodukálja).
///
/// The adapter **calls** the legacy `DailyChallenge.forDay` factory so the
/// generated pattern is byte-identical with the value the existing
/// `test/features/streak/daily_challenge_test.dart` suite already locks down.
/// Copying the generation formula into a new file would diverge on the first
/// edit and silently break the user's muscle memory.
final class LegacyDailyChallengeAdapter {
  const LegacyDailyChallengeAdapter();

  /// Produces the legacy strum-pattern challenge for [epochDay] as a V2
  /// [StrumPatternChallenge] definition. The bit-exact [StrumDirection]
  /// sequence and rotating [name] come straight from
  /// [DailyChallenge.forDay].
  StrumPatternChallenge forDay(int epochDay) {
    final DailyChallenge legacy = DailyChallenge.forDay(epochDay);
    return StrumPatternChallenge(
      pattern: List<StrumDirection>.unmodifiable(legacy.pattern),
      name: legacy.name,
    );
  }
}
