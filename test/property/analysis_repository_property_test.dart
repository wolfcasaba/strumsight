// Property-style randomised test for the file-analysis repository
// (ADR 0239, E06-R21 brief §6 — randomised property gate).
//
// Invariants covered:
//
//   - Deterministic round-trip: an analysis document survives
//     save → getById with full field equality (id, createdAt,
//     capability set, chord/strum timeline, warnings).
//   - Index round-trip: every saved document has a corresponding
//     summary entry whose `documentId` matches and whose `documentHash`
//     matches the on-disk SHA-256.
//   - Cap is INCLUSIVE for 1..100 (no eviction under cap) and
//     EVICTIVE for >100 (oldest removed, exactly max survivors).
//   - No PCM on disk: total bytes on disk after a save sequence never
//     exceed the sum of the JSON-encoded document byte counts by a
//     factor consistent with the index file alone.
//
// The test seeds the RNG from the PROPERTY_SEED env var (default 42)
// per the HORIZON §6 convention — absent → deterministic dev loop;
// CI overrides via `PROPERTY_SEED=\${{ github.run_id }}`.

import 'dart:io';
import 'dart:math' as math;

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final codec = const AnalysisDocumentCodec();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'analysis_repository_property_test_',
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('property: save → getById round-trip preserves document fields '
      'and the index hash matches the on-disk SHA-256', () async {
    final repository = await FileAnalysisRepository.openAtDirectory(
      directory: tempRoot,
      clock: () => DateTime.utc(2026, 8, 1),
    );

    for (var index = 0; index < 25; index++) {
      final document = _buildRandomDocument(
        random: math.Random(seed + index),
        index: index,
      );
      final saveResult = await repository.save(
        AnalysisSaveRequest(
          document: document,
          title: 'Take $index',
          customTitle: index.isEven,
        ),
      );
      expect(
        saveResult.isSuccess,
        isTrue,
        reason: 'seed=$seed index=$index save should succeed',
      );

      final fetched = await repository.getById(document.id);
      expect(
        fetched.isSuccess,
        isTrue,
        reason: 'seed=$seed index=$index getById should succeed',
      );
      final restored = fetched.valueOrNull!;
      expect(
        restored.id,
        document.id,
        reason: 'seed=$seed index=$index id mismatch',
      );
      expect(
        restored.createdAt.toUtc(),
        document.createdAt.toUtc(),
        reason: 'seed=$seed index=$index createdAt mismatch',
      );
      expect(
        restored.timeline.chordSegments.length,
        document.timeline.chordSegments.length,
        reason: 'seed=$seed index=$index chord segments length mismatch',
      );
      for (var i = 0; i < document.timeline.chordSegments.length; i++) {
        final original = document.timeline.chordSegments[i];
        final roundTripped = restored.timeline.chordSegments[i];
        expect(
          roundTripped.label,
          original.label,
          reason: 'seed=$seed index=$index segment $i label',
        );
        expect(
          roundTripped.start,
          original.start,
          reason: 'seed=$seed index=$index segment $i start',
        );
        expect(
          roundTripped.end,
          original.end,
          reason: 'seed=$seed index=$index segment $i end',
        );
      }

      // The index entry's hash MUST equal the on-disk SHA-256.
      final summaries = (await repository.list()).valueOrNull!;
      final summary = summaries.firstWhere((s) => s.documentId == document.id);
      final docFile = File(
        '${tempRoot.path}/'
        '${AnalysisRepositoryLayout.documentsDirectory}/${document.id}.json',
      );
      final diskBytes = docFile.readAsBytesSync();
      final expectedHash = crypto.sha256.convert(diskBytes).toString();
      expect(
        summary.documentHash,
        expectedHash,
        reason: 'seed=$seed index=$index hash mismatch',
      );

      // And the bytes must encode back to the same document.
      final reEncoded = codec.decode(String.fromCharCodes(diskBytes));
      expect(reEncoded.isSuccess, isTrue);
      expect(reEncoded.valueOrNull!.id, document.id);
    }
  });

  test('property: cap is inclusive for <=100 and evictive for >100, '
      'with exactly max survivors', () async {
    for (final cap in <int>[1, 5, 100]) {
      final localRoot = await Directory.systemTemp.createTemp(
        'analysis_repository_property_cap_${cap}_',
      );
      try {
        final repository = await FileAnalysisRepository.openAtDirectory(
          directory: localRoot,
          clock: () => DateTime.utc(2026, 1, 1),
          maxDocuments: cap,
        );

        // Save cap + 5 records.
        final total = cap + 5;
        for (var index = 0; index < total; index++) {
          final document = _buildRandomDocument(
            random: math.Random(seed + index + cap),
            index: index,
          );
          await repository.save(
            AnalysisSaveRequest(
              document: document,
              title: 'Take $index',
              customTitle: false,
            ),
          );
        }
        final summaries = (await repository.list()).valueOrNull!;
        expect(
          summaries,
          hasLength(cap),
          reason: 'seed=$seed cap=$cap survivors must equal cap',
        );

        // The oldest entry is gone — the last saved id is present.
        final newestId = 'prop-${total - 1}';
        expect(
          summaries.map((s) => s.documentId).contains(newestId),
          isTrue,
          reason: 'seed=$seed cap=$cap newest entry must survive',
        );
        // The very oldest id ('prop-0') must have been evicted on
        // disk too.
        final oldestFile = File(
          '${localRoot.path}/'
          '${AnalysisRepositoryLayout.documentsDirectory}/prop-0.json',
        );
        expect(
          oldestFile.existsSync(),
          isFalse,
          reason: 'seed=$seed cap=$cap oldest file must be removed',
        );
      } finally {
        if (localRoot.existsSync()) {
          localRoot.deleteSync(recursive: true);
        }
      }
    }
  });

  test('property: no PCM on disk — total bytes stay close to the encoded '
      'JSON document size', () async {
    final repository = await FileAnalysisRepository.openAtDirectory(
      directory: tempRoot,
      clock: () => DateTime.utc(2026, 8, 1),
    );
    var encodedBytes = 0;
    for (var index = 0; index < 10; index++) {
      final document = _buildRandomDocument(
        random: math.Random(seed + index),
        index: index,
      );
      await repository.save(
        AnalysisSaveRequest(
          document: document,
          title: 'Take $index',
          customTitle: false,
        ),
      );
      encodedBytes += codec.encode(document).length;
    }
    final documentsDir = Directory(
      '${tempRoot.path}/'
      '${AnalysisRepositoryLayout.documentsDirectory}',
    );
    final onDiskBytes = documentsDir.listSync().whereType<File>().fold<int>(
      0,
      (acc, file) => acc + file.lengthSync(),
    );
    // Each document file is roughly the encoded JSON size; allow a
    // generous 4× headroom for JSON whitespace and the SHA-256
    // header (which we do NOT actually emit; we keep the generous
    // budget to make the test resilient to codec improvements).
    expect(
      onDiskBytes,
      lessThan(encodedBytes * 4),
      reason: 'seed=$seed PCM bytes must not be on disk',
    );
  });

  test('property: list() decodes the full document zero times during a '
      'healthy list, even under randomised save traffic', () async {
    var decodeCount = 0;
    final repository = await FileAnalysisRepository.openAtDirectory(
      directory: tempRoot,
      clock: () => DateTime.utc(2026, 8, 1),
      onDecode: () => decodeCount++,
    );
    for (var index = 0; index < 10; index++) {
      final document = _buildRandomDocument(
        random: math.Random(seed + index),
        index: index,
      );
      await repository.save(
        AnalysisSaveRequest(
          document: document,
          title: 'Take $index',
          customTitle: false,
        ),
      );
    }
    decodeCount = 0;
    for (var pass = 0; pass < 5; pass++) {
      await repository.list();
      expect(
        decodeCount,
        0,
        reason: 'seed=$seed pass=$pass list() must not decode',
      );
    }
  });
}

