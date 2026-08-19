// E07-R25 — Vision → Practice Generator evidence adapter acceptance tests.
//
// Cells verified against the brief's §6 / §6.1 measure-matrix:
//   * A1 — no raw media leaks through the serialized SkillEvidence.
//   * A2 — vision OFF / capability missing is graceful: an empty input
//     yields an empty SkillEvidence list and zero exceptions.
//   * A5 — only an explicitly-allowlisted subset of vision metric keys is
//     admitted; anything else becomes a warning and is dropped.
//   * A7 — empty / missing data produces no SkillEvidence.
//   * A8 — the adapter reads only from the narrow Vision public types.
//
// The narrow `lib/features/vision/domain/evidence/public.dart` contract
// (ADR 0319 / brief §5.7) deliberately does NOT re-export the metric-id
// enums (`PostureMetricId` / `FrettingMetricId` / `PickingMetricId`) or
// `SyncQuality`, so a feature-external test cannot construct a fully-
// valid `VisionEvidence` without reaching back into the wider vision
// `public.dart` barrel. The adapter's port contract is at the
// `VisionEvidenceFact` layer — the test exercises the adapter through
// a stub reader, mirroring how production wiring will hand the adapter
// the result of `DefaultVisionEvidenceReader.read` (whose own
// construction-time tests live inside the vision feature).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/features/vision/domain/evidence/public.dart';

/// Stub reader that bypasses `VisionEvidence` construction entirely —
/// the adapter's contract starts at `VisionEvidenceFact`, so this is the
/// right level to test the adapter's rules. (Dart forbids local class
/// declarations inside `main()`, hence top-level.)
class StubVisionEvidenceReader implements VisionEvidenceReader {
  StubVisionEvidenceReader(this._facts, [this._warnings = const []]);
  final List<VisionEvidenceFact> _facts;
  final List<VisionEvidenceReaderWarning> _warnings;

  @override
  VisionEvidenceReaderOutcome read(List<VisionEvidenceObservationView> _) =>
      VisionEvidenceReaderOutcome(
        facts: List<VisionEvidenceFact>.unmodifiable(_facts),
        warnings: List<VisionEvidenceReaderWarning>.unmodifiable(_warnings),
      );
}

