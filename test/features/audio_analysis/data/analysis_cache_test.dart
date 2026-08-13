import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/data/cache/analysis_cache.dart';
import 'package:strumsight/features/audio_analysis/data/cache/model_byte_cache.dart';
import 'package:strumsight/features/audio_analysis/domain/cache/analysis_cache_key.dart';
import 'package:strumsight/features/audio_analysis/public.dart'
    show
        AnalysisCapability,
        AnalysisCompletion,
        AnalysisCompletionStatus,
        AnalysisDocument,
        AnalysisInputSource,
        AnalysisInputSummary,
        AnalysisMode,
        AnalysisProvenance,
        AnalysisSaveRequest,
        AnalysisTimeline,
        CapabilityReport,
        CapabilityStatus,
        ChordSegment,
        FileAnalysisRepository,
        SignalQualityReport,
        TempoPoint,
        analysisDocumentSchemaVersion;

void main() {
  late Directory tempRoot;
  late DateTime now;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('analysis_cache_test_');
    now = DateTime.utc(2026, 8, 13);
  });

  Future<AnalysisCache> open({
    String subdirectory = 'cache',
    int maxEntries = AnalysisCache.defaultMaxEntries,
    int maxBytes = AnalysisCache.defaultMaxBytes,
  }) => AnalysisCache.openAtDirectory(
    directory: Directory('${tempRoot.path}/$subdirectory'),
    clock: () => now,
    maxEntries: maxEntries,
    maxBytes: maxBytes,
  );

  tearDown(() async {
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  test('cache stores and retrieves a compatible key', () async {
    final cache = await open();
    final key = _key('a');

    await cache.put(key, Uint8List.fromList(<int>[1, 2, 3]));

    expect(await cache.get(key), orderedEquals(<int>[1, 2, 3]));
  });

  test('entry count cap is inclusive at 19, 20, and 21 entries', () async {
    final cache = await open(maxEntries: 20, maxBytes: 10000);
    for (var index = 0; index < 19; index++) {
      now = now.add(const Duration(microseconds: 1));
      await cache.put(_key('$index'), Uint8List(1));
    }
    expect(await cache.entryCount(), 19);

    now = now.add(const Duration(microseconds: 1));
    await cache.put(_key('19'), Uint8List(1));
    expect(await cache.entryCount(), 20);

    now = now.add(const Duration(microseconds: 1));
    await cache.put(_key('20'), Uint8List(1));

    expect(await cache.entryCount(), 20);
    expect(await cache.get(_key('0')), isNull);
    expect(await cache.get(_key('20')), isNotNull);
  });

  test('LRU retains an old entry that was accessed between writes', () async {
    final cache = await open(maxEntries: 2, maxBytes: 10000);
    await cache.put(_key('old'), Uint8List(1));
    now = now.add(const Duration(microseconds: 1));
    await cache.put(_key('middle'), Uint8List(1));
    now = now.add(const Duration(microseconds: 1));
    await cache.get(_key('old'));
    now = now.add(const Duration(microseconds: 1));
    await cache.put(_key('new'), Uint8List(1));

    expect(await cache.get(_key('old')), isNotNull);
    expect(await cache.get(_key('middle')), isNull);
    expect(await cache.get(_key('new')), isNotNull);
  });

  test(
    'byte cap is inclusive at one below, exact, and one above the cap',
    () async {
      const cap = 8;
      expect(AnalysisCache.defaultMaxBytes, 52428800);
      expect(AnalysisCache.defaultMaxBytes - 1, 52428799);
      expect(AnalysisCache.defaultMaxBytes + 1, 52428801);
      final below = await open(maxEntries: 20, maxBytes: cap);
      await below.put(_key('below'), Uint8List(cap - 1));
      expect(await below.totalBytes(), cap - 1);

      final exact = await open(
        subdirectory: 'exact',
        maxEntries: 20,
        maxBytes: cap,
      );
      await exact.put(_key('exact'), Uint8List(cap));
      expect(await exact.totalBytes(), cap);

      final above = await open(
        subdirectory: 'above',
        maxEntries: 20,
        maxBytes: cap,
      );
      await above.put(_key('above'), Uint8List(cap + 1));
      expect(await above.entryCount(), 0);
    },
  );

  test('corrupt entry is a miss and is discarded', () async {
    final cache = await open();
    final key = _key('corrupt');
    await cache.put(key, Uint8List.fromList(<int>[1]));
    await cache.fileFor(key).writeAsString('{not JSON');

    expect(await cache.get(key), isNull);
    expect(await cache.fileFor(key).exists(), isFalse);
  });

  test('purging cache leaves saved analysis sessions untouched', () async {
    final repository = await FileAnalysisRepository.openAtDirectory(
      directory: Directory('${tempRoot.path}/saved_sessions'),
    );
    final document = _document('saved');
    await repository.save(
      AnalysisSaveRequest(
        document: document,
        title: 'Saved',
        customTitle: false,
      ),
    );
    final cache = await open(subdirectory: 'derived_cache');
    await cache.put(
      _key('derived'),
      Uint8List.fromList(<int>[1]),
      documentId: document.id,
    );

    await cache.purge();

    expect((await repository.list()).valueOrNull, hasLength(1));
    expect(
      (await repository.getById(document.id)).valueOrNull?.id,
      document.id,
    );
  });

  test(
    'single flight calls the producer once for concurrent equal keys',
    () async {
      final cache = await open();
      final gate = Completer<Uint8List>();
      var calls = 0;
      Future<Uint8List> producer() {
        calls++;
        return gate.future;
      }

      final first = cache.getOrCompute(_key('single'), producer);
      final second = cache.getOrCompute(_key('single'), producer);
      gate.complete(Uint8List.fromList(<int>[7, 8]));

      expect(await first, orderedEquals(<int>[7, 8]));
      expect(await second, orderedEquals(<int>[7, 8]));
      expect(calls, 1);
    },
  );

  test(
    'model byte cache reads and parses one manifest once across stages',
    () async {
      var reads = 0;
      var parses = 0;
      final cache = ModelByteCache<String>(
        readBundle: (manifestId) async {
          reads++;
          return Uint8List.fromList(manifestId.codeUnits);
        },
        parse: (bytes) {
          parses++;
          return String.fromCharCodes(bytes);
        },
      );

      final models = await Future.wait(<Future<String>>[
        cache.load('model-a'),
        cache.load('model-a'),
        cache.load('model-a'),
      ]);

      expect(models, orderedEquals(<String>['model-a', 'model-a', 'model-a']));
      expect(reads, 1);
      expect(parses, 1);
    },
  );
}

AnalysisCacheKey _key(String value) => AnalysisCacheKey(
  inputFingerprint: 'input-$value',
  analyzerVersion: 'analyzer-v1',
  modelManifestIds: const <String>['model-v1'],
  dspConfigHash: 'dsp-v1',
  targetHash: 'target-v1',
  featureFlagSnapshot: const <String, bool>{'v2': false},
);

AnalysisDocument _document(String id) => AnalysisDocument(
  id: id,
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 13),
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
    dspConfigHash: 'dsp',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fingerprint-$id',
    platform: 'test',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: .5,
    peakDbfs: -10,
    rmsDbfs: -20,
    noiseFloorDbfs: -50,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: .5,
  ),
  capabilities: <CapabilityReport>[
    for (final capability in AnalysisCapability.values)
      CapabilityReport(
        capability: capability,
        status: CapabilityStatus.available,
        confidence: 1,
      ),
  ],
  timeline: AnalysisTimeline(
    duration: const Duration(seconds: 1),
    chordSegments: <ChordSegment>[
      ChordSegment(
        start: Duration.zero,
        end: const Duration(seconds: 1),
        confidence: 1,
        label: 'C',
      ),
    ],
    tempoPoints: <TempoPoint>[TempoPoint(time: Duration.zero, bpm: 120)],
  ),
  metrics: const [],
  hotspots: const [],
  insights: const [],
  warnings: const [],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
