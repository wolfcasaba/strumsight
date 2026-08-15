import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/learner_constraints.dart';
import 'package:strumsight/features/practice_generator/domain/model/plan_enums.dart';
import 'package:strumsight/features/practice_generator/domain/model/weekly_availability.dart';
import 'package:strumsight/features/practice_generator/domain/service/request_validator.dart';

void main() {
  const validator = RequestValidator();
  final emptyAvailability = WeeklyAvailability(const []);

  LearnerConstraint constraint(ConstraintStrength strength) =>
      LearnerConstraint(
        category: ConstraintCategory.comfort,
        strength: strength,
        code: 'wrist.pain',
        value: 'avoidBarreChords',
        softViolationCost: strength == ConstraintStrength.soft ? 7 : 0,
      );

  group('hard and soft violation handling', () {
    test('a hard constraint violation is an error, never a cost (A1)', () {
      final result = validator.validate(
        goals: const [],
        availability: emptyAvailability,
        scheduledMinutes: const {},
        constraintViolations: [
          ConstraintViolation(
            constraint: constraint(ConstraintStrength.hard),
            reason: 'The candidate requires barre chords despite wrist pain.',
          ),
        ],
      );

      expect(result.hasErrors, isTrue);
      expect(result.totalSoftViolationCost, 0);
      expect(result.findings.single.severity, ValidationSeverity.error);
      expect(
        result.findings.single.code,
        RequestValidationCode.hardConstraintViolated,
      );
    });

    test('a soft constraint violation is accepted with a cost (A2)', () {
      final result = validator.validate(
        goals: const [],
        availability: emptyAvailability,
        scheduledMinutes: const {},
        constraintViolations: [
          ConstraintViolation(
            constraint: constraint(ConstraintStrength.soft),
            reason: 'The candidate does not match the preferred style.',
          ),
        ],
      );

      expect(result.hasErrors, isFalse);
      expect(result.totalSoftViolationCost, 7);
      expect(result.findings.single.severity, ValidationSeverity.warning);
      expect(
        result.findings.single.code,
        RequestValidationCode.softConstraintViolated,
      );
    });
  });
}