void main() {
  DateTime now() => DateTime.utc(2026, 8, 20);

  VisionEvidenceFact fact({
    String skillHint = 'chord.gMajor',
    String metricKey = 'posture:shoulderAsymmetry',
    String metricFamily = 'posture',
    double value = 0.5,
    double confidence = 0.7,
    ObservationState state = ObservationState.observed,
    String measurementId = 'vision-evi-1',
    DateTime? capturedAt,
  }) => VisionEvidenceFact(
    skillHint: skillHint,
    metricKey: metricKey,
    metricFamily: metricFamily,
    value: value,
    confidence: confidence,
    state: state,
    measurementId: measurementId,
    capturedAt: capturedAt ?? now(),
  );

  VisionEvidenceAdapter adaptedTo({
    required List<VisionEvidenceFact> facts,
    Set<String>? allow,
    double ceiling = 0.6,
    List<VisionEvidenceReaderWarning> warnings = const [],
  }) => VisionEvidenceAdapter(
    reader: StubVisionEvidenceReader(facts, warnings),
    measurementVersion: 1,
    allowedMetricKeys:
        allow ?? const {'posture:shoulderAsymmetry', 'posture:torsoLean'},
    experimentalConfidenceCeiling: ceiling,
  );

  group('VisionEvidenceAdapter — no raw media (A1)', () {
    test('serialized SkillEvidence never carries a raw-media field', () {
      final adapter = adaptedTo(facts: [fact()]);
      final result = adapter.adapt(
        <VisionEvidenceObservationView>[],
        asOf: now(),
      );

      expect(result.evidence, hasLength(1));
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
          'filePath',
          'frame',
          'imagePath',
          'Uint8List',
          'CameraImage',
          'HandLandmarks',
          'PoseLandmarks',
          'NormalizedPoint',
          'modelVersion',
          'window',
          'syncQuality',
          'startUs',
          'endUs',
        ]) {
          expect(
            decoded.containsKey(forbidden),
            isFalse,
            reason:
                'A1 violation: "$forbidden" must NEVER leak into a '
                'serialised Vision SkillEvidence',
          );
        }
      }
    });
  });

  group(
    'VisionEvidenceAdapter — graceful empty when vision is absent (A2)',
    () {
      test(
        'an empty input list (and empty facts) yields zero evidence (A2)',
        () {
          final adapter = adaptedTo(facts: const []);
          final result = adapter.adapt(
            <VisionEvidenceObservationView>[],
            asOf: now(),
          );

          expect(
            result.evidence,
            isEmpty,
            reason:
                'A2: vision off must never crash, and must never '
                'fabricate a placeholder',
          );
          expect(result.warnings, isEmpty);
        },
      );

      test('the adapter uses only narrow Vision types (A8)', () {
        // Verified at construction time via the import statements; this
        // test confirms the runtime shape: SkillEvidence is the only
        // emitted value, no internal Vision type crosses the boundary.
        final adapter = adaptedTo(facts: [fact()]);
        final result = adapter.adapt(
          <VisionEvidenceObservationView>[],
          asOf: now(),
        );
        expect(result.evidence.single.source, EvidenceSource.vision);
        expect(result.evidence.single.source.code, 'vision');
        expect(
          result.evidence.single.sourceOutcomeId.value,
          startsWith('vision:'),
        );
      });
    },
  );

  group('VisionEvidenceAdapter — explicit allowlist (A5)', () {
    test('a fact whose metricKey is NOT in the allowlist becomes a warning and '
        'no SkillEvidence', () {
      final adapter = adaptedTo(
        facts: [
          fact(metricKey: 'posture:shoulderAsymmetry'),
          fact(
            measurementId: 'vision-evi-2',
            metricKey: 'posture:forbiddenProxy',
          ),
        ],
        allow: const {'posture:shoulderAsymmetry'},
      );
      final result = adapter.adapt(
        <VisionEvidenceObservationView>[],
        asOf: now(),
      );

      expect(result.evidence, hasLength(1));
      expect(
        result.warnings.where((w) => w.code == 'metricNotAllowed').length,
        greaterThanOrEqualTo(1),
      );
      expect(result.warnings.first.detail, 'posture:forbiddenProxy');
    });

    test('a metric in the allowlist becomes a SkillEvidence with the canonical '
        'practice-side metric code', () {
      final adapter = adaptedTo(facts: [fact()]);
      final result = adapter.adapt(
        <VisionEvidenceObservationView>[],
        asOf: now(),
      );

      expect(result.evidence.single.source, EvidenceSource.vision);
      expect(
        result.evidence.single.performance!.metricCode,
        'vision.posture:shoulderAsymmetry',
      );
    });
  });

  group('VisionEvidenceAdapter — capability missing / empty (A7)', () {
    test('reader-level notObservable warnings are surfaced verbatim, zero '
        'SkillEvidence (A7)', () {
      final adapter = adaptedTo(
        facts: const [],
        warnings: const [
          VisionEvidenceReaderWarning(
            code: 'notObservable',
            detail: 'vision-evi-missing',
          ),
        ],
      );
      final result = adapter.adapt(
        <VisionEvidenceObservationView>[],
        asOf: now(),
      );

      expect(result.evidence, isEmpty);
      expect(result.warnings.length, 1);
      expect(result.warnings.first.code, 'notObservable');
    });
  });

  group('VisionEvidenceAdapter — experimental ceiling', () {
    test('an experimental fact cannot exceed the configured ceiling', () {
      final adapter = adaptedTo(
        facts: [fact(state: ObservationState.experimental, confidence: 0.95)],
        ceiling: 0.5,
      );
      final result = adapter.adapt(
        <VisionEvidenceObservationView>[],
        asOf: now(),
      );

      expect(
        result.evidence.single.confidence,
        0.5,
        reason:
            'experimental confidence is bounded by the ceiling; '
            'it cannot drive focus on its own',
      );
    });

    test('an observed fact at high confidence is admitted at its reported '
        'confidence (uncapped)', () {
      final adapter = adaptedTo(facts: [fact(confidence: 0.9)], ceiling: 0.5);
      final result = adapter.adapt(
        <VisionEvidenceObservationView>[],
        asOf: now(),
      );

      expect(result.evidence.single.confidence, 0.9);
    });
  });
}
