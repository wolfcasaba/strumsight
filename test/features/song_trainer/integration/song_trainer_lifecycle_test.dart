// End-to-end coverage for the Song Trainer V2 commit + resume boundaries.
//
// E03-R21 brief §6 acceptance "duplicate finalize/re-entry egyszer commitol;
// resume stabil; revision-mismatch -> explicit invalidáció".

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_progress_committer.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_resume_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';

void main() {
  group('Song Trainer boundary integration', () {
    test(
      'duplicate finalize callbacks collapse to one recorder write',
      () async {
        final sink = _CountingSink();
        final committer = SongProgressCommitter(
          sessionRecorder: _CountingRecorder(sink),
        );

        final result = _result();
        await Future.wait<void>(<Future<void>>[
          committer.commit(
            idempotencyKey: 'song|song|attempt|1',
            sessionResult: result,
          ),
          committer.commit(
            idempotencyKey: 'song|song|attempt|1',
            sessionResult: result,
          ),
          committer.commit(
            idempotencyKey: 'song|song|attempt|1',
            sessionResult: result,
          ),
        ]);

        expect(sink.recordCalls, 1);
      },
    );

    test(
      'resume checkpoint is reusable across re-entry once revision matches',
      () async {
        final repo = _InMemoryResumeRepository();
        await repo.save(
          SongResumeCheckpoint(
            songId: SongId('song'),
            songRevision: 1,
            range: MeasureRange(start: 0, endExclusive: 1),
            attemptCounter: 2,
            resumedFrom: const Duration(milliseconds: 250),
            recordedAt: DateTime.utc(2026, 8, 4),
          ),
        );

        final first = await repo.load(songId: SongId('song'), revision: 1);
        final second = await repo.load(songId: SongId('song'), revision: 1);
        expect(first.isSuccess, isTrue);
        expect(second.isSuccess, isTrue);
        expect(first.valueOrNull!.attemptCounter, 2);
        expect(second.valueOrNull!.attemptCounter, 2);
      },
    );

    test(
      're-entry after revision bump explicitly invalidates the checkpoint',
      () async {
        final repo = _InMemoryResumeRepository();
        await repo.save(
          SongResumeCheckpoint(
            songId: SongId('song'),
            songRevision: 1,
            range: MeasureRange(start: 0, endExclusive: 1),
            attemptCounter: 4,
            resumedFrom: const Duration(milliseconds: 500),
            recordedAt: DateTime.utc(2026, 8, 4),
          ),
        );

        final loaded = await repo.load(songId: SongId('song'), revision: 2);
        expect(loaded.isFailure, isTrue);
        expect(
          (loaded as Failure).error.code,
          SongResumeFailureCode.revisionMismatch,
        );
      },
    );

    test(
      'committer survives a dispose raised between producer calls',
      () async {
        final sink = _CountingSink();
        final committer = SongProgressCommitter(
          sessionRecorder: _CountingRecorder(sink),
        );
        await committer.dispose();
        final outcome = await committer.commit(
          idempotencyKey: 'song|song|attempt|dispose',
          sessionResult: _result(),
        );
        expect(outcome.isFailure, isTrue);
        expect(sink.recordCalls, 0);
      },
    );
  });
}

PracticeSessionResult _result() => PracticeSessionResult(
  id: 'practice-result',
  activeDuration: const Duration(seconds: 4),
  pausedDuration: Duration.zero,
  attempts: const <PracticeAttemptResult>[],
  finishReason: PracticeFinishReason.completedAllTargets,
  highestStableTempo: null,
  coachingSummary: const <String>[],
);

final class _CountingSink {
  int recordCalls = 0;
}

class _CountingRecorder implements PracticeSessionRecorder {
  _CountingRecorder(this._sink);

  final _CountingSink _sink;

  @override
  Future<AppResult<void>> record(PracticeSessionResult sessionResult) async {
    _sink.recordCalls++;
    return const AppResult<void>.success(null);
  }
}

final class _InMemoryResumeRepository implements SongResumeRepository {
  final Map<String, SongResumeCheckpoint> _store =
      <String, SongResumeCheckpoint>{};

  String _key(SongId songId, int revision) => '${songId.value}@$revision';

  @override
  Future<AppResult<SongResumeCheckpoint>> load({
    required SongId songId,
    required int revision,
  }) async {
    final exact = _store[_key(songId, revision)];
    if (exact != null) {
      return AppResult<SongResumeCheckpoint>.success(exact);
    }
    final otherRevision = _store.values
        .where((checkpoint) => checkpoint.songId == songId)
        .firstOrNull;
    if (otherRevision != null) {
      return AppResult<SongResumeCheckpoint>.failure(
        const StorageFailure(code: SongResumeFailureCode.revisionMismatch),
      );
    }
    return AppResult<SongResumeCheckpoint>.failure(
      const StorageFailure(code: SongResumeFailureCode.noCheckpoint),
    );
  }

  @override
  Future<AppResult<void>> save(SongResumeCheckpoint checkpoint) async {
    _store[_key(checkpoint.songId, checkpoint.songRevision)] = checkpoint;
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> discard({
    required SongId songId,
    required int revision,
  }) async {
    _store.remove(_key(songId, revision));
    return const AppResult<void>.success(null);
  }
}
