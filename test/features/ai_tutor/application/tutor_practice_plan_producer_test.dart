// R9 — the tutor's practice-plan producer.
//
// The measurement runs against the REAL builtin exercise catalog, not a
// fixture: the point of the producer is that every block it proposes names
// an exercise the shipped app can actually run, and a fixture catalog could
// not prove that.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/application/planning/tutor_practice_plan_producer.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/practice_plan_draft.dart';
import 'package:strumsight/features/ai_tutor/domain/services/practice_plan_validator.dart';
import 'package:strumsight/features/practice_generator/data/catalog/builtin_catalog_reader.dart';
import 'package:strumsight/features/practice_generator/public.dart'
    show
        AdaptivePracticePlan,
        ExerciseCandidate,
        PracticeCatalogSnapshot,
        PracticeItemStatus,
        PlanStatus;

const _producer = TutorPracticePlanProducer();

PracticeCatalogSnapshot _catalog() =>
    const BuiltinPracticeCatalogReader().read();

PracticeCatalogSnapshot _emptyCatalog() => PracticeCatalogSnapshot(
  catalogRevision: 'test-catalog',
  contentRevision: 'test-content',
  candidates: const <ExerciseCandidate>[],
);

TutorPracticePlanProposal _proposal({int minutes = 20}) {
  final result = _producer.propose(
    catalog: _catalog(),
    targetDuration: Duration(minutes: minutes),
    title: '$minutes-minute practice plan',
    rationale: 'Built from the on-device catalog.',
  );
  return result.valueOrNull!;
}

void main() {
  group('propose — a draft the preview screen can actually render', () {
    test('the produced blocks sum EXACTLY to the requested length', () {
      final draft = _proposal(minutes: 20).draft;

      final total = draft.blocks.fold(
        Duration.zero,
        (sum, block) => sum + block.duration,
      );
      expect(total, const Duration(minutes: 20));
      expect(draft.targetDuration, const Duration(minutes: 20));
    });

    test('every block names a real catalog exercise', () {
      final catalogIds = <String>{
        for (final candidate in _catalog().candidates) candidate.exerciseId,
      };
      final draft = _proposal().draft;

      expect(draft.blocks, isNotEmpty);
      for (final block in draft.blocks) {
        expect(block.adapter, PracticePlanBlockAdapter.practiceTarget);
        expect(catalogIds, contains(block.practiceTargetId));
      }
    });

    test('the produced draft is VALID against the context it ships with', () {
      final proposal = _proposal();

      const validator = PracticePlanValidator();
      final result = validator.validate(
        proposal.draft,
        context: proposal.validationContext,
      );

      expect(result.codes, isEmpty, reason: result.codes.join(', '));
      expect(result.isValid, isTrue);
    });

    test('a short plan is split into fewer, still whole-minute blocks', () {
      final draft = _proposal(minutes: 2).draft;

      expect(draft.blocks, hasLength(2));
      for (final block in draft.blocks) {
        expect(block.duration, const Duration(minutes: 1));
      }
    });

    test('an empty catalog is a typed failure, never an empty plan', () {
      final result = _producer.propose(
        catalog: _emptyCatalog(),
        targetDuration: const Duration(minutes: 20),
        title: 'title',
        rationale: 'rationale',
      );

      expect(result, isA<Failure<TutorPracticePlanProposal>>());
      expect(result.failureOrNull?.code, tutorPlanCatalogEmptyCode);
    });

    test('a sub-minute length is refused instead of rounded away', () {
      final result = _producer.propose(
        catalog: _catalog(),
        targetDuration: const Duration(seconds: 30),
        title: 'title',
        rationale: 'rationale',
      );

      expect(result.failureOrNull?.code, tutorPlanDurationTooShortCode);
    });
  });

  group('compileActivePlan — the accepted draft becomes a real plan', () {
    test('compiles one planned day whose blocks mirror the draft', () {
      final draft = _proposal().draft;

      final compiled = _producer.compileActivePlan(
        draft: draft,
        catalog: _catalog(),
        now: DateTime.utc(2026, 9, 7, 10),
      );

      expect(compiled, isA<Success<AdaptivePracticePlan>>());
      final plan = compiled.valueOrNull!;
      expect(plan.status, PlanStatus.active);
      expect(plan.days, hasLength(1));
      expect(plan.days.single.blocks, hasLength(draft.blocks.length));
      expect(plan.days.single.status, PracticeItemStatus.planned);
      expect(plan.days.single.timeBudget, draft.targetDuration);
      expect(plan.title, draft.title);
      final exerciseIds = plan.days.single.blocks
          .map((block) => block.prescription.exerciseId)
          .toList();
      expect(
        exerciseIds,
        draft.blocks.map((block) => block.practiceTargetId).toList(),
      );
    });

    test('every compiled block is bounded and positively sized', () {
      final compiled = _producer.compileActivePlan(
        draft: _proposal().draft,
        catalog: _catalog(),
        now: DateTime.utc(2026, 9, 7, 10),
      );
      final plan = compiled.valueOrNull!;

      for (final block in plan.days.single.blocks) {
        expect(block.estimatedElapsed, greaterThan(Duration.zero));
        expect(block.prescription.loopCount, greaterThanOrEqualTo(1));
        expect(
          block.prescription.hardElapsedLimit,
          greaterThanOrEqualTo(block.prescription.activeDuration),
        );
      }
    });

    test('the revision id is content-derived: stable for the same draft, '
        'different once a duration is edited', () {
      final draft = _proposal().draft;
      final first = _producer.compileActivePlan(
        draft: draft,
        catalog: _catalog(),
        now: DateTime.utc(2026, 9, 7, 10),
      );
      final again = _producer.compileActivePlan(
        draft: draft,
        catalog: _catalog(),
        now: DateTime.utc(2026, 9, 7, 11),
      );

      expect(
        again.valueOrNull!.activeRevisionId,
        first.valueOrNull!.activeRevisionId,
        reason: 'an unchanged accepted draft must not spawn a new revision',
      );

      final edited = _editFirstBlockMinutes(draft, 1);
      final third = _producer.compileActivePlan(
        draft: edited,
        catalog: _catalog(),
        now: DateTime.utc(2026, 9, 7, 12),
      );

      expect(
        third.valueOrNull!.activeRevisionId,
        isNot(first.valueOrNull!.activeRevisionId),
        reason:
            'an edited plan MUST get a new revision id — otherwise the '
            'repository treats activation as a structural no-op and the '
            "student's edit is silently dropped",
      );
    });

    test('a block naming an exercise the catalog no longer has is refused, '
        'never silently substituted', () {
      final draft = _proposal().draft;
      final stale = draft.copyWith(
        blocks: <PracticePlanBlock>[
          PracticePlanBlock.practiceTarget(
            id: 'tutor.plan.block.0',
            type: PracticePlanBlockType.rhythm,
            duration: const Duration(minutes: 5),
            practiceTargetId: 'builtin.removedExercise.v1',
          ),
        ],
      );

      final compiled = _producer.compileActivePlan(
        draft: stale,
        catalog: _catalog(),
        now: DateTime.utc(2026, 9, 7, 10),
      );

      expect(compiled.failureOrNull?.code, tutorPlanExerciseMissingCode);
    });
  });
}

PracticePlanDraft _editFirstBlockMinutes(PracticePlanDraft draft, int delta) {
  final blocks = List<PracticePlanBlock>.from(draft.blocks);
  final first = blocks.first;
  blocks[0] = first.copyWith(
    duration: first.duration + Duration(minutes: delta),
  );
  return draft.copyWith(blocks: blocks);
}
