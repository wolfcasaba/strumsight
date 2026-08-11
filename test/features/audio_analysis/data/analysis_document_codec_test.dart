import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  const codec = AnalysisDocumentCodec();

  test('round-trips all persisted document fields deterministically', () {
    final original = _document();

    final first = codec.encode(original);
    final second = codec.encode(original);
    final decoded = codec.decode(first);

    expect(first, second);
    expect(decoded, isA<Success<AnalysisDocument>>());
    final result = decoded as Success<AnalysisDocument>;
    expect(_normalized(codec.encode(result.value)), _normalized(first));
    expect(result.value.timeline.duration, const Duration(microseconds: 1));
    expect(result.value.signalQuality.measured, isTrue);
    expect(result.value.metrics.single.value, isA<ScalarMetricValue>());
  });

  test('accepts only schema version one and ignores future extra fields', () {
    final valid = jsonDecode(codec.encode(_document())) as Map<String, dynamic>;

    for (final version in <Object?>[0, 2, null, '1']) {
      final candidate = Map<String, dynamic>.from(valid);
      if (version == null) {
        candidate.remove('schemaVersion');
      } else {
        candidate['schemaVersion'] = version;
      }
      expect(
        codec.decode(jsonEncode(candidate)),
        isA<Failure<AnalysisDocument>>(),
      );
    }

    valid['futureField'] = 1;
    expect(codec.decode(jsonEncode(valid)), isA<Success<AnalysisDocument>>());
  });

  test(
    'rejects unknown required enums and non-finite confidence and values',
    () {
      final source =
          jsonDecode(codec.encode(_document())) as Map<String, dynamic>;
      final completion = Map<String, dynamic>.from(
        source['completion'] as Map<String, dynamic>,
      )..['status'] = 'future';
      expect(
        codec.decode(
          jsonEncode(<String, Object?>{...source, 'completion': completion}),
        ),
        isA<Failure<AnalysisDocument>>(),
      );

      final capability = Map<String, dynamic>.from(
        (source['capabilities'] as List<Object?>).first as Map<String, dynamic>,
      );
      for (final invalid in <Object?>['NaN', 'Infinity', '-Infinity']) {
        capability['confidence'] = invalid;
        expect(
          codec.decode(
            jsonEncode(<String, Object?>{
              ...source,
              'capabilities': <Object?>[capability],
            }),
          ),
          isA<Failure<AnalysisDocument>>(),
        );
      }

      final metric = Map<String, dynamic>.from(
        (source['metrics'] as List<Object?>).first as Map<String, dynamic>,
      );
      final metricValue = Map<String, dynamic>.from(
        metric['value'] as Map<String, dynamic>,
      );
      for (final invalid in <Object?>['NaN', 'Infinity', '-Infinity']) {
        metricValue['value'] = invalid;
        metric['value'] = metricValue;
        expect(
          codec.decode(
            jsonEncode(<String, Object?>{
              ...source,
              'metrics': <Object?>[metric],
            }),
          ),
          isA<Failure<AnalysisDocument>>(),
        );
      }
    },
  );

  test('rejects non-finite values nested in capability details', () {
    final source = codec.encode(_document());
    final corrupt = source.replaceFirst(
      '"details":{}',
      '"details":{"x":1e999}',
    );

    expect(codec.decode(corrupt), isA<Failure<AnalysisDocument>>());
  });
}

String _normalized(String value) => jsonEncode(jsonDecode(value));

AnalysisDocument _document() => AnalysisDocument(
  id: 'document-1',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 11, 12),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(microseconds: 1),
    sampleRate: 44100,
    channelCount: 1,
    fingerprint: 'input-1',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{'stage': '1'},
    dspConfigHash: 'dsp',
    modelManifestIds: const <String>['model'],
    inputFingerprint: 'input-1',
    platform: 'android',
    featureFlagSnapshot: const <String, bool>{'flag': false},
  ),
  signalQuality: SignalQualityReport(
    overall: .5,
    peakDbfs: -1,
    rmsDbfs: -12,
    noiseFloorDbfs: -48,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: .5,
  ),
  capabilities: <CapabilityReport>[
    CapabilityReport(
      capability: AnalysisCapability.onsetTimeline,
      status: CapabilityStatus.available,
      confidence: 1,
    ),
  ],
  timeline: AnalysisTimeline(
    duration: const Duration(microseconds: 1),
    tempoPoints: <TempoPoint>[TempoPoint(time: Duration.zero, bpm: 120)],
  ),
  metrics: <AnalysisMetricResult>[
    AnalysisMetricResult(
      id: AnalysisMetricId.timingMeanAbsoluteError,
      version: 1,
      status: CapabilityStatus.available,
      confidence: 1,
      value: ScalarMetricValue(.5),
      unit: 'ratio',
      sampleCount: 1,
      evidence: const <String>['event-1'],
    ),
  ],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
