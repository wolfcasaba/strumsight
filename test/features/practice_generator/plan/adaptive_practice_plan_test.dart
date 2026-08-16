import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

import '../../../fixtures/practice_generator/plan/plan_fixtures.dart';

void main() {
  group('Practice item status transitions', () {
    final legalTargets = <PracticeItemStatus, PracticeItemStatus>{
      PracticeItemStatus.planned: PracticeItemStatus.ready,
      PracticeItemStatus.ready: PracticeItemStatus.inProgress,
      PracticeItemStatus.inProgress: PracticeItemStatus.completed,
    };
    final forbiddenTargets = <PracticeItemStatus, PracticeItemStatus>{
      PracticeItemStatus.planned: PracticeItemStatus.completed,
      PracticeItemStatus.ready: PracticeItemStatus.planned,
      PracticeItemStatus.inProgress: PracticeItemStatus.ready,
      PracticeItemStatus.completed: PracticeItemStatus.planned,
      PracticeItemStatus.skipped: PracticeItemStatus.ready,
      PracticeItemStatus.substituted: PracticeItemStatus.ready,
      PracticeItemStatus.unavailable: PracticeItemStatus.ready,
      PracticeItemStatus.expired: PracticeItemStatus.ready,
    };

    for (final status in PracticeItemStatus.values) {
      test(
        'block $status permits its pinned legal transition when present',
        () {
          final target = legalTargets[status];
          final value = block(status: status);

          if (target == null) {
            expect(value.canTransitionTo(PracticeItemStatus.ready), isFalse);
          } else {
            expect(value.canTransitionTo(target), isTrue);
            expect(value.transitionTo(target).status, target);
          }
        },
      );

      test('block $status rejects a pinned forbidden transition', () {
        final value = block(status: status);

        expect(
          () => value.transitionTo(forbiddenTargets[status]!),
          throwsStateError,
        );
      });

      test('day $status permits its pinned legal transition when present', () {
        final target = legalTargets[status];
        final value = day(status: status);

        if (target == null) {
          expect(value.canTransitionTo(PracticeItemStatus.ready), isFalse);
        } else {
          expect(value.canTransitionTo(target), isTrue);
          expect(value.transitionTo(target).status, target);
        }
      });

      test('day $status rejects a pinned forbidden transition', () {
        final value = day(status: status);

        expect(
          () => value.transitionTo(forbiddenTargets[status]!),
          throwsStateError,
        );
      });
    }
  });

  test('rejects silently replacing a completed block', () {
    final completed = block(status: PracticeItemStatus.completed);

    expect(
      () => completed.replaceContent(
        estimatedElapsed: const Duration(minutes: 8),
      ),
      throwsStateError,
    );
  });

  test(
    'round-trips a versioned plan without leaking the goal user note summary',
    () {
      final original = plan();
      final decoded = AdaptivePracticePlan.fromJson(
        original.toJson(),
        resolveCandidate: resolveCandidate,
      );

      expect(decoded, original);
      expect(original.schemaVersion, 1);
      expect(
        original.toSummary().toJson().toString(),
        isNot(contains('private note')),
      );
    },
  );
}
