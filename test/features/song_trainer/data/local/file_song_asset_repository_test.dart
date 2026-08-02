// ignore_for_file: unnecessary_string_interpolations
/// E03-R07 — FileSongAssetRepository boundary matrix (ADR 0090 §Döntés 5
/// + §6, SDD §18.5 + §18.6).
///
/// The asset store is content-addressed by SHA-256: two `put` calls with
/// the same bytes converge on a single on-disk file with a shared
/// reference count. Duplicate writes NEVER write the bytes a second
/// time, and the recovered asset-id is the *canonical* one — the second
/// caller's id is the supply-side label, the storage-side id wins.
///
/// The matrix below locks every cell the §6 acceptance criteria promises:
///
///   * put re-hashes the bytes — `hashMismatch` fires when expected
///     SHA-256 is wrong, even if the bytes would otherwise hash to it;
///   * deduplication — the second put bumps the count and returns
///     `duplicate: true` with the canonical id;
///   * `permanentlyDelete` refuses to drop bytes a document still
///     references — `stillReferenced` is the only error the contract
///     allows in this case (AGENTS.md §5: no silent asset deletion);
///   * reference count is the only "permission" for permanent delete —
///     decrementing the only reference and then calling delete lands
library;

///     the file in the recycler.
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';

String _hash(Uint8List bytes) => crypto.sha256.convert(bytes).toString();

