import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_enums.dart';

void main() {
  group('PlanStatus', () {
    test('JSON round-trip is stable for every code (A5)', () {
      for (final status in PlanStatus.values) {
        expect(PlanStatus.fromCode(status.code), status);
      }
    });

    test('known code decodes to the matching value', () {
      expect(PlanStatus.fromCode('active'), PlanStatus.active);
    });

    test('empty or null code is a controlled error, not a default (A6)', () {
      expect(() => PlanStatus.fromCode(''), throwsArgumentError);
      expect(() => PlanStatus.fromCode(null), throwsArgumentError);
    });

    test('unknown code is a controlled error, not a default (A6)', () {
      expect(() => PlanStatus.fromCode('valami_uj'), throwsArgumentError);
    });

    test('codes are the fixed persisted vocabulary, not the Dart name', () {
      expect(PlanStatus.values.map((status) => status.code), [
        'draft',
        'active',
        'paused',
        'completed',
        'archived',
        'superseded',
        'cancelled',
      ]);
    });
  });

  group('GenerationMode', () {
    test('JSON round-trip is stable for every code (A5)', () {
      for (final mode in GenerationMode.values) {
        expect(GenerationMode.fromCode(mode.code), mode);
      }
    });

    test('known code decodes to the matching value', () {
      expect(GenerationMode.fromCode('starter'), GenerationMode.starter);
    });

    test('empty or null code is a controlled error, not a default (A6)', () {
      expect(() => GenerationMode.fromCode(''), throwsArgumentError);
      expect(() => GenerationMode.fromCode(null), throwsArgumentError);
    });

    test('unknown code is a controlled error, not a default (A6)', () {
      expect(() => GenerationMode.fromCode('valami_uj'), throwsArgumentError);
    });

    test('codes are the fixed persisted vocabulary, not the Dart name', () {
      expect(GenerationMode.values.map((mode) => mode.code), [
        'starter',
        'adaptive',
        'songGoal',
        'maintenance',
        'returningAfterBreak',
        'microPlan',
        'assessment',
      ]);
    });
  });

  group('BlockKind', () {
    test('JSON round-trip is stable for every code (A5)', () {
      for (final kind in BlockKind.values) {
        expect(BlockKind.fromCode(kind.code), kind);
      }
    });

    test('known code decodes to the matching value', () {
      expect(BlockKind.fromCode('primaryFocus'), BlockKind.primaryFocus);
    });

    test('empty or null code is a controlled error, not a default (A6)', () {
      expect(() => BlockKind.fromCode(''), throwsArgumentError);
      expect(() => BlockKind.fromCode(null), throwsArgumentError);
    });

    test('unknown code is a controlled error, not a default (A6)', () {
      expect(() => BlockKind.fromCode('valami_uj'), throwsArgumentError);
    });

    test('codes are the fixed persisted vocabulary, not the Dart name', () {
      expect(BlockKind.values.map((kind) => kind.code), [
        'readiness',
        'warmup',
        'assessment',
        'primaryFocus',
        'secondaryFocus',
        'maintenance',
        'song',
        'freePlay',
        'reflection',
        'rest',
        'cooldown',
      ]);
    });
  });

  group('ValidationSeverity', () {
    test('JSON round-trip is stable for every code (A5)', () {
      for (final severity in ValidationSeverity.values) {
        expect(ValidationSeverity.fromCode(severity.code), severity);
      }
    });

    test('known code decodes to the matching value', () {
      expect(ValidationSeverity.fromCode('fatal'), ValidationSeverity.fatal);
    });

    test('empty or null code is a controlled error, not a default (A6)', () {
      expect(() => ValidationSeverity.fromCode(''), throwsArgumentError);
      expect(() => ValidationSeverity.fromCode(null), throwsArgumentError);
    });

    test('unknown code is a controlled error, not a default (A6)', () {
      expect(
        () => ValidationSeverity.fromCode('valami_uj'),
        throwsArgumentError,
      );
    });

    test('codes are the fixed persisted vocabulary, not the Dart name', () {
      expect(ValidationSeverity.values.map((severity) => severity.code), [
        'info',
        'warning',
        'error',
        'fatal',
      ]);
    });
  });

  group('CandidateSource', () {
    test('JSON round-trip is stable for every code (A5)', () {
      for (final source in CandidateSource.values) {
        expect(CandidateSource.fromCode(source.code), source);
      }
    });

    test('known code decodes to the matching value', () {
      expect(
        CandidateSource.fromCode('legacyLesson'),
        CandidateSource.legacyLesson,
      );
    });

    test('empty or null code is a controlled error, not a default (A6)', () {
      expect(() => CandidateSource.fromCode(''), throwsArgumentError);
      expect(() => CandidateSource.fromCode(null), throwsArgumentError);
    });

    test('unknown code is a controlled error, not a default (A6)', () {
      expect(() => CandidateSource.fromCode('valami_uj'), throwsArgumentError);
    });

    test('codes are the fixed persisted vocabulary, not the Dart name', () {
      expect(CandidateSource.values.map((source) => source.code), [
        'practiceCatalog',
        'legacyLesson',
        'songRange',
        'analysisHotspot',
        'visionCalibration',
        'assessment',
        'freePractice',
        'reflection',
        'rest',
      ]);
    });
  });
}
