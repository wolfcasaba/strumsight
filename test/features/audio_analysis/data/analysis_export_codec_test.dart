// Codec determinism + JSON-schema stability + "no network" source-scan +
// ShareCardBuilder confidence-marking (E06-R27 brief §6 acceptance
// criteria: "JSON-séma stabilitás", "Nincs hálózat", "Confidence-jelölés").
// share_card_builder.dart has no dedicated test file in this round's
// allowed_paths (docs/rounds/e06-r27-export-share-and-privacy-controls.md
// §4) — its unit coverage lives here, alongside the codec it is packaged
// with under data/export/.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

AnalysisDocument _document() {
  return AnalysisDocument(
    id: 'doc-codec',
    schemaVersion: analysisDocumentSchemaVersion,
    createdAt: DateTime.utc(2026, 8, 13, 10, 30),
    mode: AnalysisMode.freePlay,
    input: AnalysisInputSummary(
      source: AnalysisInputSource.microphone,
      duration: const Duration(seconds: 90),
      sampleRate: 48000,
      channelCount: 1,
      fingerprint: 'fp-codec',
      sourceName: 'my_take_final.wav',
    ),
    provenance: AnalysisProvenance(
      appVersion: '1.0.0',
      analyzerVersion: '1',
      pipelineVersion: '1',
      stageVersions: const <String, String>{'onset': '120ms'},
      dspConfigHash: 'cfg-hash',
      modelManifestIds: const <String>['model.v1'],
      inputFingerprint: 'fp-codec',
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
    capabilities: <CapabilityReport>[
      CapabilityReport(
        capability: AnalysisCapability.onsetTimeline,
        status: CapabilityStatus.available,
        confidence: 0.9,
        details: const <String, Object?>{'deviceId': 'device-secret-123'},
      ),
    ],
    timeline: AnalysisTimeline(duration: const Duration(seconds: 90)),
    metrics: <AnalysisMetricResult>[
      AnalysisMetricResult(
        id: AnalysisMetricId.timingMeanAbsoluteError,
        version: 1,
        status: CapabilityStatus.available,
        confidence: 0.7,
        unit: 's',
        sampleCount: 12,
        evidence: const <String>['ev-1'],
        value: ScalarMetricValue(0.05),
      ),
    ],
    hotspots: const <AnalysisHotspot>[],
    insights: <AnalysisInsight>[
      AnalysisInsight(
        id: 'i-1',
        ruleId: 'r-1',
        ruleVersion: '1',
        priority: AnalysisInsightPriority.high,
        kind: AnalysisInsightKind.observation,
        factIds: const <String>['f-1'],
        messageKey: 'analysisInsightRushBias',
        messageArgs: const <String, String>{'milliseconds': '12'},
        recommendedAction: AnalysisRecommendedAction.slowDown,
      ),
    ],
    warnings: const <AnalysisWarning>[],
    completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
  );
}

void main() {
  const policy = RedactionPolicy();
  const codec = AnalysisExportCodec();

  test('encode is byte-identical across two independent encodes', () {
    final export = policy.apply(_document());
    final first = codec.encode(export);
    final second = codec.encode(policy.apply(_document()));
    expect(first, second);
  });

  test('round trip: decode(encode(x)) reproduces the export payload', () {
    final export = policy.apply(_document());
    final encoded = codec.encode(export);
    final decoded = codec.decode(encoded);
    expect(decoded.isSuccess, isTrue);
    final reEncoded = codec.encode((decoded as Success<AnalysisExport>).value);
    expect(reEncoded, encoded);
  });

  test('encoded JSON carries an explicit exportSchemaVersion field', () {
    final export = policy.apply(_document());
    final encoded = codec.encode(export);
    final json = jsonDecode(encoded) as Map<String, Object?>;
    expect(json['exportSchemaVersion'], analysisExportSchemaVersion);
  });

  test('no network import — the export domain/data/presentation files never '
      'import dio, http, or core/network', () {
    final files = <String>[
      'lib/features/audio_analysis/domain/export/analysis_export.dart',
      'lib/features/audio_analysis/domain/export/redaction_policy.dart',
      'lib/features/audio_analysis/data/export/analysis_export_codec.dart',
      'lib/features/audio_analysis/data/export/share_card_builder.dart',
      'lib/features/audio_analysis/application/export_analysis_use_case.dart',
      'lib/features/audio_analysis/application/delete_analysis_use_case.dart',
      'lib/features/audio_analysis/presentation/analysis_export_screen.dart',
      'lib/features/audio_analysis/presentation/widgets/export_preview.dart',
    ];
    for (final path in files) {
      final contents = File(path).readAsStringSync();
      expect(
        contents.contains("package:dio") ||
            contents.contains("package:http") ||
            contents.contains('core/network/'),
        isFalse,
        reason: '$path must not import a network dependency',
      );
    }
  });

  group('ShareCardBuilder confidence marking', () {
    const builder = ShareCardBuilder();

    AnalysisDocument documentWithMetrics(List<AnalysisMetricResult> metrics) =>
        AnalysisDocument(
          id: 'doc-card',
          schemaVersion: analysisDocumentSchemaVersion,
          createdAt: DateTime.utc(2026, 8, 13),
          mode: AnalysisMode.freePlay,
          input: AnalysisInputSummary(
            source: AnalysisInputSource.microphone,
            duration: const Duration(seconds: 30),
            sampleRate: 48000,
            channelCount: 1,
            fingerprint: 'fp-card',
          ),
          provenance: AnalysisProvenance(
            appVersion: '1.0.0',
            analyzerVersion: '1',
            pipelineVersion: '1',
            stageVersions: const <String, String>{},
            dspConfigHash: 'cfg',
            modelManifestIds: const <String>[],
            inputFingerprint: 'fp-card',
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
          timeline: AnalysisTimeline(duration: const Duration(seconds: 30)),
          metrics: metrics,
          hotspots: const <AnalysisHotspot>[],
          insights: const <AnalysisInsight>[],
          warnings: const <AnalysisWarning>[],
          completion: AnalysisCompletion(
            status: AnalysisCompletionStatus.complete,
          ),
        );

    test('a degraded metric is included and marked as degraded', () {
      final document = documentWithMetrics(<AnalysisMetricResult>[
        AnalysisMetricResult(
          id: AnalysisMetricId.timingMeanAbsoluteError,
          version: 1,
          status: CapabilityStatus.degraded,
          confidence: 0.4,
          unit: 's',
          sampleCount: 5,
          evidence: const <String>[],
          value: ScalarMetricValue(0.09),
        ),
      ]);

      final card = builder.build(document);

      expect(card.metrics, hasLength(1));
      expect(card.metrics.single.isDegraded, isTrue);
    });

    test('an unavailable metric never appears as a value on the card', () {
      final document = documentWithMetrics(<AnalysisMetricResult>[
        AnalysisMetricResult(
          id: AnalysisMetricId.timingMeanAbsoluteError,
          version: 1,
          status: CapabilityStatus.unavailable,
          confidence: 0,
          unit: 's',
          sampleCount: 0,
          evidence: const <String>[],
          unavailableReason: CapabilityUnavailableReason.clipTooShort,
        ),
      ]);

      final card = builder.build(document);

      expect(card.metrics, isEmpty);
    });

    test('no positive/neutral insight — the card omits the insight rather '
        'than showing a negative one', () {
      final document = documentWithMetrics(const <AnalysisMetricResult>[]);
      final card = builder.build(document);
      expect(card.insight, isNull);
    });

    group('low-confidence available metric — boundary at 0.4', () {
      AnalysisMetricResult availableMetric(double confidence) =>
          AnalysisMetricResult(
            id: AnalysisMetricId.timingMeanAbsoluteError,
            version: 1,
            status: CapabilityStatus.available,
            confidence: confidence,
            unit: 's',
            sampleCount: 5,
            evidence: const <String>[],
            value: ScalarMetricValue(0.05),
          );

      test('strictly below the threshold (0.39) is marked, never a plain '
          'fact', () {
        final document = documentWithMetrics(<AnalysisMetricResult>[
          availableMetric(0.39),
        ]);
        final card = builder.build(document);
        expect(card.metrics.single.isDegraded, isTrue);
      });

      test('exactly on the threshold (0.4) is treated as a plain fact', () {
        final document = documentWithMetrics(<AnalysisMetricResult>[
          availableMetric(0.4),
        ]);
        final card = builder.build(document);
        expect(card.metrics.single.isDegraded, isFalse);
      });

      test('strictly above the threshold (0.41) is a plain fact', () {
        final document = documentWithMetrics(<AnalysisMetricResult>[
          availableMetric(0.41),
        ]);
        final card = builder.build(document);
        expect(card.metrics.single.isDegraded, isFalse);
      });
    });
  });
}
