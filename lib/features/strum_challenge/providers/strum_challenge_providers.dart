import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/strum_challenge_best_repository.dart';
import '../model/strum_challenge_best.dart';

/// The clock the daily best is keyed on. A provider, not a `DateTime.now()`
/// call, so a test can move the calendar and prove that a new day resets the
/// best — the one behaviour that cannot otherwise be tested without waiting.
final strumChallengeClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Today's best of the 60-second strum challenge, or null when nothing has
/// been recorded TODAY. A record from an earlier day is not surfaced: the
/// challenge is a per-day goal, and yesterday's number would be a best to
/// beat that the learner cannot see the day of.
///
/// Read synchronously in [build] (the streak's E01-R07 pattern), so a record
/// made on a cold start never lands on top of an unread stored one.
class StrumChallengeBestController extends Notifier<StrumChallengeBest?> {
  StrumChallengeBestRepository get _repo =>
      ref.read(strumChallengeBestRepositoryProvider);

  String get _todayKey =>
      StrumChallengeBest.dateKeyOf(ref.read(strumChallengeClockProvider)());

  @override
  StrumChallengeBest? build() {
    final stored = _repo.load();
    if (stored == null || stored.dateKey != _todayKey) return null;
    return stored;
  }

  /// Record one finished, reportable run. Returns true when [score] is a new
  /// best for today — the first scoring run of the day included, provided it
  /// scored at all.
  ///
  /// The state is updated BEFORE the write is awaited, so the screen sees the
  /// new best immediately; the write itself is the document store's job,
  /// which logs a platform refusal rather than swallowing it.
  Future<bool> recordAttempt({
    required int score,
    required int patterns,
  }) async {
    final today = _todayKey;
    final previous = state;
    // The state was built for the day the controller was created on. If the
    // date has rolled over while the app stayed open, the old record does not
    // carry into the new day.
    final current = previous != null && previous.dateKey == today
        ? previous
        : null;
    final bool isNewBest;
    final int bestScore;
    final int bestPatterns;
    if (current == null) {
      isNewBest = score > 0;
      bestScore = score;
      bestPatterns = patterns;
    } else if (score > current.bestScore) {
      isNewBest = true;
      bestScore = score;
      bestPatterns = patterns;
    } else {
      isNewBest = false;
      bestScore = current.bestScore;
      bestPatterns = current.bestPatterns;
    }
    final next = StrumChallengeBest(
      dateKey: today,
      bestScore: bestScore,
      bestPatterns: bestPatterns,
      attempts: (current?.attempts ?? 0) + 1,
    );
    state = next;
    await _repo.save(next);
    return isNewBest;
  }
}

/// Today's best, or null before the first scoring run of the day.
final strumChallengeBestProvider =
    NotifierProvider<StrumChallengeBestController, StrumChallengeBest?>(
      StrumChallengeBestController.new,
    );
