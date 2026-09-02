import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/data/local/local_practice_evidence_repository.dart';
import 'package:strumsight/features/practice_generator/domain/id/planner_ids.dart';
import 'package:strumsight/features/practice_generator/domain/model/skill_evidence.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

/// E15-R14 §6/A1, A2: the first PERSISTENT [PracticeEvidenceRepository]
/// implementation. The round-trip cells below are the falsifiable proof
/// that a delete really deletes — not just from the instance that issued
/// it, but from the underlying store, so a fresh instance opened on the
/// same store can never read the removed record back (ADR 0482 / D2).
SkillEvidence _evidence({
  String outcomeId = 'outcome.1',
  String skillId = 'chord.gMajor',
  double confidence = 0.8,
  DateTime? measuredAt,
  DateTime? validUntil,
}) => SkillEvidence(
  skillId: skillId,
  source: EvidenceSource.learn,
  sourceOutcomeId: OutcomeId(outcomeId),
  measurementVersion: 1,
  measuredAt: measuredAt ?? DateTime.utc(2026, 8, 20),
  capturedAt: measuredAt ?? DateTime.utc(2026, 8, 20),
  confidence: confidence,
  validUntil: validUntil,
  performance: PerformanceEvidence(
    metricCode: 'chordChangeAccuracy',
    value: 0.75,
  ),
);

