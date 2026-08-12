// Index store tests for [AnalysisIndexStore] (ADR 0239 §Döntés 4,
// E06-R21 brief §6 "Index-újraépítés").
//
// Covers:
//   - read() returns an empty list when no file exists
//   - write() persists entries in a deterministic order
//   - read() throws AnalysisIndexCodecException on garbage
//   - read() throws on schema-version mismatch
//   - decode() rejects duplicate documentIds

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('analysis_index_store_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('read() returns [] when no index file exists', () {
    final store = AnalysisIndexStore.openAtDirectory(directory: tempRoot);
    expect(store.read(), isEmpty);
  });

  test('write() persists a deterministic, decodable list', () {
    final store = AnalysisIndexStore.openAtDirectory(directory: tempRoot);
    final summaries = <AnalysisSummary>[
      AnalysisSummary(
        documentId: 'a',
        title: 'A take',
        customTitle: false,
        createdAt: DateTime.utc(2026, 8, 1, 10),
        completionStatus: 'complete',
        documentHash: 'a' * 64,
        sizeBytes: 123,
      ),
      AnalysisSummary(
        documentId: 'b',
        title: 'B take',
        customTitle: true,
        createdAt: DateTime.utc(2026, 8, 1, 11),
        completionStatus: 'complete',
        documentHash: 'b' * 64,
        sizeBytes: 256,
      ),
    ];
    store.write(summaries);
    final loaded = store.read();
    expect(loaded, hasLength(2));
    expect(loaded.first.documentId, 'a');
    expect(loaded.last.documentId, 'b');
  });

  test('read() throws on garbage', () {
    final store = AnalysisIndexStore.openAtDirectory(directory: tempRoot);
    File('${tempRoot.path}/index.json').writeAsBytesSync(<int>[1, 2, 3]);
    expect(() => store.read(), throwsA(isA<AnalysisIndexCodecException>()));
  });

  test('read() throws on future schemaVersion', () {
    final store = AnalysisIndexStore.openAtDirectory(directory: tempRoot);
    File(
      '${tempRoot.path}/index.json',
    ).writeAsStringSync('{"schemaVersion":999,"summaries":[]}');
    expect(() => store.read(), throwsA(isA<AnalysisIndexCodecException>()));
  });

  test('decode() rejects duplicate documentIds', () {
    const codec = AnalysisIndexCodec();
    final payload = codec.encode(<AnalysisSummary>[
      AnalysisSummary(
        documentId: 'a',
        title: 'first',
        customTitle: false,
        createdAt: DateTime.utc(2026, 8, 1),
        completionStatus: 'complete',
        documentHash: 'a' * 64,
        sizeBytes: 1,
      ),
      AnalysisSummary(
        documentId: 'a',
        title: 'dup',
        customTitle: false,
        createdAt: DateTime.utc(2026, 8, 2),
        completionStatus: 'complete',
        documentHash: 'b' * 64,
        sizeBytes: 2,
      ),
    ]);
    expect(
      () => codec.decode(payload),
      throwsA(isA<AnalysisIndexCodecException>()),
    );
  });
}
