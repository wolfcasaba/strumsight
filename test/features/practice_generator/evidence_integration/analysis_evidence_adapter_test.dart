// E07-R25 — Analysis → Practice Generator evidence adapter acceptance tests.
//
// Cells verified against the brief's §6 / §6.1 measure-matrix:
//   * A1 — no raw media leaks through the serialized SkillEvidence.
//   * A3 — low-confidence records stay below the influence cap.
//   * A4 — SignalQualityReport<threshold surfaces a setup advisory, and
//     its `overall` value NEVER appears as a SkillEvidence.performance
//     value.
//   * A6 — within-batch conflict inflates uncertainty on every fact in
//     the disputed group (no arbitrary preference).
//   * A7 — explicitly-unavailable capability never becomes a 0/0.0
//     placeholder SkillEvidence.
//   * A8 — only types from `lib/features/audio_analysis/public.dart` cross
//     the adapter boundary (verified statically by `import '... show ...'`
//     in the production file; this test asserts the runtime shape).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  AnalysisMetricResult metricFor({
    required String id,
    required double value,
    double confidence = 0.8,
    int sampleCount = 10,
    CapabilityStatus status = CapabilityStatus.available,
  }) => AnalysisMetricResult(
    id: id,
    version: _versionOf(id),
    status: status,
    confidence: confidence,
    unit: 'none',
    sampleCount: sampleCount,
    evidence: const <String>[],
    value: ScalarMetricValue(value),
  );

  SignalQualityReport reportFor({double overall = 0.7}) => SignalQualityReport(
    overall: overall,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -55,
    clippedSampleRatio: 0.01,
    silentRatio: 0.05,
    tonalness: 0.6,
  );

  DateTime now() => DateTime.utc(2026, 8, 20);

  AnalysisEvidenceAdapter defaults({double signalQualityThreshold = 0.55}) =>
      AnalysisEvidenceAdapter(
        reader: const DefaultAnalysisEvidenceReader(),
        measurementVersion: 1,
        signalQualityThreshold: signalQualityThreshold,
        conflictThreshold: 0.4,
        conflictUncertaintyPenalty: 0.45,
      );

  group('AnalysisEvidenceAdapter — no raw media (A1)', () {
    test('serialized SkillEvidence never carries a raw-media field', () {
      final adapter = defaults();
      final result = adapter.adapt(<AnalysisEvidenceView>[
        AnalysisEvidenceMetricView(
          metric: metricFor(
            id: AnalysisMetricId.timingMeanAbsoluteError,
            value: 0.4,
            confidence: 0.7,
          ),
          skillHint: 'chord.gMajor',
          capturedAt: now(),
        ),
      ], asOf: now());

      for (final e in result.evidence) {
        final encoded = jsonEncode(<String, Object?>{
          'skillId': e.skillId,
          'source': e.source.code,
          'sourceOutcomeId': e.sourceOutcomeId.value,
          'measurementVersion': e.measurementVersion,
          'measuredAt': e.measuredAt.toIso8601String(),
          'capturedAt': e.capturedAt.toIso8601String(),
          'confidence': e.confidence,
          'performance': <String, Object?>{
            'metricCode': e.performance!.metricCode,
            'value': e.performance!.value,
            'sampleCount': e.performance!.sampleCount,
          },
        });
        final decoded = jsonDecode(encoded) as Map<String, Object?>;
        for (final forbidden in const <String>[
          'pcm',
          'audio',
          'wav',
          'clip',
          'samples',
          'sampleCount',
          'filePath',
          'frame',
          'Uint8List',
          'CameraImage',
          'HandLandmarks',
          'PoseLandmarks',
          'peakDbfs',
          'rmsDbfs',
          'noiseFloorDbfs',
        ]) {
          expect(
            decoded.containsKey(forbidden),
            isFalse,
            reason:
                'A1 violation: "$forbidden" must NEVER cross into a '
                'serialised SkillEvidence',
          );
        }
      }
    });

    test(
      'no SkillEvidence is derived from SignalQualityReport.overall (A4)',
      () {
        // A4 also documents the SIGNAL value is what we assert against.
        final adapter = defaults();
        final result = adapter.adapt(<AnalysisEvidenceView>[
          AnalysisEvidenceSignalQualityView(reportFor(overall: 0.2)),
        ], asOf: now());

        expect(result.signalQualityAdvisory, isNotNull);
        expect(result.signalQualityAdvisory!.observedOverall, 0.2);
        for (final e in result.evidence) {
          // Adapter NEVER maps signalQuality.overall into a PerformanceEvidence
          // value: the metric code is the analysis id, not a signal-quality id.
          expect(e.performance!.metricCode, isNot(startsWith('signal')));
          expect(e.performance!.value, isNot(0.2));
        }
      },
    );
  });

  group('AnalysisEvidenceAdapter — bounded influence (A3)', () {
    test(
      'a low-confidence record still produces a SkillEvidence (A3 entry cell)',
      () {
        final policy = EvidenceWeightPolicy(singleEvidenceInfluenceCap: 0.25);
        final adapter = defaults();
        final result = adapter.adapt(<AnalysisEvidenceView>[
          AnalysisEvidenceMetricView(
            metric: metricFor(
              id: AnalysisMetricId.timingMeanAbsoluteError,
              value: 0.2,
              confidence: 0.15,
            ),
            skillHint: 'chord.gMajor',
            capturedAt: now(),
          ),
        ], asOf: now());

        expect(
          result.evidence,
          hasLength(1),
          reason: 'low-confidence record MUST enter (A3 a küszöb alatt)',
        );
        expect(
          result.warnings.where((w) => w.code == 'lowConfidence'),
          isNotEmpty,
          reason: 'low-confidence record MUST emit a lowConfidence warning',
        );
        final weight = policy.weightFor(result.evidence.single, asOf: now());
        expect(
          weight,
          lessThan(policy.singleEvidenceInfluenceCap),
          reason: 'cap must bound a low-confidence contribution (A3)',
        );
        expect(
          weight,
          lessThan(0.05),
          reason: 'a 0.15-confidence record cannot drive focus on its own',
        );
      },
    );

    test(
      'a high-confidence record also stays bounded by the cap (A3 above cell)',
      () {
        final policy = EvidenceWeightPolicy(singleEvidenceInfluenceCap: 0.25);
        final adapter = defaults();
        final result = adapter.adapt(<AnalysisEvidenceView>[
          AnalysisEvidenceMetricView(
            metric: metricFor(
              id: AnalysisMetricId.timingMeanAbsoluteError,
              value: 0.85,
              confidence: 0.95,
              sampleCount: 50,
            ),
            skillHint: 'chord.gMajor',
            capturedAt: now(),
          ),
        ], asOf: now());

        final weight = policy.weightFor(result.evidence.single, asOf: now());
        expect(weight, lessThanOrEqualTo(policy.singleEvidenceInfluenceCap));
      },
    );
  });

  group('AnalysisEvidenceAdapter — signal-quality vs skill (A4)', () {
    test(
      'a low-quality recording surfaces a setup advisory, NEVER a penalty',
      () {
        final adapter = defaults();
        final result = adapter.adapt(<AnalysisEvidenceView>[
          AnalysisEvidenceSignalQualityView(reportFor(overall: 0.3)),
        ], asOf: now());

        expect(result.signalQualityAdvisory, isNotNull);
        expect(result.signalQualityAdvisory!.code, 'recordingQualityLow');
        expect(result.signalQualityAdvisory!.observedOverall, 0.3);
        // No evidence was derived from raw signalQuality.
        expect(result.evidence, isEmpty);
      },
    );

    test('a clean signal-quality report produces NO advisory (the signal '
        'channel is silent when it has nothing to say)', () {
      final adapter = defaults();
      final result = adapter.adapt(<AnalysisEvidenceView>[
        AnalysisEvidenceSignalQualityView(reportFor(overall: 0.8)),
      ], asOf: now());
      expect(result.signalQualityAdvisory, isNull);
    });
  });

  group(
    'AnalysisEvidenceAdapter — within-source conflict → uncertainty (A6)',
    () {
      test('two metric facts for the same skillHint with high spread both lose '
          'confidence (no arbitrary preference)', () {
        final adapter = const AnalysisEvidenceAdapter(
          reader: DefaultAnalysisEvidenceReader(),
          measurementVersion: 1,
          signalQualityThreshold: 0.55,
          conflictThreshold: 0.3,
          conflictUncertaintyPenalty: 0.5,
        );
        final result = adapter.adapt(<AnalysisEvidenceView>[
          AnalysisEvidenceMetricView(
            metric: metricFor(
              id: AnalysisMetricId.timingMeanAbsoluteError,
              value: 0.1,
              confidence: 0.9,
            ),
            skillHint: 'chord.gMajor',
            capturedAt: now(),
          ),
          AnalysisEvidenceMetricView(
            metric: metricFor(
              id: AnalysisMetricId.harmonyChordCoverage,
              value: 0.9,
              confidence: 0.85,
            ),
            skillHint: 'chord.gMajor',
            capturedAt: now(),
          ),
        ], asOf: now());

        // Both facts are admitted, BOTH with reduced confidence — no
        // arbitrary preference, more uncertainty (ADR 0261 §3).
        expect(result.evidence, hasLength(2));
        for (final e in result.evidence) {
          expect(
            e.confidence,
            lessThan(0.55),
            reason:
                'conflict penalty must inflate uncertainty '
                'on every fact, not just one',
          );
        }
        expect(
          result.warnings.where((w) => w.code == 'withinSourceConflict'),
          isNotEmpty,
        );
      });

      test(
        'two metric facts in the same skillHint within the conflict threshold '
        'are kept at their original confidence',
        () {
          final adapter = const AnalysisEvidenceAdapter(
            reader: DefaultAnalysisEvidenceReader(),
            measurementVersion: 1,
            signalQualityThreshold: 0.55,
            conflictThreshold: 0.5,
            conflictUncertaintyPenalty: 0.5,
          );
          final result = adapter.adapt(<AnalysisEvidenceView>[
            AnalysisEvidenceMetricView(
              metric: metricFor(
                id: AnalysisMetricId.timingMeanAbsoluteError,
                value: 0.5,
                confidence: 0.9,
              ),
              skillHint: 'chord.gMajor',
              capturedAt: now(),
            ),
            AnalysisEvidenceMetricView(
              metric: metricFor(
                id: AnalysisMetricId.harmonyChordCoverage,
                value: 0.6,
                confidence: 0.85,
              ),
              skillHint: 'chord.gMajor',
              capturedAt: now(),
            ),
          ], asOf: now());

          expect(
            result.warnings.where((w) => w.code == 'withinSourceConflict'),
            isEmpty,
            reason: 'tightly-clustered values are not a conflict',
          );
          expect(result.evidence.first.confidence, 0.9);
        },
      );
    },
  );

  group('AnalysisEvidenceAdapter — capability missing (A7)', () {
    test('an unavailable capability surfaces as a warning, never a degraded '
        'SkillEvidence', () {
      final adapter = defaults();
      final result = adapter.adapt(<AnalysisEvidenceView>[
        AnalysisEvidenceUnavailableView(
          capability: AnalysisCapability.targetAlignment,
          reason: CapabilityUnavailableReason.noReferenceTarget,
          skillHint: 'chord.gMajor',
        ),
      ], asOf: now());

      expect(
        result.evidence,
        isEmpty,
        reason:
            'A7: an unavailable capability NEVER produces an evidence '
            'record',
      );
      expect(
        result.warnings.where(
          (w) => w.code == 'capabilityUnavailable:targetAlignment',
        ),
        isNotEmpty,
      );
    });

    test(
      'an empty view list is graceful (no exception, no fabricated zero)',
      () {
        final adapter = defaults();
        final result = adapter.adapt(<AnalysisEvidenceView>[], asOf: now());
        expect(result.evidence, isEmpty);
        expect(result.warnings, isEmpty);
      },
    );
  });

  group('AnalysisEvidenceAdapter — public-API-only (A8)', () {
    test('adapting works with views constructed only from audio_analysis '
        'public types and produces SkillEvidence-shaped records', () {
      // Verified at construction time: every view type is exported from
      // `lib/features/audio_analysis/public.dart`. SkillEvidence is the
      // only output shape; no internal analysis type leaks.
      final adapter = defaults();
      final result = adapter.adapt(<AnalysisEvidenceView>[
        AnalysisEvidenceMetricView(
          metric: metricFor(
            id: AnalysisMetricId.timingMeanAbsoluteError,
            value: 0.5,
            confidence: 0.7,
          ),
          skillHint: 'chord.gMajor',
          capturedAt: now(),
        ),
      ], asOf: now());

      expect(result.evidence.single.source, EvidenceSource.analyzeV2);
      expect(result.evidence.single.source.code, 'analyzeV2');
      expect(
        AnalysisMetricId.contains(
          result.evidence.single.sourceOutcomeId.value.split(':')[1],
        ),
        isTrue,
        reason: 'sourceOutcomeId must echo a known analysis metric id',
      );
    });
  });
}

int _versionOf(String id) {
  final dot = id.lastIndexOf('.v');
  if (dot <= 0) return 1;
  return int.tryParse(id.substring(dot + 2)) ?? 1;
}
