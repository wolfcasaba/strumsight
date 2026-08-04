import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/progress/song_progress_aggregator.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_progress_committer.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_practice_record.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_progress_repository.dart';
import 'package:strumsight/features/streak/public.dart';

import '../../../support/preference_store.dart';

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

  test(
    'production credit recorder skips playback-only streak credit and records scored practice once',
    () async {
      final container = ProviderContainer(
        overrides: [
          preferenceStoreOverride(InMemoryKeyValueStore()),
          streakProvider.overrideWith(_CountingStreakController.new),
        ],
      );
      addTearDown(container.dispose);
      final streak =
          container.read(streakProvider.notifier) as _CountingStreakController;
      final recorder = PracticeSessionSongCreditRecorder(
        recording: container.read(practiceSessionRecordingProvider),
        dailyGoalMinutes: 10,
      );

      final playbackOutcome = await recorder.record(
        _creditRecord(id: 'production-playback', playbackOnly: true),
      );

      expect(playbackOutcome.streakCredited, isFalse);
      expect(streak.recordPracticeTodayCalls, 0);

      final scoredOutcome = await recorder.record(
        _creditRecord(id: 'production-scored'),
      );

      expect(scoredOutcome.streakCredited, isTrue);
      expect(streak.recordPracticeTodayCalls, 1);
    },
  );
}

SongPracticeRecord _creditRecord({
  required String id,
  bool playbackOnly = false,
}) {
  return SongPracticeRecord(
    id: id,
    songId: SongId('song-a'),
    songRevision: 1,
    source: const SongProgressSource(
      measureId: 'm1',
      eventId: 'e1',
      measureIndex: 0,
    ),
    activeDuration: const Duration(seconds: 30),
    completed: true,
    score: 1,
    recordedAt: DateTime.utc(2026, 8, 4),
    playbackOnly: playbackOnly,
  );
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

final class _CountingStreakController extends StreakController {
  int recordPracticeTodayCalls = 0;

  @override
  Future<bool> recordPracticeToday([DateTime? now]) {
    recordPracticeTodayCalls++;
    return super.recordPracticeToday(now);
  }
}
