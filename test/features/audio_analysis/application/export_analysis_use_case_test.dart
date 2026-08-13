// ExportAnalysisUseCase (E06-R27 brief §6 acceptance criteria: "Temp-fájl
// takarítás" call-through, preview never triggers a share).

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/share/public.dart';

class _FakeShareService extends ShareService {
  _FakeShareService();

  int shareExportFileCallCount = 0;
  String? lastCaption;
  String? lastFilePath;
  bool lastFileExistedAtCallTime = false;

  @override
  Future<void> shareExportFile({
    required File file,
    required String caption,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    shareExportFileCallCount += 1;
    lastCaption = caption;
    lastFilePath = file.path;
    lastFileExistedAtCallTime = file.existsSync();
  }
}

AnalysisDocument _document() => AnalysisDocument(
  id: 'doc-export-use-case',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 13),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 20),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'fp',
    sourceName: 'secret_filename.wav',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1.0.0',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'cfg',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fp',
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
      'export_analysis_use_case_test_',
    );
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('preview() never invokes the share service', () {
    final fake = _FakeShareService();
    final useCase = ExportAnalysisUseCase(
      shareService: fake,
      tempDirectory: tempRoot,
    );

    final export = useCase.preview(_document());

    expect(export.documentId, 'doc-export-use-case');
    expect(fake.shareExportFileCallCount, 0);
  });

  test('share() writes the redacted export to a temp file and hands it to '
      'the ShareService with the given caption', () async {
    final fake = _FakeShareService();
    final useCase = ExportAnalysisUseCase(
      shareService: fake,
      tempDirectory: tempRoot,
    );

    final result = await useCase.share(
      document: _document(),
      caption: 'my caption',
    );

    expect(result.isSuccess, isTrue);
    expect(fake.shareExportFileCallCount, 1);
    expect(fake.lastCaption, 'my caption');
    expect(fake.lastFileExistedAtCallTime, isTrue);
    expect(fake.lastFilePath, isNotNull);
    expect(fake.lastFilePath, startsWith(tempRoot.path));
  });

  test('the temp export file never contains the imported filename', () async {
    final fake = _FakeShareService();
    final useCase = ExportAnalysisUseCase(
      shareService: fake,
      tempDirectory: tempRoot,
    );

    await useCase.share(document: _document(), caption: 'c');

    final contents = File(fake.lastFilePath!).readAsStringSync();
    expect(contents.contains('secret_filename'), isFalse);
  });

  test('a forced write failure never strands the temp file and never '
      'reaches the ShareService', () async {
    final fake = _FakeShareService();
    final useCase = ExportAnalysisUseCase(
      shareService: fake,
      tempDirectory: tempRoot,
      fileWriter: (file, bytes) => Future<void>.error(
        const FileSystemException('forced write failure for test'),
      ),
    );

    final result = await useCase.share(document: _document(), caption: 'c');

    expect(result.isFailure, isTrue);
    expect(fake.shareExportFileCallCount, 0);
    expect(tempRoot.listSync(), isEmpty);
  });

  test('a write failure that leaves a partial file on disk still leaves '
      'the temp directory empty afterwards', () async {
    final fake = _FakeShareService();
    final useCase = ExportAnalysisUseCase(
      shareService: fake,
      tempDirectory: tempRoot,
      fileWriter: (file, bytes) async {
        await file.writeAsBytes(<int>[1, 2, 3], flush: true);
        throw const FileSystemException('forced partial-write failure');
      },
    );

    final result = await useCase.share(document: _document(), caption: 'c');

    expect(result.isFailure, isTrue);
    expect(fake.shareExportFileCallCount, 0);
    expect(tempRoot.listSync(), isEmpty);
  });
}
