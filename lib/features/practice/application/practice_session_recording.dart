import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../progress/public.dart';
import '../../streak/public.dart';
import '../domain/model/practice_session_result.dart' as presult;
import '../domain/service/practice_session_eligibility.dart';

/// Snapshot of the three numbers the streak-jogosultsági predicate needs
/// (SDD §20.5, ADR 0085 Döntés 4).
///
/// Wraps [PracticeSessionEligibilityInput] with one renamable, public-facing
/// surface so the recording use case does not have to depend on the domain
/// service directly in callers.
@immutable
final class SessionEligibilitySnapshot {
  const SessionEligibilitySnapshot({
    required this.activeDuration,
    required this.resolvedRequiredTargets,
    required this.freePracticeStrums,
  });

  final Duration activeDuration;
  final int resolvedRequiredTargets;
  final int freePracticeStrums;

  PracticeSessionEligibilityInput toInput() => PracticeSessionEligibilityInput(
    activeDuration: activeDuration,
    resolvedRequiredTargets: resolvedRequiredTargets,
    freePracticeStrums: freePracticeStrums,
  );
}

/// Inputs needed to write ONE practice moment to the progress log + streak.
///
/// Lives at the application layer so the recording use case can be driven
/// from any session shape (Learn, Live, Analyze, Free Practice). All fields
/// are pure values — no Riverpod snapshots, no clocks, no repositories.
@immutable
final class PracticeRecordingRequest {
  const PracticeRecordingRequest({
    required this.lessonId,
    required this.eligibility,
    required this.eligible,
    required this.activeDuration,
    required this.elapsedSeconds,
    required this.strokes,
    required this.chords,
    required this.directionAccuracy,
    required this.finishedAt,
  });

  /// Identifier of the lesson/play-along that this moment came from. The
  /// Learn screen passes its `Lesson.id`; non-Learn callers pass a synthetic
  /// `live-*` / `analyze-*` identifier.
  final String lessonId;

  /// The three numbers the canonical streak-eligibility predicate evaluates
  /// against. The use case re-evaluates through
  /// [PracticeSessionEligibility.isEligible] on every call so a caller can
  /// never bypass the gate by passing `eligible: true` with empty fields.
  final SessionEligibilitySnapshot eligibility;

  /// Caller-side coarse gate: an aborted / never-started session reports
  /// `false` and skips the entire use case.
  final bool eligible;

  /// The session's ACTIVE time (in which the runner accumulated real play).
  /// Drives the streak-eligibility predicate AND the "added seconds" budget
  /// for the daily goal.
  final Duration activeDuration;

  /// Wall-clock seconds the runner spent on screen (count-in + pause + result
  /// included). Recorded so the dashboard's V1 log keeps its existing meaning
  /// (a "moment" includes setup) — the active-time budget still gates
  /// streak/daily-goal progress.
  final int elapsedSeconds;

  final int strokes;
  final int chords;
  final double? directionAccuracy;

  /// Local "now" used to compute the streak's epoch day (SDD §20.5).
  final DateTime finishedAt;
}

/// The output of the recording use case: tells the caller what was logged,
/// whether the streak advanced, and whether the daily-goal budget moved.
@immutable
final class PracticeRecordingOutcome {
  const PracticeRecordingOutcome({
    required this.loggedEntry,
    required this.streakAdvanced,
    required this.addedActiveSeconds,
  });

  /// The [PracticeEntry] appended to the V1 log, when a moment actually qualified
  /// (was a real play moment AND the caller marked the run as learnt). `null`
  /// when the request did not qualify — for example, a Learn session that
  /// produced zero strokes, or a non-Learn call we choose not to write.
  final PracticeEntry? loggedEntry;

  /// True iff the streak controller advanced the streak (the caller's first
  /// eligible session of the day). Idempotent — the second eligible call of
  /// the same day reports `false` and does NOT change state (A4 last cell).
  final bool streakAdvanced;

  /// Seconds added to the "active today" budget used by the daily-goal ring.
  /// Zero for cancelled / below-threshold / non-active sessions (A5 first row).
  final int addedActiveSeconds;
}

