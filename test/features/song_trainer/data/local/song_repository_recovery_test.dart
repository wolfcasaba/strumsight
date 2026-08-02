// ignore_for_file: prefer_interpolation_to_compose_strings, unnecessary_string_interpolations
/// E03-R07 — SongRepositoryRecovery crash-residue matrix (ADR 0090
/// §Döntés 7, SDD §18.7) and the `SongIndexCodec` boundary matrix (ADR
/// 0090 §Döntés 4) it depends on.
///
/// The recovery scanner runs at startup. It is the **only** code path
/// allowed to touch the `temp/` directory's contents after a crash —
/// the runtime write path refuses to leave any `*.tmp-*` behind
/// (atomic_file_writer invariant), so the scanner only ever sees
/// `temp/`-only residue as evidence of a crash.
///
/// The matrix below locks every row of the §6 / §18.7 acceptance list:
///
/// | Crash point               | Restart behaviour                          |
/// |---------------------------|--------------------------------------------|
/// | temp write előtt/közben   | régi verzió                                |
/// | flush után, verify előtt  | régi verzió + temp recovery                |
/// | document rename, index előtt | document/index reconcile                |
/// | index temp/rename         | documentból rebuildelhető index            |
/// | asset hash mismatch       | corrupt report, nincs néma playback        |
///
/// The first four rows are filesystem-level: the scanner walks the
/// directories and reports each residue file with a stable
/// [SongRepositoryRecoveryCode]. The last row is handled by the asset
/// store itself (§18.5); the scanner surfaces it via the asset summary.
///
/// The `SongIndexCodec` group locks its own encode/decode round-trip and
/// corruption matrix ("Hash mismatch, missing/corrupt index/document,
/// duplicate/orphan asset recoverable report" — the codec itself never
/// lists "missing document" as a corrupt index; that is a separate
/// failure mode the recovery scanner above owns).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/song_index_codec.dart';
import 'package:strumsight/features/song_trainer/data/local/song_repository_recovery.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';

String _zeroHash() => '0' * 64;