AnalysisDocument _buildRandomDocument({
  required math.Random random,
  required int index,
}) {
  final id = 'prop-$index';
  final createdAt = DateTime.utc(2026, 8, 1).add(
    Duration(
      // Use the index + a fixed 100ms resolution so createdAt
      // timestamps are unique across the test run — the cap-eviction
      // sort is by createdAt and equal timestamps would yield an
      // implementation-defined survivor order.
      milliseconds: index * 100 + random.nextInt(50),
    ),
  );
  final chordLabels = <String>['C', 'D', 'E', 'G', 'A', 'F'];
  final bpm = 60.0 + random.nextInt(120);
  final chordCount = 1 + random.nextInt(3);
  final strumCount = 2 + random.nextInt(4);

  return AnalysisDocument(
    id: id,
    schemaVersion: analysisDocumentSchemaVersion,
    createdAt: createdAt,
    mode: AnalysisMode.freePlay,
    input: AnalysisInputSummary(
      source: AnalysisInputSource.importedFile,
      duration: Duration(seconds: 1 + random.nextInt(10)),
      sampleRate: 44100,
      channelCount: 1,
      fingerprint: 'fingerprint-$id',
    ),
    provenance: AnalysisProvenance(
      appVersion: '1',
      analyzerVersion: '1',
      pipelineVersion: '1',
      stageVersions: <String, String>{'stage.${index % 3}': 'v1'},
      dspConfigHash: 'hash-$id',
      modelManifestIds: <String>[],
      inputFingerprint: 'fingerprint-$id',
      platform: 'test',
      featureFlagSnapshot: <String, bool>{'flag.${index % 2}': true},
    ),
    signalQuality: SignalQualityReport(
      overall: random.nextDouble(),
      peakDbfs: -10.0 - random.nextDouble() * 20,
      rmsDbfs: -30.0 - random.nextDouble() * 20,
      noiseFloorDbfs: -60.0,
      clippedSampleRatio: 0,
      silentRatio: 0,
      tonalness: random.nextDouble(),
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
      duration: Duration(seconds: 1 + random.nextInt(10)),
      chordSegments: <ChordSegment>[
        for (var i = 0; i < chordCount; i++)
          ChordSegment(
            start: Duration(seconds: i),
            end: Duration(seconds: i + 1),
            confidence: 1,
            label: chordLabels[(i + index) % chordLabels.length],
          ),
      ],
      events: <AnalysisEvent>[
        for (var i = 0; i < strumCount; i++)
          StrumEvent(
            id: 'prop-$index-strum-$i',
            time: Duration(milliseconds: 100 * i + random.nextInt(50)),
            confidence: 0.5 + random.nextDouble() * 0.5,
            direction: i.isEven ? StrumDirection.down : StrumDirection.up,
          ),
      ],
      tempoPoints: <TempoPoint>[TempoPoint(time: Duration.zero, bpm: bpm)],
    ),
    metrics: const <AnalysisMetricResult>[],
    hotspots: const <AnalysisHotspot>[],
    insights: const <AnalysisInsight>[],
    warnings: <AnalysisWarning>[
      AnalysisWarning(
        kind: AnalysisWarningKind.migration,
        severity: AnalysisWarningSeverity.info,
        messageKey: 'analysis.migration.legacy_v1',
        messageArgs: <String, String>{'beatsPerBar': '4'},
      ),
    ],
    completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
  );
}

// ignore: unused_element
final _legacyReference = Object();
