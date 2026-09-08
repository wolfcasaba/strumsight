// ignore_for_file: depend_on_referenced_packages

// R26 (audit MI4) — the write path a finished analysis takes.
//
// `saveAnalysisUseCaseProvider` shipped with ZERO callers in `lib/`
// (measured), so nothing a user recorded or imported ever reached the V2
// repository: the home screen promised "recent analyses" that only V1
// migration could ever fill. These cells measure the persister the
// controller now hands every finished document to.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:test/test.dart';

void main() {
  test('a finished document reaches the repository and then the recent '
      'list', () async {
    final repository = _RecordingRepository();
    final container = _container(repository);
    // The recent list is `autoDispose`: without a live listener the
    // invalidation below would land on a provider that no longer exists, and
    // the cell would prove nothing about what the home screen sees.
    final subscription = container.listen(
      analysisRecentSummariesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    expect(
      await container.read(analysisRecentSummariesProvider.future),
      isEmpty,
    );

    container.read(analysisDocumentPersisterProvider).persist(_document());
    await _flush();

    expect(repository.saved, hasLength(1));
    final request = repository.saved.single;
    // The V1 auto-title shape, so a migrated session and a fresh run read the
    // same way in one list. The imported FILE NAME is NOT the title: the
    // index would then carry it, and the index is not covered by the export
    // allowlist that keeps `input.sourceName` out of a shared export.
    expect(request.title, 'C · G');
    expect(request.customTitle, isFalse);
    expect(request.document.input.sourceName, 'private-take.wav');

    final refreshed = await container.read(
      analysisRecentSummariesProvider.future,
    );
    expect(refreshed, hasLength(1));
    expect(refreshed.single.documentId, 'test-document');
    expect(refreshed.single.title, 'C · G');
    expect(container.read(analysisPersistenceStatusProvider), isNull);
  });

  test('a failed write is reported, never swallowed', () async {
    final repository = _RecordingRepository(
      failure: const StorageFailure(code: FailureCode.storageWrite),
    );
    final logger = _RecordingLogger();
    final container = _container(repository, logger: logger);

    container.read(analysisDocumentPersisterProvider).persist(_document());
    await _flush();

    final status = container.read(analysisPersistenceStatusProvider);
    expect(status, isNotNull);
    expect(status!.code, FailureCode.storageWrite);
    // The diagnostic carries the CODE and nothing else: the document knows
    // the imported file's name, and a log line is the easiest place for that
    // to leak off the device.
    expect(logger.events, hasLength(1));
    expect(logger.events.single.fields, <String, Object?>{
      'code': FailureCode.storageWrite,
    });
    expect(logger.events.single.event, isNot(contains('private-take')));
  });
}

ProviderContainer _container(
  AnalysisRepository repository, {
  AppLogger? logger,
}) {
  final container = ProviderContainer(
    overrides: [
      analysisRepositoryProvider.overrideWithValue(repository),
      if (logger != null) appLoggerProvider.overrideWithValue(logger),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Two event-loop turns: the persister is deliberately fire-and-forget (the
/// controller must not block a state transition on a disk write), so the
/// write lands one microtask drain after `persist` returns.
Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _RecordingRepository implements AnalysisRepository {
  _RecordingRepository({this.failure});

  final AppFailure? failure;
  final saved = <AnalysisSaveRequest>[];

  @override
  Future<AppResult<void>> save(AnalysisSaveRequest request) async {
    final error = failure;
    if (error != null) return Failure<void>(error);
    saved.add(request);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<List<AnalysisSummary>>> list() async =>
      Success<List<AnalysisSummary>>(<AnalysisSummary>[
        for (final request in saved)
          AnalysisSummary(
            documentId: request.document.id,
            title: request.title,
            customTitle: request.customTitle,
            createdAt: request.document.createdAt,
            completionStatus: 'complete',
            documentHash: 'a' * 64,
            sizeBytes: 1,
          ),
      ]);

  @override
  Future<AppResult<AnalysisDocument>> getById(String id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> replace(String id, AnalysisSaveRequest request) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> rename({
    required String id,
    required String newTitle,
  }) => throw UnimplementedError();

  @override
  Future<AppResult<void>> delete(String id) => throw UnimplementedError();
}

final class _LogEvent {
  const _LogEvent(this.event, this.fields);

  final String event;
  final Map<String, Object?> fields;
}

final class _RecordingLogger implements AppLogger {
  final events = <_LogEvent>[];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {
    events.add(_LogEvent(event, fields));
  }

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {
    events.add(_LogEvent(event, fields));
  }

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    events.add(_LogEvent(event, fields));
  }

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    events.add(_LogEvent(event, fields));
  }
}

/// An IMPORTED document: the only provenance it carries about the file is the
/// display name in `input.sourceName`.
AnalysisDocument _document() => AnalysisDocument(
  id: 'test-document',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026),
  mode: AnalysisMode.importedRecording,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.importedFile,
    duration: const Duration(seconds: 1),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'a' * 64,
    sourceName: 'private-take.wav',
  ),
  provenance: AnalysisProvenance(
    appVersion: 'test',
    analyzerVersion: 'test',
    pipelineVersion: 'test',
    stageVersions: const <String, String>{},
    dspConfigHash: 'test',
    modelManifestIds: const <String>[],
    inputFingerprint: 'a' * 64,
    platform: 'test',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: .9,
    peakDbfs: -3,
    rmsDbfs: -20,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: .9,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(
    duration: const Duration(seconds: 1),
    chordSegments: <ChordSegment>[
      ChordSegment(
        id: 'chord-1',
        start: Duration.zero,
        end: const Duration(milliseconds: 500),
        confidence: .9,
        label: 'C',
      ),
      ChordSegment(
        id: 'chord-2',
        start: const Duration(milliseconds: 500),
        end: const Duration(seconds: 1),
        confidence: .9,
        label: 'G',
      ),
    ],
  ),
  metrics: const <AnalysisMetricResult>[],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
