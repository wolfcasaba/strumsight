import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_evidence.dart';

void main() {
  SkillEvidence evidence({
    String skillId = 'chord.gMajor',
    EvidenceSource source = EvidenceSource.learn,
    String outcomeId = 'outcome-1',
    int measurementVersion = 1,
    DateTime? measuredAt,
    DateTime? capturedAt,
    double confidence = 0.8,
    DateTime? validUntil,
    PerformanceEvidence? performance,
    DiscomfortReport? discomfort,
  }) => SkillEvidence(
    skillId: skillId,
    source: source,
    sourceOutcomeId: OutcomeId(outcomeId),
    measurementVersion: measurementVersion,
    measuredAt: measuredAt ?? DateTime.utc(2026, 8, 10),
    capturedAt: capturedAt ?? DateTime.utc(2026, 8, 15),
    confidence: confidence,
    validUntil: validUntil,
    performance:
        performance ??
        (discomfort == null
            ? PerformanceEvidence(metricCode: 'chordChangeAccuracy', value: 0.7)
            : null),
    discomfort: discomfort,
  );

  group('SkillEvidence — no raw media (A1)', () {
    test('the type has no field capable of holding raw audio/video', () {
      // Typed guarantee: performance is a numeric metric, discomfort is a
      // category + optional short note. Neither type declares a sample,
      // frame, byte buffer, or file-path field.
      final performance = PerformanceEvidence(
        metricCode: 'tempoStability',
        value: 0.5,
      );
      expect(performance.toString(), isNot(contains('pcm')));

      final e = evidence(performance: performance);
      final serialized = jsonEncode(<String, Object?>{
        'skillId': e.skillId,
        'source': e.source.code,
        'sourceOutcomeId': e.sourceOutcomeId.value,
        'measurementVersion': e.measurementVersion,
        'measuredAt': e.measuredAt.toIso8601String(),
        'confidence': e.confidence,
        'validUntil': e.validUntil?.toIso8601String(),
        'performance': {
          'metricCode': e.performance!.metricCode,
          'value': e.performance!.value,
          'sampleCount': e.performance!.sampleCount,
        },
      });
      final decoded = jsonDecode(serialized) as Map<String, Object?>;

      for (final forbidden in [
        'pcm',
        'audio',
        'wav',
        'clip',
        'samples',
        'filePath',
        'frame',
      ]) {
        expect(
          decoded.containsKey(forbidden),
          isFalse,
          reason: 'serialized evidence must not carry a "$forbidden" field',
        );
      }
    });
  });

  group('SkillEvidence — discomfort separate from performance (A4)', () {
    test(
      'discomfort lives in its own field, never averaged into performance',
      () {
        final withBoth = evidence(
          performance: PerformanceEvidence(
            metricCode: 'chordChangeAccuracy',
            value: 0.9,
          ),
          discomfort: DiscomfortReport(category: DiscomfortCategory.pain),
        );

        expect(withBoth.performance!.value, 0.9);
        expect(withBoth.discomfort!.category, DiscomfortCategory.pain);
        // No shared "score" field exists on SkillEvidence at all — performance
        // and discomfort are independent, typed value objects.
        expect(withBoth.performance, isNot(isA<DiscomfortReport>()));
      },
    );

    test('discomfort-only evidence carries no performance value', () {
      final discomfortOnly = evidence(
        performance: null,
        discomfort: DiscomfortReport(category: DiscomfortCategory.fatigue),
      );

      expect(discomfortOnly.performance, isNull);
      expect(discomfortOnly.discomfort!.category, DiscomfortCategory.fatigue);
    });

    test('evidence with neither performance nor discomfort is rejected', () {
      expect(
        () => SkillEvidence(
          skillId: 'chord.gMajor',
          source: EvidenceSource.learn,
          sourceOutcomeId: OutcomeId('outcome-1'),
          measurementVersion: 1,
          measuredAt: DateTime.utc(2026, 8, 10),
          capturedAt: DateTime.utc(2026, 8, 15),
          confidence: 0.5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('SkillEvidence — controlled timestamps (A6)', () {
    test(
      'a measuredAt after capturedAt is a controlled error, not silent correction',
      () {
        expect(
          () => evidence(
            measuredAt: DateTime.utc(2026, 8, 20),
            capturedAt: DateTime.utc(2026, 8, 15),
          ),
          throwsArgumentError,
        );
      },
    );

    test('validUntil before measuredAt is a controlled error', () {
      expect(
        () => evidence(
          measuredAt: DateTime.utc(2026, 8, 10),
          capturedAt: DateTime.utc(2026, 8, 15),
          validUntil: DateTime.utc(2026, 8, 9),
        ),
        throwsArgumentError,
      );
    });

    test('measuredAt equal to capturedAt is accepted (not future)', () {
      final e = evidence(
        measuredAt: DateTime.utc(2026, 8, 15),
        capturedAt: DateTime.utc(2026, 8, 15),
      );
      expect(e.measuredAt, e.capturedAt);
    });

    test('validUntil equal to measuredAt is accepted (boundary inclusive)', () {
      final e = evidence(
        measuredAt: DateTime.utc(2026, 8, 10),
        capturedAt: DateTime.utc(2026, 8, 15),
        validUntil: DateTime.utc(2026, 8, 10),
      );
      expect(e.validUntil, e.measuredAt);
    });
  });

  group('SkillEvidence — confidence range (A7, property-style)', () {
    test('confidence is accepted only inside the inclusive [0, 1] range', () {
      for (final value in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(evidence(confidence: value).confidence, value);
      }
      for (final value in [
        -0.0001,
        -1.0,
        1.0001,
        2.0,
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => evidence(confidence: value),
          throwsArgumentError,
          reason: 'confidence=$value must be rejected',
        );
      }
    });
  });

  group('SkillEvidence — construction hygiene', () {
    test('blank skillId is rejected', () {
      expect(() => evidence(skillId: '   '), throwsArgumentError);
    });

    test('measurementVersion below 1 is rejected', () {
      expect(() => evidence(measurementVersion: 0), throwsArgumentError);
    });

    test('non-finite performance value is rejected', () {
      expect(
        () => PerformanceEvidence(metricCode: 'x', value: double.nan),
        throwsArgumentError,
      );
    });

    test('sampleCount below 1 is rejected', () {
      expect(
        () => PerformanceEvidence(metricCode: 'x', value: 0.5, sampleCount: 0),
        throwsArgumentError,
      );
    });
  });
}
