import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/features/progress/public.dart';

void main() {
  const mappingTable = LegacyMappingTable(
    version: 2,
    entries: <LegacySkillMapping>[
      LegacySkillMapping(lessonId: 'unused-here', skillIds: <String>['x']),
    ],
  );

  const entry = PracticeEntry(
    day: 19945,
    source: PracticeSource.learn,
    seconds: 420,
    strokes: 128,
    chords: 6,
    directionAccuracy: 0.82,
  );

  LegacyProgressOutcome outcomeFor({
    String? skillId = 'chord.gMajor',
    String? outcomeId = 'progress-outcome-1',
    double? normalizedPerformance = 0.82,
  }) => LegacyProgressOutcome(
    entry: entry,
    measuredAt: DateTime.utc(2026, 8, 10),
    capturedAt: DateTime.utc(2026, 8, 15),
    skillId: skillId,
    sourceOutcomeId: outcomeId == null ? null : OutcomeId(outcomeId),
    normalizedPerformance: normalizedPerformance,
  );

  group('LegacyProgressEvidenceAdapter — happy path (§6.1: "van mapping")', () {
    test('a fully-attested outcome produces legacy-sourced evidence', () {
      final adapter = LegacyProgressEvidenceAdapter(mappingTable: mappingTable);

      final result = adapter.readEvidence(<LegacyProgressOutcome>[
        outcomeFor(),
      ]);

      expect(result.warnings, isEmpty);
      expect(result.evidence, hasLength(1));
      final evidence = result.evidence.single;
      expect(evidence.skillId, 'chord.gMajor');
      expect(evidence.source, EvidenceSource.progress);
      expect(evidence.performance!.value, 0.82);
    });
  });

  group('LegacyProgressEvidenceAdapter — provenance (A3, A4)', () {
    test(
      'the evidence measurementVersion is the mapping table version (A3)',
      () {
        final adapter = LegacyProgressEvidenceAdapter(
          mappingTable: mappingTable,
        );

        final result = adapter.readEvidence(<LegacyProgressOutcome>[
          outcomeFor(),
        ]);

        expect(result.evidence.single.measurementVersion, 2);
      },
    );

    test(
      'the evidence source is marked legacy progress, not a live source (A4)',
      () {
        final adapter = LegacyProgressEvidenceAdapter(
          mappingTable: mappingTable,
        );

        final result = adapter.readEvidence(<LegacyProgressOutcome>[
          outcomeFor(),
        ]);

        expect(result.evidence.single.source, EvidenceSource.progress);
        expect(result.evidence.single.source, isNot(EvidenceSource.analyzeV2));
      },
    );
  });

  group('LegacyProgressEvidenceAdapter — determinism and dedup (A5, A6)', () {
    test(
      'the same input yields the same evidence regardless of order (A5)',
      () {
        final adapter = LegacyProgressEvidenceAdapter(
          mappingTable: mappingTable,
        );
        final a = outcomeFor(outcomeId: 'order-a', skillId: 'chord.gMajor');
        final b = outcomeFor(outcomeId: 'order-b', skillId: 'chord.cMajor');

        final forward = adapter.readEvidence(<LegacyProgressOutcome>[a, b]);
        final reversed = adapter.readEvidence(<LegacyProgressOutcome>[b, a]);

        final forwardBySkill = {for (final e in forward.evidence) e.skillId: e};
        final reversedBySkill = {
          for (final e in reversed.evidence) e.skillId: e,
        };

        expect(forward.evidence, hasLength(2));
        expect(reversed.evidence, hasLength(2));
        expect(forwardBySkill.keys, reversedBySkill.keys);
        for (final skillId in forwardBySkill.keys) {
          expect(
            forwardBySkill[skillId]!.sourceOutcomeId,
            reversedBySkill[skillId]!.sourceOutcomeId,
          );
        }
      },
    );

    test(
      'a duplicated source outcome id is ingested once, not per replay (A6)',
      () {
        final adapter = LegacyProgressEvidenceAdapter(
          mappingTable: mappingTable,
        );
        final duplicate = outcomeFor(outcomeId: 'dup-progress-1');

        final result = adapter.readEvidence(<LegacyProgressOutcome>[
          duplicate,
          duplicate,
          duplicate,
        ]);

        expect(result.evidence, hasLength(1));
      },
    );

    test('dedup is keyed on the outcome id, not on measuredAt (A6)', () {
      final adapter = LegacyProgressEvidenceAdapter(mappingTable: mappingTable);
      final first = outcomeFor(outcomeId: 'dup-progress-2');
      final second = LegacyProgressOutcome(
        entry: entry,
        measuredAt: DateTime.utc(2020, 1, 1), // different timestamp
        capturedAt: DateTime.utc(2026, 8, 15),
        skillId: 'chord.gMajor',
        sourceOutcomeId: OutcomeId('dup-progress-2'),
        normalizedPerformance: 0.82,
      );

      final result = adapter.readEvidence(<LegacyProgressOutcome>[
        first,
        second,
      ]);

      expect(result.evidence, hasLength(1));
    });
  });

  group(
    'LegacyProgressEvidenceAdapter — missing identity never fabricated (A8)',
    () {
      test(
        'a record with no sourceOutcomeId produces no evidence, no exception',
        () {
          final adapter = LegacyProgressEvidenceAdapter(
            mappingTable: mappingTable,
          );

          Object? thrown;
          late final SkillSnapshotResult result;
          try {
            result = adapter.readEvidence(<LegacyProgressOutcome>[
              outcomeFor(outcomeId: null),
            ]);
          } catch (e) {
            thrown = e;
          }

          expect(thrown, isNull);
          expect(result.evidence, isEmpty);
          expect(result.warnings.single.code, 'missingOutcomeId');
        },
      );

      test(
        'a record with no skill link produces no evidence, no exception',
        () {
          final adapter = LegacyProgressEvidenceAdapter(
            mappingTable: mappingTable,
          );

          final result = adapter.readEvidence(<LegacyProgressOutcome>[
            outcomeFor(skillId: null),
          ]);

          expect(result.evidence, isEmpty);
          expect(result.warnings.single.code, 'missingSkillId');
        },
      );

      test(
        'a record with no explicit normalized performance produces no evidence',
        () {
          final adapter = LegacyProgressEvidenceAdapter(
            mappingTable: mappingTable,
          );

          final result = adapter.readEvidence(<LegacyProgressOutcome>[
            outcomeFor(normalizedPerformance: null),
          ]);

          expect(result.evidence, isEmpty);
          expect(result.warnings.single.code, 'missingNormalizedPerformance');
        },
      );

      test(
        'an out-of-range normalized performance is rejected, not clamped or thrown (A8 boundary)',
        () {
          final adapter = LegacyProgressEvidenceAdapter(
            mappingTable: mappingTable,
          );

          Object? thrown;
          late final SkillSnapshotResult result;
          try {
            result = adapter.readEvidence(<LegacyProgressOutcome>[
              outcomeFor(normalizedPerformance: 1.4),
            ]);
          } catch (e) {
            thrown = e;
          }

          expect(thrown, isNull);
          expect(result.evidence, isEmpty);
          expect(result.warnings.single.code, 'missingNormalizedPerformance');
        },
      );

      test(
        'seconds alone is never treated as a performance value — the adapter '
        'must not synthesise one from PracticeEntry (ADR 0293 §5)',
        () {
          final adapter = LegacyProgressEvidenceAdapter(
            mappingTable: mappingTable,
          );
          const busyEntry = PracticeEntry(
            day: 19945,
            source: PracticeSource.live,
            seconds: 3600,
          );

          final result = adapter.readEvidence(<LegacyProgressOutcome>[
            LegacyProgressOutcome(
              entry: busyEntry,
              measuredAt: DateTime.utc(2026, 8, 10),
              capturedAt: DateTime.utc(2026, 8, 15),
              skillId: 'chord.gMajor',
              sourceOutcomeId: OutcomeId('no-normalized-value'),
            ),
          ]);

          expect(result.evidence, isEmpty);
          expect(result.warnings.single.code, 'missingNormalizedPerformance');
        },
      );
    },
  );
}
