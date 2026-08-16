import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  ExerciseCapabilities capabilitiesWith(
    Map<ExerciseCapability, CapabilitySupport> overrides,
  ) {
    final capabilities = allCapabilitiesUnsupported();
    return <ExerciseCapability, CapabilitySupport>{
      ...capabilities,
      ...overrides,
    };
  }

  SuccessCriteria criterion({
    SuccessCriterionKind kind = SuccessCriterionKind.completion,
    String description = 'Play the full prescribed set cleanly.',
    Iterable<ExerciseCapability> requiredCapabilities =
        const <ExerciseCapability>[ExerciseCapability.supportsChordScoring],
    double? minimumAccuracy,
  }) => SuccessCriteria(
    kind: kind,
    description: description,
    requiredCapabilities: requiredCapabilities,
    minimumAccuracy: minimumAccuracy,
  );

  group('SuccessCriteria — measurability (A3)', () {
    test(
      'accepts a criterion whose required capabilities are all supported',
      () {
        final supported = capabilitiesWith({
          ExerciseCapability.supportsChordScoring: CapabilitySupport.supported,
        });

        expect(
          () => criterion().ensureMeasurableFor(supported),
          returnsNormally,
        );
        expect(criterion().isMeasurableFor(supported), isTrue);
      },
    );

    test('rejects a criterion requiring an unsupported capability', () {
      final unsupported = allCapabilitiesUnsupported();

      expect(
        () => criterion().ensureMeasurableFor(unsupported),
        throwsArgumentError,
      );
      expect(criterion().isMeasurableFor(unsupported), isFalse);
    });

    test('rejects when only part of the required set is supported', () {
      final partial = capabilitiesWith({
        ExerciseCapability.supportsChordScoring: CapabilitySupport.supported,
      });
      final twoCapability = criterion(
        requiredCapabilities: const <ExerciseCapability>[
          ExerciseCapability.supportsChordScoring,
          ExerciseCapability.supportsTempo,
        ],
      );

      expect(
        () => twoCapability.ensureMeasurableFor(partial),
        throwsArgumentError,
      );
    });

    test(
      'completion is not an implicit exception to the measurability rule',
      () {
        final unsupported = allCapabilitiesUnsupported();
        final completion = criterion(kind: SuccessCriterionKind.completion);

        expect(
          () => completion.ensureMeasurableFor(unsupported),
          throwsArgumentError,
        );
      },
    );

    test(
      'assessmentOnly is not an implicit exception to the measurability rule',
      () {
        final unsupported = allCapabilitiesUnsupported();
        final assessmentOnly = criterion(
          kind: SuccessCriterionKind.assessmentOnly,
        );

        expect(
          () => assessmentOnly.ensureMeasurableFor(unsupported),
          throwsArgumentError,
        );
      },
    );
  });

  group('SuccessCriteria — explicit, never vacuous (A5)', () {
    test('rejects an empty requiredCapabilities set for completion', () {
      expect(
        () => criterion(
          kind: SuccessCriterionKind.completion,
          requiredCapabilities: const <ExerciseCapability>[],
        ),
        throwsArgumentError,
      );
    });

    test('rejects an empty requiredCapabilities set for assessmentOnly', () {
      expect(
        () => criterion(
          kind: SuccessCriterionKind.assessmentOnly,
          requiredCapabilities: const <ExerciseCapability>[],
        ),
        throwsArgumentError,
      );
    });

    test('decoding JSON with a missing requiredCapabilities field fails '
        'controlledly, never falls back to "already satisfied"', () {
      final malformed = <String, dynamic>{
        'kind': 'completion',
        'description': 'Play the full prescribed set cleanly.',
        // requiredCapabilities intentionally omitted.
      };

      expect(() => SuccessCriteria.fromJson(malformed), throwsArgumentError);
    });

    test('decoding JSON with an empty requiredCapabilities list fails', () {
      final malformed = <String, dynamic>{
        'kind': 'completion',
        'description': 'Play the full prescribed set cleanly.',
        'requiredCapabilities': <String>[],
      };

      expect(() => SuccessCriteria.fromJson(malformed), throwsArgumentError);
    });
  });

  group('SuccessCriteria — validation', () {
    test('rejects an out-of-range minimumAccuracy', () {
      expect(() => criterion(minimumAccuracy: 1.5), throwsArgumentError);
      expect(() => criterion(minimumAccuracy: -0.1), throwsArgumentError);
    });

    test('accepts a boundary minimumAccuracy of 0.0 and 1.0', () {
      expect(criterion(minimumAccuracy: 0).minimumAccuracy, 0);
      expect(criterion(minimumAccuracy: 1).minimumAccuracy, 1);
    });

    test('rejects an unknown enum code from JSON', () {
      final malformed = <String, dynamic>{
        'kind': 'not-a-real-kind',
        'description': 'Play the full prescribed set cleanly.',
        'requiredCapabilities': <String>['supportsChordScoring'],
      };

      expect(() => SuccessCriteria.fromJson(malformed), throwsArgumentError);
    });

    test('rejects an unknown capability code from JSON', () {
      final malformed = <String, dynamic>{
        'kind': 'completion',
        'description': 'Play the full prescribed set cleanly.',
        'requiredCapabilities': <String>['notARealCapability'],
      };

      expect(() => SuccessCriteria.fromJson(malformed), throwsArgumentError);
    });
  });

  group('SuccessCriteria — JSON round-trip (A6)', () {
    test('round-trips losslessly with a minimumAccuracy', () {
      final original = criterion(
        kind: SuccessCriterionKind.accuracyThreshold,
        description: 'Hit at least 90% of chord changes cleanly.',
        requiredCapabilities: const <ExerciseCapability>[
          ExerciseCapability.supportsChordScoring,
          ExerciseCapability.supportsTempo,
        ],
        minimumAccuracy: 0.9,
      );

      final decoded = SuccessCriteria.fromJson(original.toJson());

      expect(decoded, original);
      expect(decoded.kind, SuccessCriterionKind.accuracyThreshold);
      expect(decoded.description, original.description);
      expect(decoded.requiredCapabilities, original.requiredCapabilities);
      expect(decoded.minimumAccuracy, 0.9);
    });

    test('round-trips losslessly without a minimumAccuracy', () {
      final original = criterion(kind: SuccessCriterionKind.assessmentOnly);

      final decoded = SuccessCriteria.fromJson(original.toJson());

      expect(decoded, original);
      expect(decoded.minimumAccuracy, isNull);
    });
  });

  group('SuccessCriteria — equality', () {
    test('compares every value field', () {
      expect(criterion(), criterion());
      expect(criterion(description: 'Other description.'), isNot(criterion()));
      expect(
        criterion(
          requiredCapabilities: const <ExerciseCapability>[
            ExerciseCapability.supportsPitchScoring,
          ],
        ),
        isNot(criterion()),
      );
    });
  });
}
