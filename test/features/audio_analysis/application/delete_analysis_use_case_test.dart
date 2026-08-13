// DeleteAnalysisUseCase — 5-cell completeness (E06-R27 brief §6 acceptance
// criteria: "Törlés-teljesség"). Uses the real, unchanged R21
// FileAnalysisRepository for the document+index cells, and explicit fake
// cache/audio ports (ADR 0247 §Döntés 4 — no R28 cache exists yet).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

class _FakeCachePort implements AnalysisCachePort {
  final List<String> invalidated = <String>[];

  @override
  Future<void> invalidate(String documentId) async {
    invalidated.add(documentId);
  }
}

class _FakeAudioPort implements AnalysisAudioPort {
  _FakeAudioPort(this.audioFile);
  final File audioFile;
  bool deleted = false;

  @override
  Future<void> deleteIfExists(String documentId) async {
    if (audioFile.existsSync()) {
      audioFile.deleteSync();
    }
    deleted = true;
  }
}

class _FailingRepository implements AnalysisRepository {
  @override
  Future<AppResult<void>> delete(String id) async =>
      const AppResult<void>.failure(
        StorageFailure(code: AnalysisRepositoryErrorCode.io),
      );

  @override
  Future<AppResult<AnalysisDocument>> getById(String id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<List<AnalysisSummary>>> list() => throw UnimplementedError();

  @override
  Future<AppResult<void>> rename({
    required String id,
    required String newTitle,
  }) => throw UnimplementedError();

  @override
  Future<AppResult<void>> replace(String id, AnalysisSaveRequest request) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> save(AnalysisSaveRequest request) =>
      throw UnimplementedError();
}

AnalysisDocument _document(String id) => AnalysisDocument(
  id: id,
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 13),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 20),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'fp-$id',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1.0.0',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'cfg',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fp-$id',
    platform: 'android',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: 0.8,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0.5,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(duration: const Duration(seconds: 20)),
  metrics: const <AnalysisMetricResult>[],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'delete_analysis_use_case_test_',
    );
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('deletes the document file, the index entry, the cache entry, and the '
      'optional audio file — getById then returns null (five cells)', () async {
    final repository = await FileAnalysisRepository.openAtDirectory(
      directory: tempRoot,
    );
    const id = 'doc-to-delete';
    await repository.save(
      AnalysisSaveRequest(
        document: _document(id),
        title: 'To delete',
        customTitle: false,
      ),
    );

    final documentFile = File(
      '${tempRoot.path}/${AnalysisRepositoryLayout.documentsDirectory}/$id.json',
    );
    expect(documentFile.existsSync(), isTrue, reason: 'precondition');

    final audioFile = File('${tempRoot.path}/audio-$id.raw')
      ..writeAsStringSync('fake-audio-bytes');
    final cache = _FakeCachePort();
    final audio = _FakeAudioPort(audioFile);
    final useCase = DeleteAnalysisUseCase(
      repository: repository,
      cache: cache,
      audio: audio,
    );

    final result = await useCase(id);

    expect(result.isSuccess, isTrue);
    // (a) the document file is gone from disk.
    expect(documentFile.existsSync(), isFalse);
    // (b) the index no longer contains it.
    final listed = await repository.list();
    expect(listed.valueOrNull!.any((s) => s.documentId == id), isFalse);
    // (c) the cache entry is gone.
    expect(cache.invalidated, contains(id));
    // (d) getById returns null (a typed not-found failure).
    final byId = await repository.getById(id);
    expect(byId.isFailure, isTrue);
    // (e) the optional audio file is gone too.
    expect(audio.deleted, isTrue);
    expect(audioFile.existsSync(), isFalse);
  });

  test(
    'a repository failure short-circuits before the cache/audio ports run',
    () async {
      final cache = _FakeCachePort();
      final audio = _FakeAudioPort(File('${tempRoot.path}/missing.raw'));
      final useCase = DeleteAnalysisUseCase(
        repository: _FailingRepository(),
        cache: cache,
        audio: audio,
      );

      final result = await useCase('doc-x');

      expect(result.isFailure, isTrue);
      expect(cache.invalidated, isEmpty);
      expect(audio.deleted, isFalse);
    },
  );
}
