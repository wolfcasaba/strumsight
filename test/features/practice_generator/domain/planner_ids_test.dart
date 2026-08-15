import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';

void main() {
  group('construction validation (A3)', () {
    const invalidValues = <String>['', '   ', '\t', '\n', 'plan id', 'plan/id'];

    for (final invalid in invalidValues) {
      test('PlanId rejects "$invalid"', () {
        expect(() => PlanId(invalid), throwsArgumentError);
      });
      test('DayId rejects "$invalid"', () {
        expect(() => DayId(invalid), throwsArgumentError);
      });
      test('BlockId rejects "$invalid"', () {
        expect(() => BlockId(invalid), throwsArgumentError);
      });
      test('GoalId rejects "$invalid"', () {
        expect(() => GoalId(invalid), throwsArgumentError);
      });
      test('RevisionId rejects "$invalid"', () {
        expect(() => RevisionId(invalid), throwsArgumentError);
      });
      test('OutcomeId rejects "$invalid"', () {
        expect(() => OutcomeId(invalid), throwsArgumentError);
      });
    }

    test('a valid id constructs without error', () {
      expect(() => PlanId('plan-2026-08-15'), returnsNormally);
    });
  });

  group('equality and hashCode (A4)', () {
    test('same value -> equal PlanId, different value -> not equal', () {
      final a = PlanId('plan-1');
      final b = PlanId('plan-1');
      final c = PlanId('plan-2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('same value -> equal DayId, different value -> not equal', () {
      final a = DayId('day-1');
      final b = DayId('day-1');
      final c = DayId('day-2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('same value -> equal BlockId, different value -> not equal', () {
      final a = BlockId('block-1');
      final b = BlockId('block-1');
      final c = BlockId('block-2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('same value -> equal GoalId, different value -> not equal', () {
      final a = GoalId('goal-1');
      final b = GoalId('goal-1');
      final c = GoalId('goal-2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('same value -> equal RevisionId, different value -> not equal', () {
      final a = RevisionId('revision-1');
      final b = RevisionId('revision-1');
      final c = RevisionId('revision-2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('same value -> equal OutcomeId, different value -> not equal', () {
      final a = OutcomeId('outcome-1');
      final b = OutcomeId('outcome-1');
      final c = OutcomeId('outcome-2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('typed ID substitution (A2)', () {
    // A PlanId is never equal to a DayId built from the same underlying
    // string, even though both wrap identical text — the types are distinct
    // and unrelated, so this is also a compile error if either were ever
    // assigned to a variable/parameter typed as the other. That half of A2
    // is proven by the source compiling at all, not by a runtime assertion;
    // see docs/rounds/e07-r02-typed-ids-enums-and-domain-primitives.md §10
    // for the documented real-violation probe.
    test('same underlying string, different ID types -> not equal', () {
      final plan = PlanId('shared-1');
      final day = DayId('shared-1');

      // ignore: unrelated_type_equality_checks
      expect(plan == day, isFalse);
    });

    test('value accessor exposes the underlying string for persistence', () {
      expect(PlanId('plan-9').value, 'plan-9');
      expect(DayId('day-9').value, 'day-9');
      expect(BlockId('block-9').value, 'block-9');
      expect(GoalId('goal-9').value, 'goal-9');
      expect(RevisionId('revision-9').value, 'revision-9');
      expect(OutcomeId('outcome-9').value, 'outcome-9');
    });
  });
}
