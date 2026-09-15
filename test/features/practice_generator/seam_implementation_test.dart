import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/practice/public.dart'
    show PracticeDefinition, practiceCatalogProvider;
import 'package:strumsight/features/practice_generator/public.dart';

import '../../core/storage/in_memory_key_value_store.dart';

/// E17-R05 §6 (ADR 0524): the two production seams of the Practice
/// Generator composition root are IMPLEMENTED, and each works off a real
/// source — the shipped Practice Engine catalog (A2, §5.1) and the
/// persistent practice-evidence history (A3, §5.2). Every cell reads a
/// production-shape container: `keyValueStoreProvider` overridden with an
/// in-memory store exactly as `main.dart` injects the bootstrap store, and
/// NOTHING else — so a seam that still threw would be measured here (A1).
void main() {
  group('E17-R05 / A1 — both seams build on a production shape', () {
    test('exerciseCandidateResolverProvider returns a working resolver: '
        'every skill-tagged shipped definition resolves to a candidate '
        'carrying that definition\'s own id and skill tags', () {
      final container = _productionShape();

      final resolve = container.read(exerciseCandidateResolverProvider);
      final definitions = container.read(practiceCatalogProvider);

      expect(definitions, isNotEmpty);
      for (final definition in definitions.where(_isSkillTagged)) {
        final candidate = resolve(definition.id);
        expect(candidate.exerciseId, definition.id);
        expect(candidate.source, CandidateSource.practiceCatalog);
        expect(candidate.skillTargets, definition.skillTags);
        expect(candidate.offlineAvailable, isTrue);
      }
    });

    test('an exerciseId the shipped catalog does not contain is a '
        'controlled failure (StateError), never a substituted exercise', () {
      final container = _productionShape();

      final resolve = container.read(exerciseCandidateResolverProvider);

      expect(() => resolve('builtin.doesNotExist.v9'), throwsStateError);
    });

    test('generationPlanInputBuilderProvider returns a working builder: a '
        'Setup-wizard draft becomes a GenerationPlanInput whose catalog '
        'and scheduled exercises come from the shipped catalog', () {
      final container = _productionShape();
      final draft = _draft();
      final catalogIds = container
          .read(practiceCatalogProvider)
          .map((definition) => definition.id)
          .toSet();

      final buildInput = container.read(generationPlanInputBuilderProvider);
      final input = buildInput(draft);

      expect(identical(input.request, draft), isTrue);
      expect(input.validationContext.catalog.candidates, isNotEmpty);
      for (final candidate in input.validationContext.catalog.candidates) {
        expect(catalogIds, contains(candidate.exerciseId));
      }
      final catalogSortKeys = input.validationContext.catalog.candidates
          .map((candidate) => candidate.sortKey)
          .toSet();
      expect(input.schedule.dayDecisions, isNotEmpty);
      final scheduled = input.schedule.dayDecisions
          .expand((decision) => decision.selectedCandidates)
          .toList();
      expect(scheduled, isNotEmpty, reason: 'a 7-day draft schedules work');
      for (final candidate in scheduled) {
        expect(catalogSortKeys, contains(candidate.identity));
      }
      expect(
        input.validationContext.catalog.catalogRevision,
        container.read(practiceCatalogSnapshotProvider).catalogRevision,
      );
    });
  });

  group('E17-R05 / A2 — the resolver works off the ONE shipped catalog', () {
    test('an empty Practice catalog yields an empty candidate set and an '
        'unresolvable id — there is no second, generator-owned list', () {
      final container = _productionShape(
        overrides: [
          practiceCatalogProvider.overrideWithValue(
            const <PracticeDefinition>[],
          ),
        ],
      );

      final snapshot = container.read(practiceCatalogSnapshotProvider);
      final resolve = container.read(exerciseCandidateResolverProvider);

      expect(snapshot.candidates, isEmpty);
      expect(() => resolve('builtin.quarterDownstrokes.v1'), throwsStateError);
    });
  });

  group('E17-R05 / A3 — the plan input is built from REAL evidence', () {
    test('assembling a draft queries the persistent evidence repository for '
        'every skill the catalog can address (no constant history)', () {
      final store = InMemoryKeyValueStore();
      final spy = _SpyEvidenceRepository(
        LocalPracticeEvidenceRepository(keyValueStore: store),
      );
      final container = _productionShape(
        store: store,
        overrides: [practiceEvidenceRepositoryProvider.overrideWithValue(spy)],
      );
      final catalogSkills = container
          .read(practiceCatalogSnapshotProvider)
          .candidates
          .expand((candidate) => candidate.skillTargets)
          .toSet();

      container.read(generationPlanInputBuilderProvider)(_draft());

      expect(catalogSkills, isNotEmpty);
      expect(spy.queriedSkillIds.toSet(), containsAll(catalogSkills));
    });

    test('empty history is an explicit empty state: every skill estimate is '
        'unknown, and saving evidence through the composition root\'s '
        'repository changes that skill\'s ranking', () {
      final emptyHistory = _productionShape();
      final withHistory = _productionShape();
      withHistory
          .read(practiceEvidenceRepositoryProvider)
          .save(_evidence('downstrokes'), sourcePlanId: PlanId('plan.seam'));

      SkillPriority rank(ProviderContainer container) => container
          .read(generationPlanInputAssemblerProvider)
          .rankSkills(
            request: _draft(),
            catalog: container.read(practiceCatalogSnapshotProvider),
            asOf: _now,
          )
          .firstWhere((priority) => priority.skillId == 'downstrokes');

      final unknown = rank(emptyHistory);
      final known = rank(withHistory);

      expect(unknown.skillId, 'downstrokes');
      expect(unknown.score, isNot(equals(known.score)));
    });
  });

  test('end-to-end: startPlanGenerationProvider on the production-shape '
      'container activates a real plan, and activePracticePlanProvider reads '
      'it back through the production resolver', () async {
    final container = _productionShape();
    final subscription = container.listen(
      startPlanGenerationProvider,
      (previous, next) {},
    );
    addTearDown(subscription.close);
    final catalogIds = container
        .read(practiceCatalogProvider)
        .map((definition) => definition.id)
        .toSet();

    final result = await subscription.read()(_draft());

    expect(
      result,
      isA<Success<AdaptivePracticePlan>>(),
      reason: switch (result) {
        Failure<AdaptivePracticePlan>(:final error) =>
          'generation failed: $error',
        Success<AdaptivePracticePlan>() => null,
      },
    );
    final plan = (result as Success<AdaptivePracticePlan>).value;
    expect(plan.status, PlanStatus.active);

    container.invalidate(activePracticePlanProvider);
    final active = await container.read(activePracticePlanProvider.future);

    expect(active, isNotNull);
    expect(active!.id, plan.id);
    final exerciseIds = active.days
        .expand((day) => day.blocks)
        .map((block) => block.prescription.exerciseId)
        .toList();
    expect(exerciseIds, isNotEmpty);
    for (final exerciseId in exerciseIds) {
      expect(catalogIds, contains(exerciseId));
    }
  });
}