/// Pure use-case: convert a finished practice moment into the right side
/// effects on the V1 practice log, the streak, and the daily-goal budget
/// (ADR 0085 Döntés 4 + 5 + 6, brief A4–A6).
///
/// Lives at the application layer so its callers (Learn screen, Live screen,
/// result screen) can drive it through one stable interface. The use case
/// owns eligibility and easy-mode-not-overwrite rules; the streak/daily-goal
/// providers below own the persistence-only side effects.
class PracticeSessionRecording {
  const PracticeSessionRecording({
    required this.eligibility,
    required this.streak,
    required this.practiceLog,
    required this.now,
  });

  /// Predicate — pure, deterministic (R16, ADR 0085 Döntés 4).
  final PracticeSessionEligibility eligibility;

  /// Streak controller — its idempotent [StreakController.recordPracticeToday]
  /// decides whether the day "advanced"; the use case does not re-implement
  /// that logic.
  final StreakController streak;

  /// The V1 practice log notifier. The use case never reads the log —
  /// appending only — so a caller override can never produce a stale read.
  final PracticeLogController practiceLog;

  /// Injectable clock so tests are deterministic.
  final DateTime Function() now;

  /// Apply [request] and return the recorded outcome.
  Future<PracticeRecordingOutcome> record(
    PracticeRecordingRequest request,
  ) async {
    // 1. Eligibility gate (Döntés 4, A4): short of the predicate's thresholds
    //    → silent no-op, no streak credit, no daily-goal credit. We still
    //    surface a non-null `loggedEntry` *only* when the caller signals the
    //    moment actually happened (i.e. the V1 log gets a record only when the
    //    runner produced a real session, not a tap→back).
    final input = PracticeSessionEligibilityInput(
      activeDuration: request.activeDuration,
      resolvedRequiredTargets: request.eligibility.resolvedRequiredTargets,
      freePracticeStrums: request.eligibility.freePracticeStrums,
    );
    final isEligible = eligibility.isEligible(input);
    if (!request.eligible || !isEligible) {
      return const PracticeRecordingOutcome(
        loggedEntry: null,
        streakAdvanced: false,
        addedActiveSeconds: 0,
      );
    }

    // 2. Append to the V1 practice log (only when the moment contains actual
    //    activity — easy/full-empty Learn calls are filtered above). The
    //    seconds/strokes/chords come from the runner, not the wall clock
    //    (count-in + pause + setup never bleed in here).
    final entry = PracticeEntry(
      day: StreakLogic.epochDayOf(request.finishedAt),
      source: PracticeSource.learn,
      seconds: request.elapsedSeconds,
      strokes: request.strokes,
      chords: request.chords,
      directionAccuracy: request.directionAccuracy,
    );
    await practiceLog.record(entry);

    // 3. Streak credit — passes `now` through; the controller returns true
    //    only on first eligible record of the day (idempotencia megmarad).
    final streakAdvanced = await streak.recordPracticeToday(request.finishedAt);

    return PracticeRecordingOutcome(
      loggedEntry: entry,
      streakAdvanced: streakAdvanced,
      // Daily-goal budget counts ACTIVE seconds only — the brief A5 rule.
      addedActiveSeconds: request.activeDuration.inSeconds,
    );
  }
}

/// Riverpod binding for the recording use case.
///
/// Overriding the individual sub-providers (eligibility, streak, practiceLog)
/// is enough for tests to drive the use case deterministically; they don't have
/// to swap out this whole provider.
final practiceSessionRecordingProvider = Provider<PracticeSessionRecording>((
  ref,
) {
  return PracticeSessionRecording(
    eligibility: ref.watch(practiceSessionEligibilityProvider),
    streak: ref.watch(streakProvider.notifier),
    practiceLog: ref.watch(practiceLogProvider.notifier),
    now: DateTime.now,
  );
});

/// The eligibility predicate wrapped in a Riverpod-visible provider.
///
/// Kept separate so tests can override just this and re-use the streak + log
/// providers from production.
final practiceSessionEligibilityProvider = Provider<PracticeSessionEligibility>(
  (_) => const PracticeSessionEligibility(),
);

/// Re-export the practice session result type so callers can `import
/// 'practice_session_recording.dart'; … presult.PracticeSessionResult` without
/// reaching into the domain path.
typedef PracticeResult = presult.PracticeSessionResult;
