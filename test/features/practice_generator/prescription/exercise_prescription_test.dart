import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  ExerciseCandidate candidate({
    String exerciseId = 'exercise.a',
    CandidateSource source = CandidateSource.practiceCatalog,
    Iterable<String> skillTargets = const <String>['rhythm.quarterNotes'],
    Map<ExerciseCapability, CapabilitySupport> capabilityOverrides =
        const <ExerciseCapability, CapabilitySupport>{
          ExerciseCapability.supportsChordScoring: CapabilitySupport.supported,
          ExerciseCapability.supportsTempo: CapabilitySupport.supported,
        },
    String contentRevision = 'content.v1',
  }) => ExerciseCandidate(
    exerciseId: exerciseId,
    source: source,
    skillTargets: skillTargets,
    prerequisites: const <String>['guitar.tuned'],
    supportedDurations: SupportedDurations.exact(const Duration(minutes: 30)),
    difficultyRange: DifficultyRange.exact('beginner'),
    capabilities: <ExerciseCapability, CapabilitySupport>{
      ...allCapabilitiesUnsupported(),
      ...capabilityOverrides,
    },
    loadProfile: const ExerciseLoadProfile.all(LoadLevel.low),
    offlineAvailable: true,
    contentRevision: contentRevision,
  );

  SuccessCriteria measurableCriteria({
    Iterable<ExerciseCapability> requiredCapabilities =
        const <ExerciseCapability>[ExerciseCapability.supportsChordScoring],
  }) => SuccessCriteria(
    kind: SuccessCriterionKind.completion,
    description: 'Complete the prescribed set cleanly.',
    requiredCapabilities: requiredCapabilities,
  );

  ExercisePrescription prescription({
    ExerciseCandidate? forCandidate,
    Duration activeDuration = const Duration(minutes: 5),
    Duration restDuration = const Duration(seconds: 30),
    int? tempoBpm,
    RepetitionPrescription? repetition,
    int loopCount = 1,
    Duration hardElapsedLimit = const Duration(minutes: 10),
    SuccessCriteria? successCriteria,
    Iterable<ExerciseCandidate> fallbackCandidates =
        const <ExerciseCandidate>[],
    ProgressionRule? progressionRule,
  }) => ExercisePrescription(
    candidate: forCandidate ?? candidate(),
    activeDuration: activeDuration,
    restDuration: restDuration,
    tempoBpm: tempoBpm,
    repetition: repetition ?? RepetitionPrescription(target: 8, maximum: 10),
    loopCount: loopCount,
    hardElapsedLimit: hardElapsedLimit,
    successCriteria: successCriteria ?? measurableCriteria(),
    fallbackCandidates: fallbackCandidates,
    progressionRule: progressionRule,
  );

  group('RepetitionPrescription — bounded repetition (A1)', () {
    test('accepts a target below the maximum', () {
      final repetition = RepetitionPrescription(target: 9, maximum: 10);
      expect(repetition.target, 9);
      expect(repetition.maximum, 10);
    });

    test('accepts a target exactly at the maximum (inclusive boundary)', () {
      final repetition = RepetitionPrescription(target: 10, maximum: 10);
      expect(repetition.target, 10);
      expect(repetition.maximum, 10);
    });

    test('rejects a target above the maximum', () {
      expect(
        () => RepetitionPrescription(target: 11, maximum: 10),
        throwsArgumentError,
      );
    });

    test('rejects decoding JSON without an explicit maximum', () {
      final malformed = <String, dynamic>{'target': 5};

      expect(
        () => RepetitionPrescription.fromJson(malformed),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive target or maximum', () {
      expect(
        () => RepetitionPrescription(target: 0, maximum: 10),
        throwsArgumentError,
      );
      expect(
        () => RepetitionPrescription(target: 5, maximum: 0),
        throwsArgumentError,
      );
    });
  });

  group('ExercisePrescription — tempo only for supported candidates (A2)', () {
    test('accepts a tempo prescription when the candidate supports it', () {
      expect(() => prescription(tempoBpm: 90), returnsNormally);
    });

    test(
      'rejects a tempo prescription when the candidate does not support it',
      () {
        final noTempo = candidate(
          capabilityOverrides: const <ExerciseCapability, CapabilitySupport>{
            ExerciseCapability.supportsChordScoring:
                CapabilitySupport.supported,
            ExerciseCapability.supportsTempo: CapabilitySupport.unsupported,
          },
        );

        expect(
          () => prescription(forCandidate: noTempo, tempoBpm: 90),
          throwsArgumentError,
        );
      },
    );

    test('rejects a non-positive tempo', () {
      expect(() => prescription(tempoBpm: 0), throwsArgumentError);
    });
  });

  group('ExercisePrescription — success criteria measurability (A3)', () {
    test('rejects a success criterion the candidate cannot measure', () {
      final noChordScoring = candidate(
        capabilityOverrides: const <ExerciseCapability, CapabilitySupport>{
          ExerciseCapability.supportsTempo: CapabilitySupport.supported,
        },
      );

      expect(
        () => prescription(forCandidate: noChordScoring),
        throwsArgumentError,
      );
    });
  });

  group('ExercisePrescription — fallback compatibility (A4)', () {
    test('accepts a fallback candidate with an identical skill-target set', () {
      final fallback = candidate(
        exerciseId: 'exercise.fallback',
        source: CandidateSource.legacyLesson,
      );

      final result = prescription(
        fallbackCandidates: <ExerciseCandidate>[fallback],
      );

      expect(result.fallbacks, hasLength(1));
      expect(result.fallbacks.single.exerciseId, 'exercise.fallback');
      expect(result.fallbacks.single.skillTargets, result.skillTargets);
    });

    test('rejects a fallback candidate that targets a different skill', () {
      final otherSkill = candidate(
        exerciseId: 'exercise.other-skill',
        skillTargets: const <String>['picking.alternate'],
      );

      expect(
        () => prescription(fallbackCandidates: <ExerciseCandidate>[otherSkill]),
        throwsArgumentError,
      );
    });

    test('rejects a fallback candidate with a superset skill-target set', () {
      final superset = candidate(
        exerciseId: 'exercise.superset',
        skillTargets: const <String>[
          'rhythm.quarterNotes',
          'picking.alternate',
        ],
      );

      expect(
        () => prescription(fallbackCandidates: <ExerciseCandidate>[superset]),
        throwsArgumentError,
      );
    });
  });

  group('ExercisePrescription — hard elapsed limit (A7)', () {
    test('accepts elapsed time strictly under the hard limit', () {
      final result = prescription(
        activeDuration: const Duration(minutes: 4),
        restDuration: const Duration(seconds: 30),
        loopCount: 1,
        hardElapsedLimit: const Duration(minutes: 10),
      );

      expect(result.elapsed, const Duration(minutes: 4, seconds: 30));
    });

    test('accepts elapsed time exactly at the hard limit (inclusive)', () {
      final result = prescription(
        activeDuration: const Duration(minutes: 3),
        restDuration: const Duration(minutes: 1),
        loopCount: 2,
        hardElapsedLimit: const Duration(minutes: 8),
      );

      expect(result.elapsed, const Duration(minutes: 8));
    });

    test('rejects elapsed time above the hard limit, never rounding down', () {
      expect(
        () => prescription(
          activeDuration: const Duration(minutes: 3),
          restDuration: const Duration(minutes: 1),
          loopCount: 2,
          hardElapsedLimit:
              const Duration(minutes: 8) - const Duration(microseconds: 1),
        ),
        throwsArgumentError,
      );
    });

    test('multiplies active+rest across every loop iteration', () {
      final result = prescription(
        activeDuration: const Duration(minutes: 1),
        restDuration: const Duration(seconds: 15),
        loopCount: 3,
        hardElapsedLimit: const Duration(minutes: 5),
      );

      expect(result.elapsed, const Duration(minutes: 3, seconds: 45));
    });
  });

  group('ExercisePrescription — construction validation', () {
    test('rejects a non-positive active duration', () {
      expect(
        () => prescription(activeDuration: Duration.zero),
        throwsArgumentError,
      );
    });

    test('rejects a negative rest duration', () {
      expect(
        () => prescription(restDuration: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('rejects a non-positive loop count', () {
      expect(() => prescription(loopCount: 0), throwsArgumentError);
    });
  });

  group('ExercisePrescription — JSON round-trip (A6)', () {
    test('round-trips losslessly with tempo, fallback and progression', () {
      final primary = candidate();
      final fallback = candidate(
        exerciseId: 'exercise.fallback',
        source: CandidateSource.legacyLesson,
      );
      final original = ExercisePrescription(
        candidate: primary,
        activeDuration: const Duration(minutes: 6, seconds: 12),
        restDuration: const Duration(seconds: 45),
        tempoBpm: 96,
        repetition: RepetitionPrescription(target: 6, maximum: 8),
        loopCount: 2,
        hardElapsedLimit: const Duration(minutes: 20),
        successCriteria: measurableCriteria(
          requiredCapabilities: const <ExerciseCapability>[
            ExerciseCapability.supportsChordScoring,
            ExerciseCapability.supportsTempo,
          ],
        ),
        fallbackCandidates: <ExerciseCandidate>[fallback],
        progressionRule: ProgressionRule(
          onSuccess: ProgressionStep(
            direction: ProgressionDirection.advance,
            repetitionTargetDelta: 1,
          ),
          onFailure: ProgressionStep(
            direction: ProgressionDirection.regress,
            repetitionTargetDelta: -1,
          ),
        ),
      );

      final decoded = ExercisePrescription.fromJson(
        original.toJson(),
        candidate: primary,
        fallbackCandidates: <ExerciseCandidate>[fallback],
      );

      expect(decoded, original);
      expect(decoded.activeDuration, original.activeDuration);
      expect(decoded.restDuration, original.restDuration);
      expect(decoded.tempoBpm, 96);
      expect(decoded.repetition, original.repetition);
      expect(decoded.loopCount, 2);
      expect(decoded.hardElapsedLimit, original.hardElapsedLimit);
      expect(decoded.successCriteria, original.successCriteria);
      expect(decoded.fallbacks, original.fallbacks);
      expect(decoded.progressionRule, original.progressionRule);
    });

    test('round-trips losslessly without tempo, fallback or progression', () {
      final primary = candidate();
      final original = prescription(forCandidate: primary);

      final decoded = ExercisePrescription.fromJson(
        original.toJson(),
        candidate: primary,
      );

      expect(decoded, original);
      expect(decoded.tempoBpm, isNull);
      expect(decoded.fallbacks, isEmpty);
      expect(decoded.progressionRule, isNull);
    });

    test('decoding JSON with a missing successCriteria fails controlledly', () {
      final primary = candidate();
      final original = prescription(forCandidate: primary);
      final malformed = Map<String, dynamic>.from(original.toJson())
        ..remove('successCriteria');

      expect(
        () => ExercisePrescription.fromJson(malformed, candidate: primary),
        throwsArgumentError,
      );
    });

    test('decoding re-validates the hard elapsed limit, never accepting a '
        'tampered document', () {
      final primary = candidate();
      final original = prescription(forCandidate: primary);
      final malformed = Map<String, dynamic>.from(original.toJson());
      malformed['hardElapsedLimitMicros'] = 1;

      expect(
        () => ExercisePrescription.fromJson(malformed, candidate: primary),
        throwsArgumentError,
      );
    });
  });

  group('ExercisePrescription — equality', () {
    test('compares every value field', () {
      final primary = candidate();
      expect(
        prescription(forCandidate: primary),
        prescription(forCandidate: primary),
      );
      expect(
        prescription(
          forCandidate: primary,
          loopCount: 2,
          hardElapsedLimit: const Duration(minutes: 20),
        ),
        isNot(prescription(forCandidate: primary)),
      );
    });
  });
}
