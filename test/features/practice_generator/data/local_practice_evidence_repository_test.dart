import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
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

    test(
      'B1: a failing physical remove does not silently succeed — the '
      'failure is observable via lastWriteFailure, and the record stays '
      'recoverable (never an undeletable residue) once the store recovers',
      () async {
        final store = InMemoryKeyValueStore();
        final repository = LocalPracticeEvidenceRepository(
          keyValueStore: store,
        );
        final evidence = _evidence(outcomeId: 'outcome.residue');
        repository.save(evidence, sourcePlanId: PlanId('plan.1'));
        await repository.flush();

        const recordKey =
            'ss.practice_generator.evidence.record.outcome.residue';
        expect(store.values.containsKey(recordKey), isTrue);
        store.failingKeys.add(recordKey);

        final removed = repository.deleteForPlan(PlanId('plan.1'));
        expect(removed, 1);
        await repository.flush();

        expect(repository.lastWriteFailure, isA<StorageException>());
        // The physical record is still on disk — the remove really failed.
        expect(store.values.containsKey(recordKey), isTrue);

        // Recovery proof (falsifies the review's "residue undeletable
        // forever" finding): a FRESH instance opened on the same store
        // must still see — and therefore still be able to delete — the
        // record. The manifest was never rewritten to drop an id whose
        // physical removal never confirmed.
        final reader = LocalPracticeEvidenceRepository(keyValueStore: store);
        expect(reader.findByOutcomeId(evidence.sourceOutcomeId), evidence);

        store.failingKeys.remove(recordKey);
        final retryRemoved = reader.deleteForPlan(PlanId('plan.1'));
        await reader.flush();

        expect(retryRemoved, 1);
        expect(store.values.containsKey(recordKey), isFalse);
      },
    );

    test('M1: a record with a corrupt evidence body still hydrates its '
        'owner, so deleteForPlan can remove the orphaned key instead of it '
        'staying permanently un-owned', () {
      final store = InMemoryKeyValueStore({
        LocalPracticeEvidenceRepository.manifestKey: jsonEncode(<String>[
          'outcome.corrupt',
        ]),
        'ss.practice_generator.evidence.record.outcome.corrupt': jsonEncode(
          <String, Object?>{'evidence': 'NOT-A-MAP', 'sourcePlanId': 'plan.1'},
        ),
      });

      final repository = LocalPracticeEvidenceRepository(keyValueStore: store);

      expect(repository.findByOutcomeId(OutcomeId('outcome.corrupt')), isNull);
      final removed = repository.deleteForPlan(PlanId('plan.1'));

      expect(removed, 1);
    });

    test('R3 (open limitation): an UNPARSEABLE envelope — not a corrupt '
        'evidence body, the whole record string is not valid JSON — has no '
        'sourcePlanId to read at all, so it stays immune to deleteForPlan '
        "even though its outcome id remains in the manifest (it's never a "
        'silent leak, just an unresolvable owner — documented in round-brief '
        '§10, deferred to an ADR before any auto-tombstone behaviour is '
        'added)', () {
      final store = InMemoryKeyValueStore({
        LocalPracticeEvidenceRepository.manifestKey: jsonEncode(<String>[
          'outcome.unparseable',
        ]),
        'ss.practice_generator.evidence.record.outcome.unparseable':
            'NOT-JSON-AT-ALL{{{',
      });

      final repository = LocalPracticeEvidenceRepository(keyValueStore: store);

      expect(
        repository.findByOutcomeId(OutcomeId('outcome.unparseable')),
        isNull,
      );
      final removed = repository.deleteForPlan(PlanId('plan.1'));

      expect(removed, 0);
      expect(
        store.values.containsKey(
          'ss.practice_generator.evidence.record.outcome.unparseable',
        ),
        isTrue,
      );
    });

    test(
      "M2: a stale instance's save does not resurrect an id a NEWER "
      'instance already deleted — the manifest write re-reads disk '
      "instead of overwriting it with the stale instance's own list",
      () async {
        final store = InMemoryKeyValueStore();
        final writer = LocalPracticeEvidenceRepository(keyValueStore: store);
        final a = _evidence(outcomeId: 'outcome.a');
        final b = _evidence(outcomeId: 'outcome.b');
        writer.save(a, sourcePlanId: PlanId('plan.1'));
        writer.save(b, sourcePlanId: PlanId('plan.1'));
        await writer.flush();

        // A second, "stale" instance opened on the same store BEFORE `a`
        // is deleted — it hydrates both `a` and `b` into its own
        // in-memory view.
        final stale = LocalPracticeEvidenceRepository(keyValueStore: store);

        writer.deleteForOutcomes(PlanId('plan.1'), {a.sourceOutcomeId});
        await writer.flush();

        // `stale` now saves a brand-new evidence `c`. Its own in-memory
        // outcome-id list still (wrongly) includes `a`, since it
        // hydrated before the delete — the manifest write this triggers
        // must not resurrect `a`.
        final c = _evidence(outcomeId: 'outcome.c');
        stale.save(c, sourcePlanId: PlanId('plan.1'));
        await stale.flush();

        final rawManifest =
            store.values[LocalPracticeEvidenceRepository.manifestKey] as String;
        final manifestIds = (jsonDecode(rawManifest) as List).cast<String>();
        expect(manifestIds, isNot(contains('outcome.a')));
        expect(manifestIds, containsAll(<String>['outcome.b', 'outcome.c']));

        final fresh = LocalPracticeEvidenceRepository(keyValueStore: store);
        expect(fresh.findByOutcomeId(a.sourceOutcomeId), isNull);
        expect(fresh.findByOutcomeId(b.sourceOutcomeId), b);
        expect(fresh.findByOutcomeId(c.sourceOutcomeId), c);
      },
    );

    test(
      "R2: a stale instance's RE-SAVE of an outcome another instance already "
      'deleted still lands in the manifest — never a physical record with '
      'no manifest entry pointing at it (permanently invisible AND '
      'undeletable)',
      () async {
        final store = InMemoryKeyValueStore();
        final writer = LocalPracticeEvidenceRepository(keyValueStore: store);
        final evidence = _evidence(outcomeId: 'outcome.stale-resave');
        writer.save(evidence, sourcePlanId: PlanId('plan.1'));
        await writer.flush();

        // A second instance hydrates the same outcome id into its own
        // `_outcomeIds`, then deletes it — the manifest on disk drops it,
        // but `writer`'s local cache still (staleness) lists it.
        final second = LocalPracticeEvidenceRepository(keyValueStore: store);
        final removed = second.deleteForPlan(PlanId('plan.1'));
        await second.flush();
        expect(removed, 1);

        // `writer` now re-saves the SAME outcome id. Its local
        // `_outcomeIds` still contains it, so a naive `isNew` check would
        // skip the manifest write entirely.
        writer.save(evidence, sourcePlanId: PlanId('plan.1'));
        await writer.flush();

        const recordKey =
            'ss.practice_generator.evidence.record.outcome'
            '.stale-resave';
        expect(store.values.containsKey(recordKey), isTrue);

        // The falsifiable proof: a BRAND NEW instance must be able to
        // discover — and therefore delete — the re-saved record.
        final third = LocalPracticeEvidenceRepository(keyValueStore: store);
        expect(third.findByOutcomeId(evidence.sourceOutcomeId), evidence);

        final secondRemoved = third.deleteForPlan(PlanId('plan.1'));
        await third.flush();
        expect(secondRemoved, 1);
        expect(store.values.containsKey(recordKey), isFalse);
      },
    );

    test('MINOR-1: a discomfort-only evidence WITH a validUntil round-trips '
        'through a FRESH instance (that branch was never exercised past '
        'the same-process cache before)', () {
      final store = InMemoryKeyValueStore();
      final writer = LocalPracticeEvidenceRepository(keyValueStore: store);
      final evidence = SkillEvidence(
        skillId: 'chord.gMajor',
        source: EvidenceSource.selfReport,
        sourceOutcomeId: OutcomeId('outcome.discomfort'),
        measurementVersion: 1,
        measuredAt: DateTime.utc(2026, 8, 20),
        capturedAt: DateTime.utc(2026, 8, 20),
        confidence: 0.5,
        validUntil: DateTime.utc(2026, 9, 20),
        discomfort: DiscomfortReport(category: DiscomfortCategory.tension),
      );
      writer.save(evidence, sourcePlanId: PlanId('plan.1'));

      final reader = LocalPracticeEvidenceRepository(keyValueStore: store);

      expect(reader.findByOutcomeId(evidence.sourceOutcomeId), evidence);
    });

    test('MINOR-6: outcomePlanLookup is an ownership fallback for records '
        'saved without a sourcePlanId, mirroring the in-memory fake', () {
      final store = InMemoryKeyValueStore();
      final repository = LocalPracticeEvidenceRepository(
        keyValueStore: store,
        outcomePlanLookup: (outcomeId) =>
            outcomeId == 'outcome.legacy' ? PlanId('plan.1') : null,
      );
      final evidence = _evidence(outcomeId: 'outcome.legacy');
      repository.save(evidence);

      final removed = repository.deleteForPlan(PlanId('plan.1'));

      expect(removed, 1);
      expect(repository.findByOutcomeId(evidence.sourceOutcomeId), isNull);
    });
  });
}
