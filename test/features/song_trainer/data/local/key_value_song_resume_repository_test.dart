// Javító sáv 2026-09-06 (R8, audit §5.2 "Song resume persistálás").
//
// A1 — a checkpoint written by one repository instance is readable by a
//      FRESH instance over the same store (the app-restart case the
//      in-memory default failed).
// A2 — an absent checkpoint is `noCheckpoint`, a stale one is
//      `revisionMismatch` — the two stay distinguishable after persistence.
// A3 — discard removes exactly one (song, revision) pair.
// A4 — a corrupt document surfaces as a storage-read failure and does NOT
//      block the next save.
// A5 — a store that refuses the write surfaces as a storage-write failure,
//      never a silent no-op.
// A6 — the document stays bounded, keeping the newest checkpoints.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_resume_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/key_value_song_resume_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';

import '../../../../core/storage/in_memory_key_value_store.dart';

void main() {
  group('KeyValueSongResumeRepository', () {
    test('A1 — a checkpoint survives a fresh instance', () async {
      final store = InMemoryKeyValueStore();
      final writer = _open(store);

      final saved = await writer.save(
        _checkpoint(
          songId: 'song',
          revision: 2,
          attemptCounter: 3,
          resumedFrom: const Duration(milliseconds: 250),
        ),
      );
      expect(saved.isSuccess, isTrue);

      // A brand-new repository over the same store == the next app start.
      final loaded = await _load(_open(store), 'song', revision: 2);

      expect(loaded.isSuccess, isTrue);
      final checkpoint = loaded.valueOrNull!;
      expect(checkpoint.attemptCounter, 3);
      expect(checkpoint.resumedFrom, const Duration(milliseconds: 250));
      expect(checkpoint.range, MeasureRange(start: 0, endExclusive: 4));
      expect(checkpoint.songRevision, 2);
    });

    test('A1 — the latest write for a pair wins', () async {
      final store = InMemoryKeyValueStore();
      final writer = _open(store);

      await writer.save(_checkpoint(songId: 'song', revision: 1));
      await writer.save(
        _checkpoint(songId: 'song', revision: 1, attemptCounter: 7),
      );

      final loaded = await _load(_open(store), 'song');
      expect(loaded.valueOrNull!.attemptCounter, 7);
    });

    test('A2 — an absent checkpoint is noCheckpoint', () async {
      final loaded = await _load(_open(InMemoryKeyValueStore()), 'missing');

      expect(loaded.isFailure, isTrue);
      expect(loaded.failureOrNull!.code, SongResumeFailureCode.noCheckpoint);
    });

    test('A2 — a stale revision is revisionMismatch', () async {
      final store = InMemoryKeyValueStore();
      await _open(store).save(_checkpoint(songId: 'song', revision: 1));

      final loaded = await _load(_open(store), 'song', revision: 2);

      expect(loaded.isFailure, isTrue);
      expect(
        loaded.failureOrNull!.code,
        SongResumeFailureCode.revisionMismatch,
      );
    });

    test('A3 — discard removes exactly one revision pair', () async {
      final store = InMemoryKeyValueStore();
      final writer = _open(store);
      await writer.save(_checkpoint(songId: 'song', revision: 1));
      await writer.save(_checkpoint(songId: 'song', revision: 2));

      final discarded = await writer.discard(
        songId: SongId('song'),
        revision: 1,
      );
      expect(discarded.isSuccess, isTrue);

      final reader = _open(store);
      final gone = await _load(reader, 'song');
      final kept = await _load(reader, 'song', revision: 2);
      expect(gone.isFailure, isTrue);
      expect(kept.isSuccess, isTrue);
    });

    test('A3 — discarding an absent pair is a no-op success', () async {
      final repository = _open(InMemoryKeyValueStore());

      final discarded = await repository.discard(
        songId: SongId('never'),
        revision: 1,
      );

      expect(discarded.isSuccess, isTrue);
    });

    for (var index = 0; index < _corruptDocuments.length; index++) {
      test('A4 — corrupt document $index is a read failure', () async {
        final store = InMemoryKeyValueStore(<String, Object>{
          KeyValueSongResumeRepository.storageKey: _corruptDocuments[index],
        });

        final loaded = await _load(_open(store), 'song');

        expect(loaded.isFailure, isTrue);
        expect(loaded.failureOrNull!.code, FailureCode.storageRead);
      });
    }

    test('A4 — a corrupt document never blocks the next save', () async {
      final store = InMemoryKeyValueStore(<String, Object>{
        KeyValueSongResumeRepository.storageKey: 'not json at all',
      });

      final repository = _open(store);
      final saved = await repository.save(
        _checkpoint(songId: 'song', revision: 1, attemptCounter: 5),
      );
      expect(saved.isSuccess, isTrue);

      final loaded = await _load(_open(store), 'song');
      expect(loaded.valueOrNull!.attemptCounter, 5);
    });

    test('A5 — a refused write is a storage write failure', () async {
      final store = InMemoryKeyValueStore();
      store.failingKeys.add(KeyValueSongResumeRepository.storageKey);

      final repository = _open(store);
      final saved = await repository.save(
        _checkpoint(songId: 'song', revision: 1),
      );

      expect(saved.isFailure, isTrue);
      expect(saved.failureOrNull!.code, FailureCode.storageWrite);
    });

    test('A6 — the document keeps only the newest checkpoints', () async {
      final store = InMemoryKeyValueStore();
      final writer = _open(store);
      const total = KeyValueSongResumeRepository.maxCheckpoints + 5;
      final origin = DateTime.utc(2026, 8, 4);
      for (var index = 0; index < total; index++) {
        await writer.save(
          _checkpoint(
            songId: 'song-$index',
            revision: 1,
            recordedAt: origin.add(Duration(days: index)),
          ),
        );
      }

      final key = KeyValueSongResumeRepository.storageKey;
      final decoded = jsonDecode(store.readString(key)!);
      final stored = (decoded as Map<String, dynamic>)['checkpoints'] as List;
      expect(stored, hasLength(KeyValueSongResumeRepository.maxCheckpoints));

      final reader = _open(store);
      final newest = await _load(reader, 'song-${total - 1}');
      final oldest = await _load(reader, 'song-0');
      expect(newest.isSuccess, isTrue);
      expect(oldest.isFailure, isTrue);
    });
  });
}

/// Documents the repository must refuse to guess at.
const List<String> _corruptDocuments = <String>[
  'not json at all',
  '[]',
  '{"checkpoints": []}',
  '{"schemaVersion": 99, "checkpoints": []}',
  '{"schemaVersion": 1, "checkpoints": "nope"}',
  '{"schemaVersion": 1, "checkpoints": [{"songId": "song"}]}',
];

KeyValueSongResumeRepository _open(InMemoryKeyValueStore store) =>
    KeyValueSongResumeRepository(keyValueStore: store);

Future<AppResult<SongResumeCheckpoint>> _load(
  KeyValueSongResumeRepository repository,
  String songId, {
  int revision = 1,
}) => repository.load(songId: SongId(songId), revision: revision);

SongResumeCheckpoint _checkpoint({
  required String songId,
  required int revision,
  int attemptCounter = 1,
  Duration resumedFrom = Duration.zero,
  DateTime? recordedAt,
}) => SongResumeCheckpoint(
  songId: SongId(songId),
  songRevision: revision,
  range: MeasureRange(start: 0, endExclusive: 4),
  attemptCounter: attemptCounter,
  resumedFrom: resumedFrom,
  recordedAt: recordedAt ?? DateTime.utc(2026, 8, 4),
);