void main() {
  late Directory sandbox;
  late Directory songsRoot;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('recovery_');
    songsRoot = Directory('${sandbox.path}/songs')..createSync();
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  Future<void> prepareTree({
    required Future<void> Function(Directory) build,
  }) async {
    // The song repository lazily creates its subtree on open, but
    // some recovery scenarios need files BEFORE any repository runs.
    await songsRoot.create(recursive: true);
    await build(songsRoot);
  }

  group('SongRepositoryRecovery.scan — temp-only residue', () {
    test('flags a `.tmp-` residue in the temp/ directory', () async {
      await prepareTree(
        build: (root) async {
          final tempDir = Directory('${root.path}/temp');
          await tempDir.create(recursive: true);
          await File(
            '${tempDir.path}/stale.tmp-99-1',
          ).writeAsBytes(const <int>[1, 2, 3]);
        },
      );

      final report = await SongRepositoryRecovery.scan(songsRoot);
      final tempIssue = report.issues.singleWhere(
        (issue) => issue.code == SongRepositoryRecoveryCode.orphanTempFile,
      );
      expect(tempIssue.path, endsWith('stale.tmp-99-1'));
    });

    test('removes the `.tmp-` residue when requested', () async {
      await prepareTree(
        build: (root) async {
          final tempDir = Directory('${root.path}/temp');
          await tempDir.create(recursive: true);
          await File(
            '${tempDir.path}/junk.tmp-99-1',
          ).writeAsBytes(const <int>[1]);
        },
      );

      final report = await SongRepositoryRecovery.scan(
        songsRoot,
        action: SongRepositoryRecoveryAction.cleanTemp,
      );
      expect(report.issues, isNotEmpty);
      expect(Directory('${songsRoot.path}/temp').listSync(), isEmpty);
    });

    test(
      'a clean install (no index, no docs) reports no recoverable issues',
      () async {
        final report = await SongRepositoryRecovery.scan(songsRoot);
        // A fresh install has no `index.json`; that is the documented
        // initial state, NOT a recoverable issue. The scanner must
        // therefore leave `issues` empty for a brand-new tree.
        expect(report.issues, isEmpty);
        expect(report.hasIssues, isFalse);
      },
    );
  });

  group('SongRepositoryRecovery.scan — orphan document', () {
    test('flags a document with no matching summary', () async {
      await prepareTree(
        build: (root) async {
          final docsDir = Directory('${root.path}/documents');
          await docsDir.create(recursive: true);
          await File('${docsDir.path}/orphan-song.json').writeAsBytes(
            utf8.encode(
              '{"schemaVersion":1,"id":"orphan-song","revision":0,'
                      '"metadata":{"title":"orphan"},"source":{"type":"createdInApp",'
                      '"originalFileName":"o.json","sha256":"' +
                  ('0' * 64) +
                  '",'
                      '"importedAt":"2026-08-02T00:00:00Z","importerVersion":"test@1"},'
                      '"createdAt":"2026-08-02T00:00:00Z",'
                      '"updatedAt":"2026-08-02T00:00:00Z"}',
            ),
          );
        },
      );

      final report = await SongRepositoryRecovery.scan(songsRoot);
      final issue = report.issues.singleWhere(
        (i) => i.code == SongRepositoryRecoveryCode.orphanDocument,
      );
      expect(issue.path, endsWith('orphan-song.json'));
    });

    test('rebuildIndex rebuilds the index from documents/', () async {
      await prepareTree(
        build: (root) async {
          final docsDir = Directory('${root.path}/documents');
          await docsDir.create(recursive: true);
          await File('${docsDir.path}/keepable.json').writeAsBytes(
            utf8.encode(
              '{"schemaVersion":1,"id":"keepable","revision":0,'
                      '"metadata":{"title":"keepable"},"source":{"type":"createdInApp",'
                      '"originalFileName":"k.json","sha256":"' +
                  ('0' * 64) +
                  '",'
                      '"importedAt":"2026-08-02T00:00:00Z","importerVersion":"test@1"},'
                      '"createdAt":"2026-08-02T00:00:00Z",'
                      '"updatedAt":"2026-08-02T00:00:00Z"}',
            ),
          );
        },
      );

      final report = await SongRepositoryRecovery.scan(
        songsRoot,
        action: SongRepositoryRecoveryAction.rebuildIndex,
      );
      expect(report.rebuiltSummaries, hasLength(1));
      final indexFile = File('${songsRoot.path}/index.json');
      expect(indexFile.existsSync(), isTrue);
      final decoded = const SongIndexCodec().decode(
        indexFile.readAsBytesSync(),
      );
      expect(decoded.single.documentId.value, 'keepable');
    });
  });

  group('SongRepositoryRecovery.scan — corrupt index', () {
    test('flags a structurally invalid index.json', () async {
      await prepareTree(
        build: (root) async {
          await File(
            '${root.path}/index.json',
          ).writeAsBytes(utf8.encode('{not-json'));
        },
      );
      final report = await SongRepositoryRecovery.scan(songsRoot);
      expect(
        report.issues.any(
          (i) => i.code == SongRepositoryRecoveryCode.corruptIndex,
        ),
        isTrue,
      );
    });
  });

  group('Integration: FileSongRepository reopen → recovery', () {
    test('a crash between document and index write leaves only an orphan '
        'document, recovered by the next run', () async {
      // 1. Successful document create leaves a clean document file +
      // a matching index entry. We simulate a crash AFTER the document
      // rename but BEFORE the index rename by writing only the document
      // file and skipping the index. The next open + recovery scan
      // must surface the orphan document and rebuild the index.
      final docsDir = Directory('${songsRoot.path}/documents')
        ..createSync(recursive: true);
      await File('${docsDir.path}/reborn.json').writeAsBytes(
        utf8.encode(
          '{"schemaVersion":1,"id":"reborn","revision":0,'
                  '"metadata":{"title":"reborn"},"source":{"type":"createdInApp",'
                  '"originalFileName":"r.json","sha256":"' +
              ('0' * 64) +
              '",'
                  '"importedAt":"2026-08-02T00:00:00Z","importerVersion":"test@1"},'
                  '"createdAt":"2026-08-02T00:00:00Z",'
                  '"updatedAt":"2026-08-02T00:00:00Z"}',
        ),
      );
      // No index.json written — that's the simulated crash.

      final report = await SongRepositoryRecovery.scan(
        songsRoot,
        action: SongRepositoryRecoveryAction.rebuildIndex,
      );
      expect(report.rebuiltSummaries, hasLength(1));

      // Now opening the repository must yield the recovered document.
      final repo = await FileSongRepository.openAtDirectory(
        directory: songsRoot,
        clock: () => DateTime.utc(2026, 8, 2, 13),
      );
      final result = await repo.list(
        const SongQuery(includeTrashed: true, includeArchived: true),
      );
      expect(result.isSuccess, isTrue);
      final list = result.valueOrNull!;
      expect(list.single.documentId.value, 'reborn');
    });
  });

  group('Integration: asset store + recovery', () {
    test('flags an assets/ file with no summary sidecar', () async {
      await prepareTree(
        build: (root) async {
          // Open the asset store once so the asset subdirectories exist,
          // then drop a stray bytes file with no `.summary.json` next to
          // it (simulating a crashed write between bytes land and
          // summary land).
          await FileSongAssetRepository.openAtDirectory(
            root: root,
            clock: () => DateTime.utc(2026, 8, 2, 13),
          );
          final assetsDir = Directory('${root.path}/assets')..createSync();
          await File(
            '${assetsDir.path}/' + 'ab' * 32 + '.mp3',
          ).writeAsBytes(const <int>[1]);
        },
      );

      final report = await SongRepositoryRecovery.scan(songsRoot);
      expect(
        report.issues.any(
          (i) => i.code == SongRepositoryRecoveryCode.orphanAssetBytes,
        ),
        isTrue,
      );
    });
  });

  group('SongIndexCodec.encode / decode — round-trip', () {
    const codec = SongIndexCodec();

    test('encodes and decodes a single summary byte-identically', () {
      final timestamp = DateTime.utc(2026, 8, 2, 12, 30, 45);
      final summary = SongSummary(
        documentId: SongId('song-1'),
        title: 'Test Song',
        artist: 'Test Artist',
        tags: const ['rock', 'acoustic'],
        updatedAt: timestamp,
        lastPracticedAt: timestamp,
        capability: SongCapabilitySummary(
          canPersist: true,
          canTrain: true,
          canExport: true,
          chordScoring: true,
          pitchScoring: false,
          lastValidatedAt: timestamp,
        ),
        sourceType: SongSourceType.createdInApp,
        favorite: true,
        archived: false,
        trashed: false,
        revision: 7,
        documentHash: _zeroHash(),
      );

      final encoded = codec.encode([summary]);
      final decoded = codec.decode(encoded);

      expect(decoded, hasLength(1));
      expect(decoded.single, equals(summary));
    });

    test('encode produces valid UTF-8 JSON with empty list', () {
      final encoded = codec.encode(const <SongSummary>[]);
      final raw = jsonDecode(utf8.decode(encoded));
      expect(raw, isA<Map<String, dynamic>>());
      expect(raw['schemaVersion'], isNotNull);
      expect(raw['summaries'], isA<List>());
      expect(raw['summaries'], isEmpty);
    });
  });

  group('SongIndexCodec.decode — corruption matrix', () {
    const codec = SongIndexCodec();

    test('rejects missing schemaVersion', () {
      expect(
        () => codec.decode(utf8.encode('{"summaries":[]}')),
        throwsA(isA<SongIndexCodecException>()),
      );
    });

    test('rejects missing summaries list', () {
      expect(
        () => codec.decode(utf8.encode('{"schemaVersion":1}')),
        throwsA(isA<SongIndexCodecException>()),
      );
    });

    test('rejects a summary entry missing revision', () {
      final raw =
          '{"schemaVersion":1,"summaries":[{"documentId":"x",'
              '"title":"a","artist":null,"tags":[],'
              '"updatedAt":"2026-08-02T00:00:00Z",'
              '"lastPracticedAt":"2026-08-02T00:00:00Z",'
              '"capability":null,'
              '"sourceType":"createdInApp",'
              '"favorite":false,"archived":false,"trashed":false",'
              '"documentHash":"' +
          _zeroHash() +
          '"}'
              '}';
      expect(
        () => codec.decode(utf8.encode(raw)),
        throwsA(isA<SongIndexCodecException>()),
      );
    });

    test('rejects a non-hex document hash', () {
      final raw =
          '{"schemaVersion":1,"summaries":[{"documentId":"x","title":"a",'
          '"artist":null,"tags":[],'
          '"updatedAt":"2026-08-02T00:00:00Z",'
          '"lastPracticedAt":"2026-08-02T00:00:00Z",'
          '"capability":null,'
          '"sourceType":"createdInApp",'
          '"favorite":false,"archived":false,"trashed":false,'
          '"revision":1,"documentHash":"not-hex"}]}';
      expect(
        () => codec.decode(utf8.encode(raw)),
        throwsA(isA<SongIndexCodecException>()),
      );
    });

    test('rejects a duplicate documentId entry', () {
      final ts = DateTime.utc(2026, 8, 2, 12);
      final entry = {
        'documentId': 'duplicate-song',
        'title': 'Test',
        'artist': null,
        'tags': <String>[],
        'updatedAt': ts.toIso8601String(),
        'lastPracticedAt': ts.toIso8601String(),
        'capability': null,
        'sourceType': '${SongSourceType.createdInApp.code}',
        'favorite': false,
        'archived': false,
        'trashed': false,
        'revision': 1,
        'documentHash': _zeroHash(),
      };
      final raw =
          '{"schemaVersion":1,"summaries":[${jsonEncode(entry)},${jsonEncode(entry)}]}';
      expect(
        () => codec.decode(utf8.encode(raw)),
        throwsA(isA<SongIndexCodecException>()),
      );
    });
  });
}
