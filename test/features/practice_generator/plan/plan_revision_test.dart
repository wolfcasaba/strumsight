import 'package:flutter_test/flutter_test.dart';
import '../../../fixtures/practice_generator/plan/plan_fixtures.dart';

void main() {
  group('PlanRevision', () {
    test('rejects a revision number below the current revision', () {
      final current = revision(number: 2);

      expect(() => revision(number: 1, previous: current), throwsArgumentError);
    });

    test('rejects a revision number equal to the current revision', () {
      final current = revision(number: 2);

      expect(() => revision(number: 2, previous: current), throwsArgumentError);
    });

    test('accepts a revision number above the current revision', () {
      final current = revision(number: 2);

      expect(() => revision(number: 3, previous: current), returnsNormally);
    });

    test('keeps a full immutable snapshot when a later plan changes', () {
      final fixedSnapshot = plan(title: 'Original plan');
      final frozen = revision(number: 1, snapshot: fixedSnapshot);
      final changedPlan = fixedSnapshot.copyWith(title: 'Later plan');

      expect(frozen.snapshot.title, 'Original plan');
      expect(changedPlan.title, 'Later plan');
      expect(frozen.snapshot, isNot(same(changedPlan)));
    });

    test('rejects an attempt to write a fixed revision field', () {
      final frozen = revision(number: 1);

      expect(
        () => (frozen as dynamic).snapshot = plan(title: 'Replacement'),
        throwsA(isA<NoSuchMethodError>()),
      );
    });
  });
}
