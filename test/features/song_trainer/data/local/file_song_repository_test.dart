/// E03-R07 — FileSongRepository contract matrix (ADR 0090 §Döntés 1 + §3,
/// SDD §18.2 / §18.3 / §18.6).
///
/// This suite locks every cell of the §6 acceptance matrix the *file*
/// implementation must satisfy. The contract-level matrix (list, get,
/// create, update, trash, restore, permanent-delete, stale revision)
/// lives here, together with the `AtomicFileWriter` boundary matrix (ADR
/// 0090 §Döntés 3) it is built on. The recovery scenarios (orphan temp,
/// half-written index, duplicate entry, missing document) live in the
/// recovery suite; this file verifies the *good* path, the
/// contract-level refusal cases the repository must reject with a
/// stable error code, and the writer's own crash-point behaviour.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/local/atomic_file_writer.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/song_document_codec.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

SongDocument _sample({
  SongId? id,
  int revision = 0,
  DateTime? createdAt,
  DateTime? updatedAt,
  SongMetadata? metadata,
}) {
  final stamp = createdAt ?? DateTime.utc(2026, 8, 2, 12);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: id ?? SongId('test-song-1'),
    revision: revision,
    metadata:
        metadata ??
        SongMetadata(title: 'Test Song', tags: const ['test', 'demo']),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'test.json',
      sha256: 'a' * 64,
      importedAt: stamp,
      importerVersion: 'test@1',
    ),
    createdAt: stamp,
    updatedAt: updatedAt ?? stamp,
  );
}

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('file_song_repository_');
  });

  tearDown(() {
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  Future<FileSongRepository> openRepository() {
    final songsRoot = Directory('${sandbox.path}/songs')..createSync();
    return FileSongRepository.openAtDirectory(
      directory: songsRoot,
      clock: () => DateTime.utc(2026, 8, 2, 13),
    );
  }

  group('FileSongRepository.list', () {
    test('returns an empty list on a fresh install', () async {
      final repo = await openRepository();
      final result = await repo.list(
        const SongQuery(includeTrashed: true, includeArchived: true),
      );
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isEmpty);
    });

    test('returns the persisted summary ordered newest-first', () async {
      final repo = await openRepository();
      final clock = DateTime.utc(2026, 8, 2, 13);
      final older = _sample(
        id: SongId('song-old'),
        createdAt: clock.subtract(const Duration(days: 2)),
        updatedAt: clock.subtract(const Duration(days: 2)),
      );
      final newer = _sample(
        id: SongId('song-new'),
        createdAt: clock,
        updatedAt: clock,
      );
      await repo.create(older);
      await repo.create(newer);
      final result = await repo.list(
        const SongQuery(includeTrashed: true, includeArchived: true),
      );
      expect(result.isSuccess, isTrue);
      final list = result.valueOrNull!;
      expect(list.map((s) => s.documentId.value), [
        newer.id.value,
        older.id.value,
      ]);
    });

    test('omits trash rows by default and includes when requested', () async {
      final repo = await openRepository();
      final ok = _sample(id: SongId('song-keep'));
      final trash = _sample(id: SongId('song-trash'));
      await repo.create(ok);
      await repo.create(trash);
      final trashOutcome = await repo.moveToTrash(SongId('song-trash'));
      expect(trashOutcome.isSuccess, isTrue);

      final defaultList = await repo.list(const SongQuery());
      expect(defaultList.valueOrNull!.map((s) => s.documentId.value), [
        'song-keep',
      ]);

      final withTrash = await repo.list(const SongQuery(includeTrashed: true));
      expect(withTrash.valueOrNull!.map((s) => s.documentId.value).toSet(), {
        'song-keep',
        'song-trash',
      });
      expect(
        withTrash.valueOrNull!
            .firstWhere((s) => s.documentId.value == 'song-trash')
            .trashed,
        isTrue,
      );
    });
  });

  group('FileSongRepository.get', () {
    test('returns Success(null) for an unknown song', () async {
      final repo = await openRepository();
      final result = await repo.get(SongId('does-not-exist'));
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('returns the document byte-identical after create', () async {
      final repo = await openRepository();
      final song = _sample();
      final createResult = await repo.create(song);
      expect(createResult.isSuccess, isTrue);
      final getResult = await repo.get(SongId('test-song-1'));
      expect(getResult.isSuccess, isTrue);
      expect(getResult.valueOrNull, equals(song));
    });
  });

  group('FileSongRepository.create', () {
    test('persists a brand-new document and updates the index', () async {
      final repo = await openRepository();
      final song = _sample();
      final result = await repo.create(song);
      expect(result.isSuccess, isTrue);

      final indexFile = File('${sandbox.path}/songs/index.json');
      expect(indexFile.existsSync(), isTrue);
      final documentFile = File(
        '${sandbox.path}/songs/documents/test-song-1.json',
      );
      expect(documentFile.existsSync(), isTrue);

      final documentBytes = documentFile.readAsBytesSync();
      // Codec can read its own bytes back.
      final decoded = const SongDocumentCodec().decode(documentBytes);
      expect(decoded, equals(song));
    });

    test('rejects a duplicate documentId with alreadyExists', () async {
      final repo = await openRepository();
      await repo.create(_sample(id: SongId('dupe')));
      final second = await repo.create(_sample(id: SongId('dupe')));
      expect(second.isFailure, isTrue);
      expect(second.failureOrNull!.code, SongRepositoryErrorCode.alreadyExists);
    });
  });

  group('FileSongRepository.update', () {
    test('bumps revision and persists the new bytes when expectedRevision '
        'matches', () async {
      final repo = await openRepository();
      final stamp = DateTime.utc(2026, 8, 2);
      await repo.create(
        _sample(
          id: SongId('song-update'),
          revision: 0,
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      final replacement = _sample(
        id: SongId('song-update'),
        revision: 0,
        createdAt: stamp,
        updatedAt: stamp.add(const Duration(hours: 1)),
      );
      final result = await repo.update(replacement, expectedRevision: 0);
      expect(result.isSuccess, isTrue);
      // On-disk revision is expectedRevision + 1 (= 1).
      final fileOnDisk = File(
        '${sandbox.path}/songs/documents/song-update.json',
      );
      final decoded = const SongDocumentCodec().decode(
        fileOnDisk.readAsBytesSync(),
      );
      expect(decoded.revision, 1);
    });

    test(
      'returns staleRevision when expectedRevision does not match',
      () async {
        final repo = await openRepository();
        final stamp = DateTime.utc(2026, 8, 2);
        await repo.create(
          _sample(
            id: SongId('song-stale'),
            revision: 4,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
        final result = await repo.update(
          _sample(
            id: SongId('song-stale'),
            revision: 4,
            createdAt: stamp,
            updatedAt: stamp.add(const Duration(hours: 1)),
          ),
          expectedRevision: 99,
        );
        expect(result.isFailure, isTrue);
        expect(
          result.failureOrNull!.code,
          SongRepositoryErrorCode.staleRevision,
        );
        // The on-disk revision is unchanged.
        final fileOnDisk = File(
          '${sandbox.path}/songs/documents/song-stale.json',
        );
        final decoded = const SongDocumentCodec().decode(
          fileOnDisk.readAsBytesSync(),
        );
        expect(decoded.revision, 4);
      },
    );
  });

  group('FileSongRepository.moveToTrash / restore', () {
    test('moveToTrash moves the document into the trash directory', () async {
      final repo = await openRepository();
      await repo.create(_sample(id: SongId('to-trash')));
      final trash = await repo.moveToTrash(SongId('to-trash'));
      expect(trash.isSuccess, isTrue);

      final trashFile = File('${sandbox.path}/songs/trash/to-trash.json');
      expect(trashFile.existsSync(), isTrue);
      final originalFile = File(
        '${sandbox.path}/songs/documents/to-trash.json',
      );
      expect(originalFile.existsSync(), isFalse);
    });

    test('restore brings the document back into documents/', () async {
      final repo = await openRepository();
      await repo.create(_sample(id: SongId('restore-song')));
      await repo.moveToTrash(SongId('restore-song'));
      final restore = await repo.restore(SongId('restore-song'));
      expect(restore.isSuccess, isTrue);

      final restoredFile = File(
        '${sandbox.path}/songs/documents/restore-song.json',
      );
      expect(restoredFile.existsSync(), isTrue);
    });

    test('restore on a non-trashed song is a no-op success', () async {
      final repo = await openRepository();
      await repo.create(_sample(id: SongId('not-trashed')));
      final restore = await repo.restore(SongId('not-trashed'));
      expect(restore.isSuccess, isTrue);
    });
  });

  group('FileSongRepository.permanentlyDelete', () {
    test('removes the document and its index entry', () async {
      final repo = await openRepository();
      await repo.create(_sample(id: SongId('doomed')));
      final gone = await repo.permanentlyDelete(SongId('doomed'));
      expect(gone.isSuccess, isTrue);
      final listResult = await repo.list(
        const SongQuery(includeTrashed: true, includeArchived: true),
      );
      expect(listResult.valueOrNull, isEmpty);
    });

    test('returns notFound when the document does not exist', () async {
      final repo = await openRepository();
      final result = await repo.permanentlyDelete(SongId('ghost'));
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.code, SongRepositoryErrorCode.notFound);
    });
  });

  group('Re-open cycle', () {
    test(
      'a second repository instance re-reads the same persisted state',
      () async {
        final songsRoot = Directory('${sandbox.path}/songs')..createSync();
        final repo = await FileSongRepository.openAtDirectory(
          directory: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 13),
        );
        await repo.create(_sample(id: SongId('durable')));

        // Open a fresh instance against the same root.
        final reopened = await FileSongRepository.openAtDirectory(
          directory: songsRoot,
          clock: () => DateTime.utc(2026, 8, 2, 13),
        );

        final result = await reopened.get(SongId('durable'));
        expect(result.isSuccess, isTrue);
        expect(result.valueOrNull, isNotNull);
        expect(result.valueOrNull!.id, SongId('durable'));
      },
    );
  });

  group('AtomicFileWriter', () {
    late Directory atomicSandbox;

    setUp(() {
      atomicSandbox = Directory.systemTemp.createTempSync(
        'atomic_writer_test_',
      );
    });

    tearDown(() {
      if (atomicSandbox.existsSync()) {
        atomicSandbox.deleteSync(recursive: true);
      }
    });

    File targetFile() => File('${atomicSandbox.path}/payload.bin');

    test('successful write replaces the existing file byte-identically', () {
      final writer = const AtomicFileWriter();
      final target = targetFile();
      final bytes = Uint8List.fromList('hello world'.codeUnits);

      final outcome = writer.write(
        target: target,
        bytes: bytes,
        verifier: (b) {
          expect(b, equals(bytes));
          return true;
        },
      );

      expect(outcome.committed, isTrue);
      expect(outcome.attempts, 1);
      expect(target.existsSync(), isTrue);
      expect(target.readAsBytesSync(), equals(bytes));
      // The temp residue must NOT persist after a successful rename —
      // the recovery scanner relies on this invariant.
      final residue = atomicSandbox
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(AtomicFileWriter.tempExtension));
      expect(
        residue,
        isEmpty,
        reason: 'no .tmp-* residue after a successful rename',
      );
    });

    test('verifier returning false leaves the previous good file intact', () {
      final writer = const AtomicFileWriter();
      final target = targetFile();
      final original = Uint8List.fromList('original-good'.codeUnits);
      target.writeAsBytesSync(original, flush: true);

      final outcome = writer.write(
        target: target,
        bytes: Uint8List.fromList('bad'.codeUnits),
        verifier: (_) => false,
      );

      expect(outcome.committed, isFalse);
      expect(outcome.attempts, greaterThanOrEqualTo(1));
      // Target must still carry the pre-write bytes.
      expect(target.readAsBytesSync(), equals(original));
      // No stray temp file inside the containing dir.
      final leak = atomicSandbox
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(AtomicFileWriter.tempExtension));
      expect(leak, isEmpty, reason: 'temp residue on failed write');
    });

    test('target is created when it does not yet exist', () {
      final writer = const AtomicFileWriter();
      final target = targetFile();
      expect(target.existsSync(), isFalse);

      final bytes = Uint8List.fromList('brand-new'.codeUnits);
      final outcome = writer.write(
        target: target,
        bytes: bytes,
        verifier: (b) {
          expect(b, equals(bytes));
          return true;
        },
      );

      expect(outcome.committed, isTrue);
      expect(target.existsSync(), isTrue);
      expect(target.readAsBytesSync(), equals(bytes));
    });

    test('verifier is invoked exactly once when it succeeds', () {
      final writer = const AtomicFileWriter();
      final target = targetFile();
      var verifierCalls = 0;
      final outcome = writer.write(
        target: target,
        bytes: Uint8List.fromList('verifier-once'.codeUnits),
        verifier: (b) {
          verifierCalls++;
          expect(b, hasLength('verifier-once'.length));
          return true;
        },
      );
      expect(outcome.committed, isTrue);
      expect(verifierCalls, 1);
    });
  });
}
