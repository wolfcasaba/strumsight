import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/progress/song_progress_aggregator.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_progress_committer.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_practice_record.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_progress_repository.dart';

void main() {
  test(
    'duplicate terminal callback commits record, history, daily goal and streak once',
    () async {
      final progress = _CountingProgressRepository();
      final history = _CountingHistoryRecorder();
      final credits = _CountingCreditRecorder();
      final integrator = SongProgressTerminalIntegrator(
        progressRepository: progress,
        historyCommitter: SongProgressCommitter(sessionRecorder: history),
        creditRecorder: credits,
      );
      final record = SongPracticeRecord(
        id: 'terminal-1',
        songId: SongId('song-a'),
        songRevision: 1,
        source: const SongProgressSource(
          measureId: 'm1',
          eventId: 'e1',
          measureIndex: 0,
        ),
        activeDuration: const Duration(seconds: 15),
        completed: true,
        score: 0.9,
        recordedAt: DateTime.utc(2026, 8, 4),
      );
      final sessionResult = PracticeSessionResult(
        id: 'practice-session-1',
        activeDuration: const Duration(seconds: 15),
        pausedDuration: Duration.zero,
        attempts: const <PracticeAttemptResult>[],
        finishReason: PracticeFinishReason.completedAllTargets,
        highestStableTempo: null,
        coachingSummary: const <String>[],
      );

      final outcomes =
          await Future.wait(<Future<SongProgressTerminalCommitOutcome>>[
            integrator.commit(
              idempotencyKey: 'terminal-1',
              record: record,
              sessionResult: sessionResult,
            ),
            integrator.commit(
              idempotencyKey: 'terminal-1',
              record: record,
              sessionResult: sessionResult,
            ),
          ]);

      expect(outcomes.every((outcome) => outcome.isSuccess), isTrue);
      expect(progress.saves, 1);
      expect(history.records, 1);
      expect(credits.calls, 1);
      expect(credits.streakCredits, 1);
      expect(credits.dailyGoalCredits, 1);
    },
  );

  test('playback-only terminal leaves streak credit at zero', () async {
    final credits = _CountingCreditRecorder();
    final outcome = await credits.record(
      SongPracticeRecord(
        id: 'playback',
        songId: SongId('song-a'),
        songRevision: 1,
        source: const SongProgressSource(
          measureId: 'm1',
          eventId: 'e1',
          measureIndex: 0,
        ),
        activeDuration: const Duration(seconds: 15),
        completed: true,
        score: 1,
        recordedAt: DateTime.utc(2026, 8, 4),
        playbackOnly: true,
      ),
    );

    expect(outcome.streakCredited, isFalse);
    expect(credits.streakCredits, 0);
  });
}

final class _CountingProgressRepository implements SongProgressRepository {
  int saves = 0;

  @override
  Future<AppResult<List<SongPracticeRecord>>> load({
    SongId? songId,
    int? revision,
  }) async => const Success<List<SongPracticeRecord>>(<SongPracticeRecord>[]);

  @override
  Future<AppResult<void>> save(SongPracticeRecord record) async {
    saves++;
    return const Success<void>(null);
  }
}

final class _CountingHistoryRecorder implements PracticeSessionRecorder {
  int records = 0;

  @override
  Future<AppResult<void>> record(PracticeSessionResult result) async {
    records++;
    return const Success<void>(null);
  }
}

final class _CountingCreditRecorder implements SongPracticeCreditRecorder {
  int calls = 0;
  int streakCredits = 0;
  int dailyGoalCredits = 0;

  @override
  Future<SongPracticeCreditOutcome> record(SongPracticeRecord record) async {
    calls++;
    if (!record.playbackOnly) {
      streakCredits++;
      dailyGoalCredits++;
    }
    return SongPracticeCreditOutcome(
      streakCredited: !record.playbackOnly,
      dailyGoalActiveSeconds: record.playbackOnly
          ? 0
          : record.activeDuration.inSeconds,
    );
  }
}
