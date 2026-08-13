// Allowlist-redaction property (E06-R27 brief §6 acceptance criteria:
// "Allowlist-redakció property", "Új mező szivárgás-próbája",
// "Tiltott tartalom mátrix — öt cella"). ADR 0247.
//
// The core assertion measures the *key-set difference* between the
// exported JSON and a fixed, independently-declared allowlist — not
// pattern matching against the implementation. A denylist redaction would
// still pass a pattern-matching test for the field it happens to know
// about; it fails this test because it forwards every key it does NOT
// know about, growing the observed key set past the allowlist.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

/// Every key this codec's fixed encoding is allowed to ever emit, at any
/// nesting depth. Declared independently of `AnalysisExportCodec` — a
/// change to the codec that adds an unreviewed key must fail this test.
const Set<String> _allowedKeys = <String>{
  'exportSchemaVersion',
  'documentId',
  'createdAt',
  'mode',
  'input',
  'source',
  'durationUs',
  'sampleRate',
  'channelCount',
  'signalQuality',
  'overall',
  'peakDbfs',
  'rmsDbfs',
  'noiseFloorDbfs',
  'clippedSampleRatio',
  'silentRatio',
  'tonalness',
  'measured',
  'capabilities',
  'capability',
  'status',
  'confidence',
  'reason',
  'metrics',
  'id',
  'version',
  'value',
  'unit',
  'sampleCount',
  'unavailableReason',
  'type',
  'valueUs',
  'values',
  'points',
  'timeUs',
  'hotspots',
  'kind',
  'startUs',
  'endUs',
  'severity',
  'insights',
  'ruleId',
  'ruleVersion',
  'priority',
  'messageKey',
  'messageArgs',
  'recommendedAction',
  'warnings',
  'completion',
  'failureCode',
  // The controlled set of message-argument names this fixture's own
  // insight/warning generator uses — never attacker/random-controlled.
  'milliseconds',
  'ratio',
};

Set<String> _collectKeys(Object? value) {
  final keys = <String>{};
  if (value is Map) {
    for (final entry in value.entries) {
      keys.add(entry.key as String);
      keys.addAll(_collectKeys(entry.value));
    }
  } else if (value is List) {
    for (final item in value) {
      keys.addAll(_collectKeys(item));
    }
  }
  return keys;
}

