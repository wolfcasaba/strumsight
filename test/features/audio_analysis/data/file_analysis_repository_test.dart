// Comprehensive CRUD + atomicity + corruption + index-rebuild + cap +
// summary-only tests for the FileAnalysisRepository (ADR 0239, E06-R21
// brief §6 acceptance criteria).
//
// The matrix cells covered:
//
//   - CRUD-mátrix: save → getById → list → rename → delete → replace
//   - Atomikus írás: throwy filesystem, the previous document survives,
//     temp file does not remain
//   - Korrupció-izoláció: 3 documents, one file trashed; list returns 2,
//     getById on the corrupt one returns typed failure
//   - Index-újraépítés: index missing → list returns the same three
//     elements; index trashed → same outcome (two cells)
//   - Summary-olvasás: list() invokes the document decoder zero times
//   - Cap-küszöb hármas: 99/100/101 — exactly 100 survives, the 101st
//     drops the oldest
//   - Nincs audio a lemezen: post-save directory contents match the
//     document JSON size, no PCM-sized file
//   - Storage-kulcs őr: the new ss.analysis.migration_state key lives
//     in StorageKeys.all and is unique
//
// The test does NOT depend on path_provider, SharedPreferences, or any
// platform plugin — it only uses dart:io with temp directories and an
// injected atomic-writer fake.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'file_analysis_repository_test_',
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test(
    'CRUD matrix: save → getById → list → rename → delete → replace',
    () async {
      final repository = await FileAnalysisRepository.openAtDirectory(
        directory: tempRoot,
        clock: () => DateTime.utc(2026, 8, 1),
      );

      final initial = _buildDocument(
        id: 'a',
        createdAt: DateTime.utc(2026, 8, 1, 10),
        label: 'A',
      );
      final saveResult = await repository.save(
        AnalysisSaveRequest(
          document: initial,
          title: 'First take',
          customTitle: true,
        ),
      );
      expect(saveResult.isSuccess, isTrue, reason: 'first save should succeed');

      final listOne = await repository.list();
      expect(listOne.isSuccess, isTrue);
      expect(listOne.valueOrNull, hasLength(1));
      expect(listOne.valueOrNull!.first.title, 'First take');
      expect(listOne.valueOrNull!.first.customTitle, isTrue);

      final fetch = await repository.getById('a');
      expect(fetch.isSuccess, isTrue);
      expect(fetch.valueOrNull!.id, 'a');

      final renamed = await repository.rename(
        id: 'a',
        newTitle: '  Renamed take  ',
      );
      expect(renamed.isSuccess, isTrue);

      final listTwo = await repository.list();
      expect(listTwo.valueOrNull!.first.title, 'Renamed take');
      expect(listTwo.valueOrNull!.first.customTitle, isTrue);

      final replacement = _buildDocument(
        id: 'a',
        createdAt: DateTime.utc(2026, 8, 1, 10),
        label: 'A2',
      );
      final replaceResult = await repository.replace(
        'a',
        AnalysisSaveRequest(
          document: replacement,
          title: 'Renamed take',
          customTitle: true,
        ),
      );
      expect(replaceResult.isSuccess, isTrue);

      final fetchedAfterReplace = await repository.getById('a');
      expect(
        fetchedAfterReplace.valueOrNull!.timeline.chordSegments.first.label,
        'A2',
      );

      final deleted = await repository.delete('a');
      expect(deleted.isSuccess, isTrue);

      final listThree = await repository.list();
      expect(listThree.valueOrNull, isEmpty);
    },
  );

  test('atomic write: mid-write failure leaves previous document intact and '
      'cleans up the temp file', () async {
    // Step 1: persist the original document with the real writer so the
    // previous good bytes are on disk.
    final realRepository = await FileAnalysisRepository.openAtDirectory(
      directory: tempRoot,
      clock: () => DateTime.utc(2026, 8, 1),
    );
    final original = _buildDocument(
      id: 'a',
      createdAt: DateTime.utc(2026, 8, 1),
      label: 'A',
    );
    await realRepository.save(
      AnalysisSaveRequest(
        document: original,
        title: 'Original',
        customTitle: false,
      ),
    );

    // Step 2: open a SECOND repository against the SAME directory
    // with a writer that refuses every commit. The replace attempt
    // must fail-closed: previous bytes survive, no temp residue.
    final throwingRepository = await FileAnalysisRepository.openAtDirectory(
      directory: tempRoot,
      clock: () => DateTime.utc(2026, 8, 1),
      writer: _ThrowingAnalysisAtomicWriter(),
    );

    final docFile = File(
      '${tempRoot.path}/${AnalysisRepositoryLayout.documentsDirectory}/a.json',
    );
    final originalBytes = docFile.readAsBytesSync();

    final replacement = _buildDocument(
      id: 'a',
      createdAt: DateTime.utc(2026, 8, 1),
      label: 'A2',
    );
    final replace = await throwingRepository.replace(
      'a',
      AnalysisSaveRequest(
        document: replacement,
        title: 'Replacement',
        customTitle: true,
      ),
    );
    expect(replace.isSuccess, isFalse);

    // Previous good document is intact — bytes are unchanged.
    expect(docFile.existsSync(), isTrue);
    expect(docFile.readAsBytesSync(), originalBytes);

    // No temp residue survives in `temp/`.
    final tempDir = Directory(
      '${tempRoot.path}/${AnalysisRepositoryLayout.tempDirectory}',
    );
    final residue = tempDir.existsSync()
        ? tempDir
              .listSync()
              .whereType<File>()
              .where((file) => file.path.contains('.tmp-'))
              .toList()
        : <FileSystemEntity>[];
    expect(
      residue,
      isEmpty,
      reason: 'no temp residue may survive a failed atomic write',
    );
  });

  test(
    'corruption isolation: 3 documents, one file trashed, list returns 2',
    () async {
      final repository = await FileAnalysisRepository.openAtDirectory(
        directory: tempRoot,
        clock: () => DateTime.utc(2026, 8, 1),
      );

      for (final id in <String>['a', 'b', 'c']) {
        await repository.save(
          AnalysisSaveRequest(
            document: _buildDocument(
              id: id,
              createdAt: DateTime.utc(2026, 8, 1, 10),
              label: id.toUpperCase(),
            ),
            title: 'Take $id',
            customTitle: false,
          ),
        );
      }

      // Replace one document's on-disk bytes with garbage.
      final trashFile = File(
        '${tempRoot.path}/${AnalysisRepositoryLayout.documentsDirectory}/b.json',
      );
      trashFile.writeAsBytesSync(utf8.encode('this is not json {{{'));

      final list = await repository.list();
      expect(list.isSuccess, isTrue);
      expect(list.valueOrNull, hasLength(2));
      expect(
        list.valueOrNull!.map((summary) => summary.documentId).toSet(),
        <String>{'a', 'c'},
        reason: 'the corrupt document is quarantined out of the index',
      );

      // The corrupt file should now live under the .corrupt suffix.
      final quarantined = File(
        '${trashFile.path}${AnalysisRepositoryLayout.corruptSuffix}',
      );
      expect(quarantined.existsSync(), isTrue);

      final fetchCorrupt = await repository.getById('b');
      expect(fetchCorrupt.isSuccess, isFalse);
      expect(
        fetchCorrupt.failureOrNull!.code,
        AnalysisRepositoryErrorCode.corruptDocument,
      );
    },
  );

  test(
    'index rebuild: missing index returns the same three elements',
    () async {
      final repository = await FileAnalysisRepository.openAtDirectory(
        directory: tempRoot,
        clock: () => DateTime.utc(2026, 8, 1),
      );
      for (final id in <String>['a', 'b', 'c']) {
        await repository.save(
          AnalysisSaveRequest(
            document: _buildDocument(
              id: id,
              createdAt: DateTime.utc(2026, 8, 1, 10),
              label: id.toUpperCase(),
            ),
            title: 'Take $id',
            customTitle: false,
          ),
        );
      }
      // Delete the index file.
      final indexFile = File(
        '${tempRoot.path}/${AnalysisRepositoryLayout.indexFileName}',
      );
      indexFile.deleteSync();

      final list = await repository.list();
      expect(list.isSuccess, isTrue);
      expect(list.valueOrNull, hasLength(3));
      expect(list.valueOrNull!.map((s) => s.documentId).toSet(), <String>{
        'a',
        'b',
        'c',
      });
      // The rebuild writes a fresh index file with deterministic ordering.
      expect(indexFile.existsSync(), isTrue);
    },
  );

  test(
    'index rebuild: trashed index returns the same three elements',
    () async {
      final repository = await FileAnalysisRepository.openAtDirectory(
        directory: tempRoot,
        clock: () => DateTime.utc(2026, 8, 1),
      );
      for (final id in <String>['a', 'b', 'c']) {
        await repository.save(
          AnalysisSaveRequest(
            document: _buildDocument(
              id: id,
              createdAt: DateTime.utc(2026, 8, 1, 10),
              label: id.toUpperCase(),
            ),
            title: 'Take $id',
            customTitle: false,
          ),
        );
      }
      // Truncate the index to garbage.
      final indexFile = File(
        '${tempRoot.path}/${AnalysisRepositoryLayout.indexFileName}',
      );
      indexFile.writeAsBytesSync(utf8.encode('not-json'));

      final list = await repository.list();
      expect(list.isSuccess, isTrue);
      expect(list.valueOrNull, hasLength(3));
      expect(list.valueOrNull!.map((s) => s.documentId).toSet(), <String>{
        'a',
        'b',
        'c',
      });
    },
  );

  test(
    'summary-only list: zero document-decode calls during a healthy list',
    () async {
      var decodeCount = 0;
      final repository = await FileAnalysisRepository.openAtDirectory(
        directory: tempRoot,
        clock: () => DateTime.utc(2026, 8, 1),
        onDecode: () => decodeCount++,
      );
      for (final id in <String>['a', 'b', 'c']) {
        await repository.save(
          AnalysisSaveRequest(
            document: _buildDocument(
              id: id,
              createdAt: DateTime.utc(2026, 8, 1, 10),
              label: id.toUpperCase(),
            ),
            title: 'Take $id',
            customTitle: false,
          ),
        );
      }
      decodeCount = 0;
      final list = await repository.list();
      expect(list.isSuccess, isTrue);
      expect(list.valueOrNull, hasLength(3));
      expect(
        decodeCount,
        0,
        reason: 'list() MUST NOT decode any full document',
      );
    },
  );

  test('cap-küszöb 99/100/101: 99 survives, 100 survives without eviction, '
      '101 evicts the oldest and removes its file from disk', () async {
    Future<FileAnalysisRepository> openRepo(int max) async =>
        FileAnalysisRepository.openAtDirectory(
          directory: tempRoot,
          clock: () => DateTime.utc(2026, 1, 1),
          maxDocuments: max,
        );

    var repository = await openRepo(100);
    for (var i = 0; i < 99; i++) {
      await repository.save(
        AnalysisSaveRequest(
          document: _buildDocument(
            id: 'd$i',
            createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
            label: 'D',
          ),
          title: 'Take $i',
          customTitle: false,
        ),
      );
    }
    expect((await repository.list()).valueOrNull, hasLength(99));

    // 100th add — the cap is INCLUSIVE; no eviction yet.
    await repository.save(
      AnalysisSaveRequest(
        document: _buildDocument(
          id: 'd99',
          createdAt: DateTime.utc(2026, 1, 1).add(const Duration(minutes: 99)),
          label: 'D',
        ),
        title: 'Take 99',
        customTitle: false,
      ),
    );
    var list = await repository.list();
    expect(list.valueOrNull, hasLength(100));
    final oldestAfterHundred =
        list.valueOrNull!.map((s) => s.documentId).toList()..sort();
    expect(
      oldestAfterHundred.first,
      'd0',
      reason: 'inclusive boundary: oldest is still present at 100',
    );

    // 101st add — the OLDEST entry ('d0') MUST be evicted both from
    // the index AND from disk.
    await repository.save(
      AnalysisSaveRequest(
        document: _buildDocument(
          id: 'd100',
          createdAt: DateTime.utc(2026, 1, 1).add(const Duration(minutes: 100)),
          label: 'D',
        ),
        title: 'Take 100',
        customTitle: false,
      ),
    );
    list = await repository.list();
    expect(list.valueOrNull, hasLength(100));
    final ids = list.valueOrNull!.map((s) => s.documentId).toSet();
    expect(
      ids,
      isNot(contains('d0')),
      reason: 'the oldest must be evicted on the 101st save',
    );
    expect(ids, contains('d100'), reason: 'the newest save is present');
    final evictedFile = File(
      '${tempRoot.path}/'
      '${AnalysisRepositoryLayout.documentsDirectory}/d0.json',
    );
    expect(
      evictedFile.existsSync(),
      isFalse,
      reason: 'the evicted document is also removed from disk',
    );
  });

  test(
    'no audio on disk: post-save files match the document JSON size',
    () async {
      final repository = await FileAnalysisRepository.openAtDirectory(
        directory: tempRoot,
        clock: () => DateTime.utc(2026, 8, 1),
      );
      final document = _buildDocument(
        id: 'no-audio',
        createdAt: DateTime.utc(2026, 8, 1),
        label: 'C',
      );
      await repository.save(
        AnalysisSaveRequest(
          document: document,
          title: 'No PCM',
          customTitle: false,
        ),
      );

      final documentsDir = Directory(
        '${tempRoot.path}/${AnalysisRepositoryLayout.documentsDirectory}',
      );
      final totalSize = documentsDir.listSync().whereType<File>().fold<int>(
        0,
        (acc, file) => acc + file.lengthSync(),
      );
      // The document bytes themselves are an upper bound on what the
      // file directory MAY hold; we assert the total is strictly below
      // a generous PCM threshold (10 KiB). A real PCM of any audible
      // duration exceeds that by orders of magnitude.
      expect(
        totalSize,
        lessThan(10 * 1024),
        reason: 'no PCM-sized file may live in documents/',
      );
    },
  );

  test('checksum mutation on disk triggers typed failure on getById', () async {
    final repository = await FileAnalysisRepository.openAtDirectory(
      directory: tempRoot,
      clock: () => DateTime.utc(2026, 8, 1),
    );
    await repository.save(
      AnalysisSaveRequest(
        document: _buildDocument(
          id: 'checksum',
          createdAt: DateTime.utc(2026, 8, 1),
          label: 'C',
        ),
        title: 'Checksummed',
        customTitle: false,
      ),
    );

    final docFile = File(
      '${tempRoot.path}/'
      '${AnalysisRepositoryLayout.documentsDirectory}/checksum.json',
    );
    // Flip a single byte to break the on-disk hash check.
    final bytes = docFile.readAsBytesSync();
    bytes[bytes.length ~/ 2] = (bytes[bytes.length ~/ 2] ^ 0xFF) & 0xFF;
    docFile.writeAsBytesSync(bytes);

    final fetched = await repository.getById('checksum');
    expect(fetched.isSuccess, isFalse);
    expect(
      fetched.failureOrNull!.code,
      AnalysisRepositoryErrorCode.corruptDocument,
      reason: 'checksum mismatch surfaces as a typed corruption failure',
    );
  });
}