Uint8List _bytes(List<int> pattern) => Uint8List.fromList(pattern);

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('asset_repo_');
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  Future<FileSongAssetRepository> openStore() {
    final root = Directory('${sandbox.path}/songs')..createSync();
    return FileSongAssetRepository.openAtDirectory(
      root: root,
      clock: () => DateTime.utc(2026, 8, 2, 13),
    );
  }

  group('FileSongAssetRepository.put', () {
    test('writes bytes to assets/ and persists a summary', () async {
      final store = await openStore();
      final bytes = _bytes([1, 2, 3, 4, 5]);
      final hash = _hash(bytes);
      final result = await store.put(
        SongAssetWriteRequest(
          bytes: bytes,
          assetId: SongAssetId('asset-1'),
          extension: 'mp3',
          expectedSha256: hash,
          mimeType: 'audio/mp3',
          durationMs: 1000,
        ),
      );
      expect(result.isSuccess, isTrue);
      final receipt = result.valueOrNull!;
      expect(receipt.duplicate, isFalse);
      expect(receipt.sha256, hash);

      final assetsDir = Directory('${sandbox.path}/songs/assets');
      final expectedFile = File('${assetsDir.path}/$hash.mp3');
      expect(expectedFile.existsSync(), isTrue);
      expect(expectedFile.readAsBytesSync(), equals(bytes));

      final summaryFile = File('${assetsDir.path}/$hash.summary.json');
      expect(summaryFile.existsSync(), isTrue);

      final summaryResult = await store.summary(hash);
      expect(summaryResult.isSuccess, isTrue);
      final summary = summaryResult.valueOrNull!;
      expect(summary.byteLength, bytes.length);
      expect(summary.mimeType, 'audio/mp3');
      expect(summary.referenceCount, 0);
    });

    test('rejects hash mismatch with a stable code', () async {
      final store = await openStore();
      final bytes = _bytes([7, 8, 9]);
      final result = await store.put(
        SongAssetWriteRequest(
          bytes: bytes,
          assetId: SongAssetId('asset-bad'),
          extension: 'mp3',
          expectedSha256: 'f' * 64,
        ),
      );
      expect(result.isFailure, isTrue);
      expect(
        result.failureOrNull!.code,
        SongAssetRepositoryErrorCode.hashMismatch,
      );
      final assetsDir = Directory('${sandbox.path}/songs/assets');
      expect(assetsDir.existsSync(), isTrue);
      // No asset file should have been written.
      expect(assetsDir.listSync().whereType<File>(), isEmpty);
    });

    test(
      'deduplicates identical content under the canonical asset-id',
      () async {
        final store = await openStore();
        final bytes = _bytes([10, 20, 30]);
        final hash = _hash(bytes);
        final first = await store.put(
          SongAssetWriteRequest(
            bytes: bytes,
            assetId: SongAssetId('first-id'),
            extension: 'mp3',
            expectedSha256: hash,
          ),
        );
        expect(first.valueOrNull!.duplicate, isFalse);
        // A second put with the SAME bytes — even from a different
        // asset-id — returns the canonical receipt with `duplicate: true`.
        final second = await store.put(
          SongAssetWriteRequest(
            bytes: bytes,
            assetId: SongAssetId('second-id'),
            extension: 'mp3',
            expectedSha256: hash,
          ),
        );
        expect(second.isSuccess, isTrue);
        final receipt = second.valueOrNull!;
        expect(receipt.duplicate, isTrue);
        expect(receipt.sha256, hash);
        // The original bytes file is unchanged (no second copy on disk).
        final assetsDir = Directory('${sandbox.path}/songs/assets');
        final matches = assetsDir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('$hash.mp3'),
        );
        expect(matches, hasLength(1));
      },
    );

    test('rejects empty bytes', () async {
      final store = await openStore();
      final result = await store.put(
        SongAssetWriteRequest(
          bytes: _bytes(<int>[]),
          assetId: SongAssetId('empty'),
          extension: 'png',
          expectedSha256:
              'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        ),
      );
      expect(result.isFailure, isTrue);
      expect(
        result.failureOrNull!.code,
        SongAssetRepositoryErrorCode.assetEmpty,
      );
    });

    test('rejects bytes larger than documented ceiling', () async {
      final store = await openStore();
      final oversize = Uint8List(maxSongAssetByteLength + 1);
      final result = await store.put(
        SongAssetWriteRequest(
          bytes: oversize,
          assetId: SongAssetId('too-big'),
          extension: 'bin',
          expectedSha256: 'a' * 64,
        ),
      );
      expect(result.isFailure, isTrue);
      expect(
        result.failureOrNull!.code,
        SongAssetRepositoryErrorCode.assetTooLarge,
      );
    });
  });

  group('FileSongAssetRepository.reference counts', () {
    test('incrementReference increases the count', () async {
      final store = await openStore();
      final bytes = _bytes([42, 43]);
      final hash = _hash(bytes);
      await store.put(
        SongAssetWriteRequest(
          bytes: bytes,
          assetId: SongAssetId('counted'),
          extension: 'mp3',
          expectedSha256: hash,
        ),
      );
      final incResult = await store.incrementReference(
        SongAssetHolder.forDocument(
          sha256: hash,
          holderId: SongAssetId('doc-1'),
        ),
      );
      expect(incResult.isSuccess, isTrue);
      final summaryResult = await store.summary(hash);
      expect(summaryResult.valueOrNull!.referenceCount, 1);
    });

    test('incrementReference is idempotent per holder', () async {
      final store = await openStore();
      final bytes = _bytes([44, 45]);
      final hash = _hash(bytes);
      await store.put(
        SongAssetWriteRequest(
          bytes: bytes,
          assetId: SongAssetId('idempotent'),
          extension: 'mp3',
          expectedSha256: hash,
        ),
      );
      final holder = SongAssetHolder.forDocument(
        sha256: hash,
        holderId: SongAssetId('doc-2'),
      );
      await store.incrementReference(holder);
      await store.incrementReference(holder);
      final summaryResult = await store.summary(hash);
      expect(summaryResult.valueOrNull!.referenceCount, 1);
    });

    test('permanentlyDelete refuses while a reference exists', () async {
      final store = await openStore();
      final bytes = _bytes([55]);
      final hash = _hash(bytes);
      await store.put(
        SongAssetWriteRequest(
          bytes: bytes,
          assetId: SongAssetId('holder-asset'),
          extension: 'mp3',
          expectedSha256: hash,
        ),
      );
      await store.incrementReference(
        SongAssetHolder.forDocument(
          sha256: hash,
          holderId: SongAssetId('doc-3'),
        ),
      );
      final deleteResult = await store.permanentlyDelete(hash);
      expect(deleteResult.isFailure, isTrue);
      expect(
        deleteResult.failureOrNull!.code,
        SongAssetRepositoryErrorCode.stillReferenced,
      );
      final assetsDir = Directory('${sandbox.path}/songs/assets');
      final stillThere = assetsDir.listSync().whereType<File>().any(
        (f) => f.path.contains('$hash'),
      );
      expect(stillThere, isTrue);
    });

    test('permanentlyDelete drops bytes when the count reaches zero', () async {
      final store = await openStore();
      final bytes = _bytes([66]);
      final hash = _hash(bytes);
      await store.put(
        SongAssetWriteRequest(
          bytes: bytes,
          assetId: SongAssetId('lonely'),
          extension: 'mp3',
          expectedSha256: hash,
        ),
      );
      await store.incrementReference(
        SongAssetHolder.forDocument(
          sha256: hash,
          holderId: SongAssetId('doc-4'),
        ),
      );
      await store.decrementReference(
        SongAssetHolder.forDocument(
          sha256: hash,
          holderId: SongAssetId('doc-4'),
        ),
      );
      final deleteResult = await store.permanentlyDelete(hash);
      expect(deleteResult.isSuccess, isTrue);
      final assetsDir = Directory('${sandbox.path}/songs/assets');
      // Asset byte file gone.
      final byteFile = assetsDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('$hash.mp3'),
      );
      expect(byteFile, isEmpty);
    });
  });

  group('FileSongAssetRepository.get', () {
    test('returns the bytes verbatim', () async {
      final store = await openStore();
      final bytes = _bytes([101, 102, 103]);
      final hash = _hash(bytes);
      await store.put(
        SongAssetWriteRequest(
          bytes: bytes,
          assetId: SongAssetId('get-asset'),
          extension: 'bin',
          expectedSha256: hash,
        ),
      );
      final getResult = await store.get(hash);
      expect(getResult.isSuccess, isTrue);
      expect(getResult.valueOrNull, equals(bytes));
    });

    test('returns Success(null) for an unknown asset', () async {
      final store = await openStore();
      final result = await store.get('0' * 64);
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isNull);
    });
  });
}
