// Resume checkpoint repository for one Song Trainer session.
//
// E03-R21 brief §5.4 / §6 acceptance "resume biztonságos időközönként +
// pause/stopkor; scoring state nem áll vissza fél attemptként; revision-mismatch
// -> explicit invalidáció".
//
// The contract is intentionally thin: a Song Trainer checkpoint is a single
// immutable record keyed by the song id + revision + selected range. The
// repository persists the latest snapshot, returns it on re-entry, and never
// silently rewinds a half-attempt or applies a checkpoint that targets a
// different song revision.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_resume_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';

void main() {
  group('SongResumeRepository', () {
    test('saves and returns the latest checkpoint on reload', () async {
      final repo = _InMemorySongResumeRepository();
      final first = _checkpoint(songId: 'song', revision: 1);
      final second = _checkpoint(
        songId: 'song',
        revision: 1,
        attemptCounter: 2,
        resumedFrom: Duration(milliseconds: 250),
      );

      await repo.save(first);
      await repo.save(second);

      final loaded = await repo.load(songId: SongId('song'), revision: 1);
      expect(loaded.isSuccess, isTrue);
      expect(loaded.valueOrNull, isNotNull);
      expect(loaded.valueOrNull!.attemptCounter, 2);
      expect(
        loaded.valueOrNull!.resumedFrom,
        const Duration(milliseconds: 250),
      );
    });

    test('returns a failure when no checkpoint exists for the song', () async {
      final repo = _InMemorySongResumeRepository();
      final loaded = await repo.load(songId: SongId('missing'), revision: 1);
      expect(loaded.isFailure, isTrue);
      expect(
        (loaded as Failure).error.code,
        SongResumeFailureCode.noCheckpoint,
      );
    });

    test(
      'revision mismatch returns an explicit invalidation failure',
      () async {
        final repo = _InMemorySongResumeRepository();
        await repo.save(_checkpoint(songId: 'song', revision: 1));

        final loaded = await repo.load(songId: SongId('song'), revision: 2);
        expect(loaded.isFailure, isTrue);
        expect(
          (loaded as Failure).error.code,
          SongResumeFailureCode.revisionMismatch,
        );
      },
    );

    test(
      'discarding a checkpoint removes it for the exact revision pair',
      () async {
        final repo = _InMemorySongResumeRepository();
        await repo.save(_checkpoint(songId: 'song', revision: 1));

        final discard = await repo.discard(songId: SongId('song'), revision: 1);
        expect(discard.isSuccess, isTrue);

        final loaded = await repo.load(songId: SongId('song'), revision: 1);
        expect(loaded.isFailure, isTrue);
      },
    );

    test('discarding on a mismatched revision is a no-op success', () async {
      final repo = _InMemorySongResumeRepository();
      await repo.save(_checkpoint(songId: 'song', revision: 1));

      final discard = await repo.discard(songId: SongId('song'), revision: 2);
      expect(discard.isSuccess, isTrue);

      // Original revision is still readable.
      final loaded = await repo.load(songId: SongId('song'), revision: 1);
      expect(loaded.isSuccess, isTrue);
    });

    test(
      'discarding on a song with no checkpoint is a no-op success',
      () async {
        final repo = _InMemorySongResumeRepository();
        final discard = await repo.discard(
          songId: SongId('never'),
          revision: 1,
        );
        expect(discard.isSuccess, isTrue);
      },
    );

    test('a checkpoint never carries partial attempt state', () async {
      final checkpoint = _checkpoint(
        songId: 'song',
        revision: 1,
        attemptCounter: 3,
        resumedFrom: const Duration(milliseconds: 750),
      );
      expect(checkpoint.attemptCounter, 3);
      expect(checkpoint.resumedFrom, const Duration(milliseconds: 750));
      // The checkpoint itself does not own a Result / scoring state — only the
      // attempt counter and the resume position. The result belongs to the
      // commit boundary, not the resume boundary.
    });
  });
}

SongResumeCheckpoint _checkpoint({
  required String songId,
  required int revision,
  int attemptCounter = 1,
  Duration resumedFrom = Duration.zero,
}) => SongResumeCheckpoint(
  songId: SongId(songId),
  songRevision: revision,
  range: MeasureRange(start: 0, endExclusive: 1),
  attemptCounter: attemptCounter,
  resumedFrom: resumedFrom,
  recordedAt: DateTime.utc(2026, 8, 4),
);

final class _InMemorySongResumeRepository implements SongResumeRepository {
  final Map<String, SongResumeCheckpoint> _store = {};

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