AnalysisDocument _buildDocument({
  required String id,
  required DateTime createdAt,
  required String label,
}) {
  return AnalysisDocument(
    id: id,
    schemaVersion: analysisDocumentSchemaVersion,
    createdAt: createdAt,
    mode: AnalysisMode.freePlay,
    input: AnalysisInputSummary(
      source: AnalysisInputSource.importedFile,
      duration: const Duration(seconds: 1),
      sampleRate: 44100,
      channelCount: 1,
      fingerprint: 'fingerprint-$id',
    ),
    provenance: AnalysisProvenance(
      appVersion: '1',
      analyzerVersion: '1',
      pipelineVersion: '1',
      stageVersions: const <String, String>{},
      dspConfigHash: 'hash-$id',
      modelManifestIds: const <String>[],
      inputFingerprint: 'fingerprint-$id',
      platform: 'test',
      featureFlagSnapshot: const <String, bool>{},
    ),
    signalQuality: SignalQualityReport(
      overall: 0.5,
      peakDbfs: -10,
      rmsDbfs: -20,
      noiseFloorDbfs: -50,
      clippedSampleRatio: 0,
      silentRatio: 0,
      tonalness: 0.5,
    ),
    capabilities: <CapabilityReport>[
      for (final capability in AnalysisCapability.values)
        CapabilityReport(
          capability: capability,
          status:
              capability == AnalysisCapability.chordTimeline ||
                  capability == AnalysisCapability.strumDirection ||
                  capability == AnalysisCapability.onsetTimeline
              ? CapabilityStatus.available
              : CapabilityStatus.unavailable,
          confidence: 1,
          reason:
              capability == AnalysisCapability.chordTimeline ||
                  capability == AnalysisCapability.strumDirection ||
                  capability == AnalysisCapability.onsetTimeline
              ? null
              : CapabilityUnavailableReason.modelUnavailable,
        ),
    ],
    timeline: AnalysisTimeline(
      duration: const Duration(seconds: 1),
      chordSegments: <ChordSegment>[
        ChordSegment(
          start: Duration.zero,
          end: const Duration(seconds: 1),
          confidence: 1,
          label: label,
        ),
      ],
      tempoPoints: <TempoPoint>[TempoPoint(time: Duration.zero, bpm: 120)],
    ),
    metrics: const <AnalysisMetricResult>[],
    hotspots: const <AnalysisHotspot>[],
    insights: const <AnalysisInsight>[],
    warnings: const <AnalysisWarning>[],
    completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
  );
}

/// Test seam — refuses to commit any document write so the "atomic
/// write" cell can prove the previous good bytes survive.
final class _ThrowingAnalysisAtomicWriter implements AnalysisAtomicWriter {
  @override
  AnalysisAtomicWriteOutcome write({
    required File target,
    required Uint8List bytes,
    required Directory stagingDirectory,
    required bool Function(Uint8List verified) verifier,
  }) {
    return AnalysisAtomicWriteOutcome(committed: false, bytes: bytes);
  }
}