AnalysisDocument _document({
  required math.Random random,
  String? sourceName,
  String fingerprint = 'fp',
  Map<String, Object?> capabilityDetails = const <String, Object?>{},
  Map<String, String> insightMessageArgs = const <String, String>{},
  Map<String, String> warningMessageArgs = const <String, String>{},
}) {
  final metricStatuses = <CapabilityStatus>[
    CapabilityStatus.available,
    CapabilityStatus.degraded,
    CapabilityStatus.unavailable,
  ];
  final status = metricStatuses[random.nextInt(metricStatuses.length)];
  return AnalysisDocument(
    id: 'doc-${random.nextInt(1 << 31)}',
    schemaVersion: analysisDocumentSchemaVersion,
    createdAt: DateTime.utc(
      2026,
      8,
      13,
    ).add(Duration(minutes: random.nextInt(10000))),
    mode: AnalysisMode.values[random.nextInt(AnalysisMode.values.length)],
    input: AnalysisInputSummary(
      source: AnalysisInputSource
          .values[random.nextInt(AnalysisInputSource.values.length)],
      duration: Duration(seconds: 10 + random.nextInt(500)),
      sampleRate: 44100,
      channelCount: 1,
      fingerprint: fingerprint,
      sourceName: sourceName,
    ),
    provenance: AnalysisProvenance(
      appVersion: '1.0.0',
      analyzerVersion: '1',
      pipelineVersion: '1',
      stageVersions: const <String, String>{'onset': '87ms-internal-timing'},
      dspConfigHash: 'cfg',
      modelManifestIds: const <String>['model.v1'],
      inputFingerprint: fingerprint,
      platform: 'android',
      featureFlagSnapshot: const <String, bool>{},
    ),
    signalQuality: SignalQualityReport(
      overall: random.nextDouble(),
      peakDbfs: -random.nextDouble() * 10,
      rmsDbfs: -random.nextDouble() * 20,
      noiseFloorDbfs: -random.nextDouble() * 60,
      clippedSampleRatio: 0,
      silentRatio: 0,
      tonalness: random.nextDouble(),
    ),
    capabilities: <CapabilityReport>[
      CapabilityReport(
        capability: AnalysisCapability.onsetTimeline,
        status: CapabilityStatus.available,
        confidence: random.nextDouble(),
        details: capabilityDetails,
      ),
    ],
    timeline: AnalysisTimeline(duration: const Duration(seconds: 10)),
    metrics: <AnalysisMetricResult>[
      AnalysisMetricResult(
        id: AnalysisMetricId.timingMeanAbsoluteError,
        version: 1,
        status: status,
        confidence: random.nextDouble(),
        unit: 's',
        sampleCount: random.nextInt(100),
        evidence: const <String>['internal-evidence-id'],
        value: status == CapabilityStatus.unavailable
            ? null
            : ScalarMetricValue(random.nextDouble()),
        unavailableReason: status == CapabilityStatus.unavailable
            ? CapabilityUnavailableReason.inputTooNoisy
            : null,
      ),
    ],
    hotspots: const <AnalysisHotspot>[],
    insights: <AnalysisInsight>[
      AnalysisInsight(
        id: 'i-${random.nextInt(1 << 31)}',
        ruleId: 'r-1',
        ruleVersion: '1',
        priority: AnalysisInsightPriority.high,
        kind: AnalysisInsightKind.observation,
        factIds: const <String>['internal-fact-id'],
        messageKey: 'analysisInsightRushBias',
        messageArgs: <String, String>{
          'milliseconds': '${random.nextInt(50)}',
          ...insightMessageArgs,
        },
        recommendedAction: AnalysisRecommendedAction.slowDown,
      ),
    ],
    warnings: <AnalysisWarning>[
      AnalysisWarning(
        kind: AnalysisWarningKind.inputQuality,
        severity: AnalysisWarningSeverity.info,
        messageKey: 'analysisInsightLowSignalQuality',
        messageArgs: <String, String>{'ratio': '0.1', ...warningMessageArgs},
      ),
    ],
    completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
  );
}

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  const policy = RedactionPolicy();
  const codec = AnalysisExportCodec();

  String encodeOf(AnalysisDocument document) =>
      codec.encode(policy.apply(document));

  test('allowlist-redaction property: exported key set never exceeds the '
      'declared allowlist across randomized documents', () {
    for (var trial = 0; trial < 200; trial += 1) {
      final random = math.Random(seed + trial * 7919);
      final document = _document(
        random: random,
        sourceName: 'take-$trial.wav',
        capabilityDetails: <String, Object?>{
          'deviceId': 'device-secret-$trial',
          'internalNote': 'do-not-export-$trial',
        },
      );
      final encoded = encodeOf(document);
      final decoded = jsonDecode(encoded);
      final observedKeys = _collectKeys(decoded);
      final unexpected = observedKeys.difference(_allowedKeys);
      expect(
        unexpected,
        isEmpty,
        reason: 'seed=$seed trial=$trial leaked keys: $unexpected',
      );
    }
  });

  test('new-field leak probe: an unknown key injected into the diagnostic '
      'branch (CapabilityReport.details) never appears in the export', () {
    final random = math.Random(seed);
    final document = _document(
      random: random,
      capabilityDetails: const <String, Object?>{
        'brandNewUnreviewedField': 'sneaky-value-should-never-leak',
      },
    );
    final encoded = encodeOf(document);
    expect(encoded.contains('brandNewUnreviewedField'), isFalse);
    expect(encoded.contains('sneaky-value-should-never-leak'), isFalse);
  });

  group('forbidden content matrix — five cells', () {
    test('raw PCM bytes never appear in the export', () {
      final random = math.Random(seed);
      final document = _document(
        random: random,
        capabilityDetails: const <String, Object?>{
          'rawPcm': <int>[1, 2, 3, 4, 5, 6, 7, 8],
        },
      );
      expect(encodeOf(document).contains('rawPcm'), isFalse);
    });

    test('the imported filename never appears in the export', () {
      final random = math.Random(seed);
      final document = _document(
        random: random,
        sourceName: 'private-family-recording-do-not-share.wav',
      );
      expect(
        encodeOf(document).contains('private-family-recording-do-not-share'),
        isFalse,
      );
    });

    test('a device identifier never appears in the export', () {
      final random = math.Random(seed);
      final document = _document(
        random: random,
        capabilityDetails: const <String, Object?>{
          'deviceId': 'unique-hardware-serial-9f8e7d',
        },
      );
      expect(
        encodeOf(document).contains('unique-hardware-serial-9f8e7d'),
        isFalse,
      );
    });

    test('internal stage-timing never appears in the export', () {
      final random = math.Random(seed);
      final document = _document(random: random);
      // The document's own provenance carries stage timing
      // ('87ms-internal-timing' set by the fixture above) — the export
      // must never surface the provenance block at all.
      expect(encodeOf(document).contains('internal-timing'), isFalse);
    });

    test('Lab decoder diagnostics never appear in the export', () {
      final random = math.Random(seed);
      final document = _document(
        random: random,
        capabilityDetails: const <String, Object?>{
          'labDecoderDiagnostics': <String, Object?>{
            'nnlsResidual': 0.42,
            'decoderTraceId': 'lab-trace-secret',
          },
        },
      );
      expect(encodeOf(document).contains('labDecoderDiagnostics'), isFalse);
      expect(encodeOf(document).contains('lab-trace-secret'), isFalse);
    });
  });

  group('message-argument allowlist boundary (review BLOCKER)', () {
    // messageArgs is an unrestricted Map<String, String> on the source
    // model — RedactionPolicy must drop any key it does not name for the
    // given messageKey, not forward it because "it's just a string value".
    // Each forbidden payload is injected under an unknown key through BOTH
    // the insight and the warning branch.
    const forbiddenPayloads = <String, String>{
      'importedFileName': 'private-family-recording-do-not-share.wav',
      'rawAudioLike': 'RIFF....WAVEfmt sneaky-pcm-payload-bytes',
      'deviceId': 'unique-hardware-serial-9f8e7d',
      'diagnosticString': 'lab-trace-secret-decoder-residual-0.42',
    };

    for (final entry in forbiddenPayloads.entries) {
      test('insight messageArgs: an unknown key carrying a ${entry.key} '
          'payload never appears in the export', () {
        final random = math.Random(seed);
        final document = _document(
          random: random,
          insightMessageArgs: <String, String>{entry.key: entry.value},
        );
        final encoded = encodeOf(document);
        expect(encoded.contains(entry.key), isFalse);
        expect(encoded.contains(entry.value), isFalse);
      });

      test('warning messageArgs: an unknown key carrying a ${entry.key} '
          'payload never appears in the export', () {
        final random = math.Random(seed);
        final document = _document(
          random: random,
          warningMessageArgs: <String, String>{entry.key: entry.value},
        );
        final encoded = encodeOf(document);
        expect(encoded.contains(entry.key), isFalse);
        expect(encoded.contains(entry.value), isFalse);
      });
    }

    test('a known argument key on an unrecognised messageKey is still '
        'dropped — the allowlist is per-messageKey, not global', () {
      const policy = RedactionPolicy();
      final document = AnalysisDocument(
        id: 'doc-unknown-key',
        schemaVersion: analysisDocumentSchemaVersion,
        createdAt: DateTime.utc(2026, 8, 13),
        mode: AnalysisMode.freePlay,
        input: AnalysisInputSummary(
          source: AnalysisInputSource.microphone,
          duration: const Duration(seconds: 10),
          sampleRate: 44100,
          channelCount: 1,
          fingerprint: 'fp-unknown',
        ),
        provenance: AnalysisProvenance(
          appVersion: '1.0.0',
          analyzerVersion: '1',
          pipelineVersion: '1',
          stageVersions: const <String, String>{},
          dspConfigHash: 'cfg',
          modelManifestIds: const <String>[],
          inputFingerprint: 'fp-unknown',
          platform: 'android',
          featureFlagSnapshot: const <String, bool>{},
        ),
        signalQuality: SignalQualityReport(
          overall: 0.5,
          peakDbfs: -3,
          rmsDbfs: -18,
          noiseFloorDbfs: -60,
          clippedSampleRatio: 0,
          silentRatio: 0,
          tonalness: 0.5,
        ),
        capabilities: const <CapabilityReport>[],
        timeline: AnalysisTimeline(duration: const Duration(seconds: 10)),
        metrics: const <AnalysisMetricResult>[],
        hotspots: const <AnalysisHotspot>[],
        insights: const <AnalysisInsight>[],
        warnings: <AnalysisWarning>[
          AnalysisWarning(
            kind: AnalysisWarningKind.inputQuality,
            severity: AnalysisWarningSeverity.info,
            messageKey: 'some.future.unreviewed.messageKey',
            messageArgs: const <String, String>{
              'stageId': 'sneaky-value-should-never-leak',
            },
          ),
        ],
        completion: AnalysisCompletion(
          status: AnalysisCompletionStatus.complete,
        ),
      );
      final export = policy.apply(document);
      expect(export.warnings.single.messageArgs, isEmpty);
    });
  });
}