final DateTime _now = DateTime.utc(2026, 9, 14, 9);

ProviderContainer _productionShape({
  InMemoryKeyValueStore? store,
  List<Override> overrides = const <Override>[],
}) {
  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store ?? InMemoryKeyValueStore()),
      practiceGeneratorClockProvider.overrideWithValue(() => _now),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

bool _isSkillTagged(PracticeDefinition definition) =>
    definition.skillTags.isNotEmpty &&
    definition.skillTags.every((tag) => tag.trim().isNotEmpty);

LocalDate _dateAfter(int days) {
  final date = _now.add(Duration(days: days));
  return LocalDate(date.year, date.month, date.day);
}

/// A completed Setup-wizard draft: seven available days from "today", a
/// primary rhythm goal on a skill the shipped catalog targets.
PracticeGenerationRequest _draft() => PracticeGenerationRequest(
  id: GenerationRequestId('request.seam'),
  createdAt: _now,
  locale: 'en',
  generationMode: GenerationMode.starter,
  planHorizonDays: 7,
  availability: WeeklyAvailability(<DailyAvailability>[
    for (var offset = 0; offset < 7; offset++)
      DailyAvailability(
        date: _dateAfter(offset),
        status: AvailabilityStatus.available,
        minimumMinutes: 0,
        targetMinutes: 20,
        maximumMinutes: 30,
        maximumStrength: ConstraintStrength.hard,
      ),
  ]),
  constraints: LearnerConstraints(const <LearnerConstraint>[]),
  goals: <PracticeGoal>[
    PracticeGoal(
      id: GoalId('goal.seam'),
      type: PracticeGoalType.rhythm,
      priority: GoalPriority.primary,
      status: PracticeGoalStatus.active,
      createdAt: _now,
      skillIds: const <String>['downstrokes'],
    ),
  ],
);

SkillEvidence _evidence(String skillId) => SkillEvidence(
  skillId: skillId,
  source: EvidenceSource.learn,
  sourceOutcomeId: OutcomeId('outcome.seam.$skillId'),
  measurementVersion: 1,
  measuredAt: _now.subtract(const Duration(days: 1)),
  capturedAt: _now.subtract(const Duration(days: 1)),
  confidence: 0.9,
  performance: PerformanceEvidence(metricCode: 'seam.accuracy', value: 0.5),
);

/// Records which skills the assembler asked the REAL repository about.
final class _SpyEvidenceRepository implements PracticeEvidenceRepository {
  _SpyEvidenceRepository(this.inner);

  final PracticeEvidenceRepository inner;
  final List<String> queriedSkillIds = <String>[];

  @override
  void save(SkillEvidence evidence, {PlanId? sourcePlanId}) =>
      inner.save(evidence, sourcePlanId: sourcePlanId);

  @override
  SkillEvidence? findByOutcomeId(OutcomeId sourceOutcomeId) =>
      inner.findByOutcomeId(sourceOutcomeId);

  @override
  List<SkillEvidence> allForSkill(String skillId) => inner.allForSkill(skillId);

  @override
  List<SkillEvidence> query({
    required String skillId,
    required DateTime asOf,
    DateTime? measuredFrom,
    DateTime? measuredTo,
  }) {
    queriedSkillIds.add(skillId);
    return inner.query(
      skillId: skillId,
      asOf: asOf,
      measuredFrom: measuredFrom,
      measuredTo: measuredTo,
    );
  }

  @override
  int deleteForPlan(PlanId planId) => inner.deleteForPlan(planId);

  @override
  int deleteForOutcomes(PlanId planId, Set<OutcomeId> sourceOutcomeIds) =>
      inner.deleteForOutcomes(planId, sourceOutcomeIds);
}