void main() {
  group('LocalPracticeEvidenceRepository', () {
    test('findByOutcomeId returns null for an unknown outcome id', () {
      final repository = LocalPracticeEvidenceRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );

      expect(repository.findByOutcomeId(OutcomeId('missing')), isNull);
    });

    test('A1: a saved evidence round-trips within the same instance', () {
      final repository = LocalPracticeEvidenceRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );
      final evidence = _evidence();

      repository.save(evidence, sourcePlanId: PlanId('plan.1'));

      expect(repository.findByOutcomeId(evidence.sourceOutcomeId), evidence);
      expect(repository.allForSkill('chord.gMajor'), <SkillEvidence>[evidence]);
    });

    test(
      'evidence saved by one instance is readable from a FRESH instance '
      'opened on the same store (persistence, not just an in-memory cache)',
      () {
        final store = InMemoryKeyValueStore();
        final writer = LocalPracticeEvidenceRepository(keyValueStore: store);
        final evidence = _evidence();
        writer.save(evidence, sourcePlanId: PlanId('plan.1'));

        final reader = LocalPracticeEvidenceRepository(keyValueStore: store);

        expect(reader.findByOutcomeId(evidence.sourceOutcomeId), evidence);
      },
    );

    test('A2: deleteForPlan removes the record so that a FRESH instance over '
        'the same store can never read it back', () {
      final store = InMemoryKeyValueStore();
      final writer = LocalPracticeEvidenceRepository(keyValueStore: store);
      final kept = _evidence(outcomeId: 'outcome.kept');
      final deleted = _evidence(outcomeId: 'outcome.deleted');
      writer.save(kept, sourcePlanId: PlanId('plan.other'));
      writer.save(deleted, sourcePlanId: PlanId('plan.target'));

      final removed = writer.deleteForPlan(PlanId('plan.target'));

      expect(removed, 1);
      // Same-instance visibility (obvious for any implementation).
      expect(writer.findByOutcomeId(deleted.sourceOutcomeId), isNull);

      // The falsifiable proof (§6.1): a BRAND NEW repository instance
      // opened on the very same store must not be able to read the
      // deleted record back — persistence, not an in-memory illusion.
      final reader = LocalPracticeEvidenceRepository(keyValueStore: store);
      expect(reader.findByOutcomeId(deleted.sourceOutcomeId), isNull);
      // The untouched sibling survives — deletion is plan-scoped, not
      // a wholesale wipe.
      expect(reader.findByOutcomeId(kept.sourceOutcomeId), kept);
    });

    test('evidence saved without a sourcePlanId has unknown ownership and is '
        'immune to deleteForPlan (absence of ownership is a refusal, not a '
        'wildcard)', () {
      final store = InMemoryKeyValueStore();
      final repository = LocalPracticeEvidenceRepository(keyValueStore: store);
      final unowned = _evidence(outcomeId: 'outcome.unowned');
      repository.save(unowned);

      final removed = repository.deleteForPlan(PlanId('plan.anything'));

      expect(removed, 0);
      expect(repository.findByOutcomeId(unowned.sourceOutcomeId), unowned);
    });

    test('deleteForOutcomes removes exactly the given, owned outcome ids', () {
      final store = InMemoryKeyValueStore();
      final repository = LocalPracticeEvidenceRepository(keyValueStore: store);
      final a = _evidence(outcomeId: 'outcome.a');
      final b = _evidence(outcomeId: 'outcome.b');
      final c = _evidence(outcomeId: 'outcome.c');
      repository.save(a, sourcePlanId: PlanId('plan.1'));
      repository.save(b, sourcePlanId: PlanId('plan.1'));
      repository.save(c, sourcePlanId: PlanId('plan.2'));

      final removed = repository.deleteForOutcomes(PlanId('plan.1'), {
        a.sourceOutcomeId,
        c.sourceOutcomeId, // owned by a different plan — must be refused.
      });

      expect(removed, 1);
      expect(repository.findByOutcomeId(a.sourceOutcomeId), isNull);
      expect(repository.findByOutcomeId(b.sourceOutcomeId), b);
      expect(repository.findByOutcomeId(c.sourceOutcomeId), c);
    });

    test('query filters by skillId and validity at asOf', () {
      final repository = LocalPracticeEvidenceRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );
      final fresh = _evidence(
        outcomeId: 'outcome.fresh',
        measuredAt: DateTime.utc(2026, 8, 1),
        validUntil: DateTime.utc(2026, 9, 1),
      );
      final expired = _evidence(
        outcomeId: 'outcome.expired',
        measuredAt: DateTime.utc(2026, 1, 1),
        validUntil: DateTime.utc(2026, 2, 1),
      );
      final otherSkill = _evidence(
        outcomeId: 'outcome.other',
        skillId: 'chord.dMajor',
        measuredAt: DateTime.utc(2026, 8, 1),
      );
      repository.save(fresh);
      repository.save(expired);
      repository.save(otherSkill);

      final result = repository.query(
        skillId: 'chord.gMajor',
        asOf: DateTime.utc(2026, 8, 15),
      );

      expect(result, <SkillEvidence>[fresh]);
    });

    test(
      'saving overwrites any prior evidence sharing the same sourceOutcomeId',
      () {
        final store = InMemoryKeyValueStore();
        final repository = LocalPracticeEvidenceRepository(
          keyValueStore: store,
        );
        final first = _evidence(confidence: 0.4);
        final second = _evidence(confidence: 0.9);
        repository.save(first, sourcePlanId: PlanId('plan.1'));
        repository.save(second, sourcePlanId: PlanId('plan.1'));

        final reader = LocalPracticeEvidenceRepository(keyValueStore: store);

        expect(reader.findByOutcomeId(second.sourceOutcomeId), second);
        expect(reader.allForSkill('chord.gMajor'), <SkillEvidence>[second]);
      },
    );

    test('re-saving without a sourcePlanId clears any previously recorded '
        'ownership', () {
      final repository = LocalPracticeEvidenceRepository(
        keyValueStore: InMemoryKeyValueStore(),
      );
      final evidence = _evidence();
      repository.save(evidence, sourcePlanId: PlanId('plan.1'));
      repository.save(evidence);

      expect(repository.deleteForPlan(PlanId('plan.1')), 0);
      expect(repository.findByOutcomeId(evidence.sourceOutcomeId), evidence);
    });

    test('A5/D3: every key this repository writes lives in its own '
        'namespace, never the plan or draft namespace', () {
      final store = InMemoryKeyValueStore();
      final repository = LocalPracticeEvidenceRepository(keyValueStore: store);

      repository.save(_evidence(), sourcePlanId: PlanId('plan.1'));

      expect(store.values.keys, isNotEmpty);
      for (final key in store.values.keys) {
        expect(key, startsWith('ss.practice_generator.evidence'));
        expect(key, isNot(startsWith('ss.practice_generator.plan')));
        expect(key, isNot('ss.practice_generator.generation_draft'));
      }
    });

    test(
      'a corrupt manifest is treated as empty — construction never throws',
      () {
        final store = InMemoryKeyValueStore({
          LocalPracticeEvidenceRepository.manifestKey: 'not-json-at-all{{{',
        });

        final repository = LocalPracticeEvidenceRepository(
          keyValueStore: store,
        );

        expect(repository.findByOutcomeId(OutcomeId('anything')), isNull);
      },
    );
  });
}
