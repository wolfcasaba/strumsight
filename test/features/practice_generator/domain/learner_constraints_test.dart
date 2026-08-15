import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/learner_constraints.dart';

void main() {
  group('LearnerConstraint', () {
    test('comfort can be an explicit hard constraint (A3)', () {
      final constraint = LearnerConstraint(
        category: ConstraintCategory.comfort,
        strength: ConstraintStrength.hard,
        code: 'wrist.pain',
        value: 'avoidBarreChords',
      );

      expect(constraint.isHard, isTrue);
      expect(constraint.softViolationCost, 0);
    });

    test('hard constraints cannot be encoded as a cost', () {
      expect(
        () => LearnerConstraint(
          category: ConstraintCategory.comfort,
          strength: ConstraintStrength.hard,
          code: 'wrist.pain',
          value: 'avoidBarreChords',
          softViolationCost: 100,
        ),
        throwsArgumentError,
      );
    });

    test('soft constraints require a positive violation cost', () {
      expect(
        () => LearnerConstraint(
          category: ConstraintCategory.preference,
          strength: ConstraintStrength.soft,
          code: 'style',
          value: 'blues',
        ),
        throwsArgumentError,
      );
    });

    test('all required categories use stable codes', () {
      expect(ConstraintCategory.values.map((category) => category.code), [
        'equipment',
        'tuning',
        'capability',
        'comfort',
        'accessibility',
        'preference',
        'avoid',
      ]);
      expect(
        ConstraintCategory.fromCode('comfort'),
        ConstraintCategory.comfort,
      );
      expect(() => ConstraintCategory.fromCode('unknown'), throwsArgumentError);
    });

    test('constraint collection retains separate hard and soft sets', () {
      final constraints = LearnerConstraints([
        LearnerConstraint(
          category: ConstraintCategory.equipment,
          strength: ConstraintStrength.hard,
          code: 'instrument',
          value: 'acoustic',
        ),
        LearnerConstraint(
          category: ConstraintCategory.preference,
          strength: ConstraintStrength.soft,
          code: 'style',
          value: 'blues',
          softViolationCost: 3,
        ),
      ]);

      expect(constraints.hardConstraints, hasLength(1));
      expect(constraints.softConstraints, hasLength(1));
    });
  });
}
