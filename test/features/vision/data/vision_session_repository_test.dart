import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/vision/public.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

void main() {
  group('VisionSessionRepository', () {
    test(
      'vN round-trip is byte-stable and retains only aggregate fields',
      () async {
        final codec = const VisionSessionCodec();
        const modelVersions = <String, String>{
          'hand_landmarker': '1.2.3',
          'pose_landmarker': '4.5.6',
        };
        final entry = codec.fromResult(
          _result('one'),
          modelVersions: modelVersions,
        );

        expect(
          codec.encode(entry),
          codec.encode(codec.decodeFromMap(codec.encodeToMap(entry))),
        );

        final store = InMemoryKeyValueStore();
        final repository = VisionSessionRepository(
          store: store,
          codec: codec,
          manifestReader: _ManifestReader(modelVersions),
        );
        await repository.save(_result('one'));

        final restored = repository.list().single;
        expect(restored.sessionId, 'one');
        expect(restored.quality.overall, VisionMetricState.good);
        expect(
          restored.insights.single.capability,
          FeedbackCapability.fretting,
        );
        expect(restored.observedFrameCount, 12);
        expect(restored.modelVersions, modelVersions);
      },
    );

    test('vN+1 item shape is skipped fail-loud without misreading history', () {
      final store = InMemoryKeyValueStore(<String, Object>{
        StorageKeys.visionSessionHistory: jsonEncode(<String, Object>{
          'schemaVersion': 1,
          'items': <Object>[
            <String, Object>{'schemaVersion': 2},
          ],
        }),
      });

      expect(VisionSessionRepository(store: store).list(), isEmpty);
      expect(store.readString(StorageKeys.visionSessionHistory), isNotNull);
    });

    test(
      'one malformed record is skipped while a valid session remains readable',
      () async {
        final codec = const VisionSessionCodec();
        final valid = codec.encodeToMap(
          codec.fromResult(
            _result('kept'),
            modelVersions: const <String, String>{'hand_landmarker': '1.2.3'},
          ),
        );
        final store = InMemoryKeyValueStore(<String, Object>{
          StorageKeys.visionSessionHistory: jsonEncode(<String, Object>{
            'schemaVersion': 1,
            'items': <Object>[
              valid,
              <String, Object>{'schemaVersion': 1, 'sessionId': 'broken'},
            ],
          }),
        });
        final repository = VisionSessionRepository(store: store, codec: codec);

        expect(repository.list().map((entry) => entry.sessionId), <String>[
          'kept',
        ]);

        await repository.deleteSession('kept');
        final raw =
            jsonDecode(store.readString(StorageKeys.visionSessionHistory)!)
                as Map<String, dynamic>;
        expect(raw['items'], isEmpty);
      },
    );

    test(
      'an unreadable manifest fails before a history record is written',
      () async {
        final store = InMemoryKeyValueStore();
        final repository = VisionSessionRepository(
          store: store,
          manifestReader: const _UnreadableManifestReader(),
        );

        await expectLater(
          repository.save(_result('unattributed')),
          throwsStateError,
        );

        expect(store.readString(StorageKeys.visionSessionHistory), isNull);
      },
    );

    test(
      'deleting one session changes raw history but preserves another',
      () async {
        final store = InMemoryKeyValueStore();
        final repository = VisionSessionRepository(store: store);
        await repository.save(_result('delete-me'));
        await repository.save(_result('keep-me'));

        await repository.deleteSession('delete-me');

        final raw =
            jsonDecode(store.readString(StorageKeys.visionSessionHistory)!)
                as Map<String, dynamic>;
        final items = raw['items'] as List<dynamic>;
        expect(
          items.map((item) => (item as Map<String, dynamic>)['sessionId']),
          <String>['keep-me'],
        );
      },
    );

    test(
      'delete all removes every Vision key and quarantine shadow from raw store',
      () async {
        final store = InMemoryKeyValueStore(<String, Object>{
          StorageKeys.visionSessionHistory: 'history',
          StorageKeys.quarantineOf(StorageKeys.visionSessionHistory):
              'history-corrupt',
          StorageKeys.visionCalibration: 'calibration',
          StorageKeys.quarantineOf(StorageKeys.visionCalibration):
              'calibration-corrupt',
        });

        await VisionSessionRepository(store: store).deleteAllVisionData();

        for (final key in StorageKeys.visionData) {
          expect(store.readString(key), isNull, reason: key);
          expect(
            store.readString(StorageKeys.quarantineOf(key)),
            isNull,
            reason: key,
          );
        }
      },
    );
  });
}

VisionSessionResult _result(String id) => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create(id),
    startedAt: DateTime.utc(2026, 8, 8, 10),
  ),
  endedAt: DateTime.utc(2026, 8, 8, 10, 1),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(<VisionFrameQuality>[
    VisionFrameQuality(
      thresholdsVersion: 'quality-v1',
      framing: VisionMetricState.good,
      lighting: VisionLighting.good,
      blur: VisionMetricState.good,
      stability: VisionMetricState.good,
      roiCoverage: VisionMetricState.good,
      overall: VisionMetricState.good,
      meanLuminance: 1,
      highlightClippingRatio: 0,
      shadowClippingRatio: 0,
      sharpness: 1,
      cameraMotion: 0,
      roiCoverageRatio: 1,
    ),
  ]),
  calibrationState: CalibrationLossState.tracking,
  sessionSummary: <VisionInsight>[
    VisionInsight(
      code: InsightCode.frettingStable,
      policyVersion: 'policy-v1',
      evidenceIds: const <String>['evidence-id'],
      confidence: 0.9,
    ),
  ],
  observedFrameCount: 12,
);

final class _ManifestReader implements VisionModelManifestReader {
  const _ManifestReader(this._versions);

  final Map<String, String> _versions;

  @override
  Future<VisionModelManifestReport> read() async => VisionModelManifestReport(
    entries: <VisionModelEntry>[
      for (final entry in _versions.entries)
        VisionModelEntry(
          modelId: entry.key,
          version: entry.value,
          path: 'assets/ml/${entry.key}.tflite',
          sha256: '0' * 64,
          status: VisionModelStatus.active,
          inputShape: const <int>[1, 1, 1],
          outputSchema: handLandmarksOutputSchema,
          licenseSpdx: 'Apache-2.0',
          licenseName: 'Apache License 2.0',
          minimumDeviceTier: 'low',
          evaluationReport: 'test',
        ),
    ],
    issues: const <String>[],
  );
}

final class _UnreadableManifestReader implements VisionModelManifestReader {
  const _UnreadableManifestReader();

  @override
  Future<VisionModelManifestReport> read() async => VisionModelManifestReport(
    entries: const <VisionModelEntry>[],
    issues: const <String>['manifest unavailable'],
  );
}
