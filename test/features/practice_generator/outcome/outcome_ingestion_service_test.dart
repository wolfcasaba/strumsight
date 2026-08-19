import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  final today = LocalDate(2026, 8, 19);
  final reviewItem = ReviewItem(
    target: ReviewTarget(
      kind: ReviewTargetKind.lesson,
      targetId: 'lesson.rhythm-basics',
    ),
    currentInterval: const Duration(days: 7),
    dueDate: LocalDate(2026, 8, 26),
  );

  PracticeOutcome outcome({
    String revisionId = 'revision.active',
    String outcomeId = 'outcome.1',
    PracticeCompletionState state = PracticeCompletionState.completed,
  }) => PracticeOutcome(
    id: OutcomeId(outcomeId),
    planId: PlanId('plan.1'),
    revisionId: RevisionId(revisionId),
    dayId: DayId('day.1'),
    blockId: BlockId('block.1'),
    source: PracticeOutcomeSource.practiceEngine,
    startedAt: DateTime.utc(2026, 8, 19, 10),
    completedAt: DateTime.utc(2026, 8, 19, 10, 5),
    activeDuration: const Duration(minutes: 5),
    completionState: state,
    metricEvidence: const <String, double>{'overall': .9},
    userFeedback: const <PracticeUserFeedback>[],
  );

  group('OutcomeIngestionService', () {
    test('A3: processes a duplicate outcome only once', () {
      final service = OutcomeIngestionService();
      final first = service.ingest(
        outcome: outcome(),
        activeRevisionId: RevisionId('revision.active'),
        processedOutcomeIds: const <String>{},
        reviewItems: <ReviewItem>[reviewItem],
        today: today,
      );
      final replay = service.ingest(
        outcome: outcome(),
        activeRevisionId: RevisionId('revision.active'),
        processedOutcomeIds: const <String>{'outcome.1'},
        reviewItems: <ReviewItem>[reviewItem],
        today: today,
      );

      expect(first.status, OutcomeIngestionStatus.processed);
      expect(first.reviewItems.single.currentInterval.inDays, 14);
      expect(replay.status, OutcomeIngestionStatus.duplicate);
      expect(replay.reviewItems, <ReviewItem>[reviewItem]);
    });

    test('A6: controls an outcome for a non-active revision', () {
      final result = OutcomeIngestionService().ingest(
        outcome: outcome(revisionId: 'revision.old'),
        activeRevisionId: RevisionId('revision.active'),
        processedOutcomeIds: const <String>{},
        reviewItems: <ReviewItem>[reviewItem],
        today: today,
      );

      expect(result.status, OutcomeIngestionStatus.staleRevision);
      expect(result.reviewItems, <ReviewItem>[reviewItem]);
    });

    test(
      'A7: a technical failure updates no review item and is not adaptable',
      () {
        final result = OutcomeIngestionService().ingest(
          outcome: outcome(state: PracticeCompletionState.failedTechnical),
          activeRevisionId: RevisionId('revision.active'),
          processedOutcomeIds: const <String>{},
          reviewItems: <ReviewItem>[reviewItem],
          today: today,
        );

        expect(result.status, OutcomeIngestionStatus.processed);
        expect(result.reviewItems, <ReviewItem>[reviewItem]);
        expect(result.canAdapt, isFalse);
      },
    );
  });
}
