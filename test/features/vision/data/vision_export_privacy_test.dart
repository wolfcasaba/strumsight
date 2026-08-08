import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/vision/public.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

void main() {
  test('store and export pin the exact same privacy-safe DTO keys', () async {
    final store = InMemoryKeyValueStore();
    await VisionSessionRepository(store: store).save(_result());

    final storedEnvelope =
        jsonDecode(store.readString(StorageKeys.visionSessionHistory)!)
            as Map<String, dynamic>;
    final stored =
        (storedEnvelope['items'] as List<dynamic>).single
            as Map<String, dynamic>;
    final exported =
        jsonDecode(VisionExport(store: store).exportJson())
            as Map<String, dynamic>;
    final exportedEntry =
        (exported['sessions'] as List<dynamic>).single as Map<String, dynamic>;

    expect(_paths(stored), _expectedPaths);
    expect(_paths(exportedEntry), _expectedPaths);
    expect(exported['schemaVersion'], VisionSessionCodec.currentSchemaVersion);
    expect(_paths(stored), _paths(exportedEntry));
  });
}

const Set<String> _expectedPaths = <String>{
  'schemaVersion',
  'sessionId',
  'startedAt',
  'endedAt',
  'endReason',
  'quality',
  'quality.frameCount',
  'quality.framing',
  'quality.lighting',
  'quality.blur',
  'quality.stability',
  'quality.roiCoverage',
  'quality.overall',
  'quality.setupCue',
  'calibrationState',
  'insights',
  'insights.code',
  'insights.policyVersion',
  'insights.evidenceIds',
  'insights.confidence',
  'insights.priority',
  'insights.direction',
  'insights.capability',
  'observedFrameCount',
};

Set<String> _paths(Object? value, [String prefix = '']) {
  if (value is Map<String, dynamic>) {
    return <String>{
      for (final entry in value.entries) ...<String>{
        '$prefix${entry.key}',
        ..._paths(entry.value, '$prefix${entry.key}.'),
      },
    };
  }
  if (value is List && value.isNotEmpty) return _paths(value.first, prefix);
  return <String>{};
}

VisionSessionResult _result() => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create('privacy-test'),
    startedAt: DateTime.utc(2026, 8, 8),
  ),
  endedAt: DateTime.utc(2026, 8, 8, 0, 1),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(const <VisionFrameQuality>[]),
  calibrationState: CalibrationLossState.lost,
  sessionSummary: <VisionInsight>[
    VisionInsight(
      code: InsightCode.postureFocus,
      policyVersion: 'policy-v1',
      evidenceIds: const <String>['id-only'],
      confidence: 0.9,
    ),
  ],
  observedFrameCount: 0,
);
