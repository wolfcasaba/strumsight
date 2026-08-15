import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/learn/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

/// A minimal fixture standing in for the built-in Learn lesson catalog
/// (round brief §3): only `id` matters to the adapter, but a realistic
/// `Lesson.fromEvents` is used so the test exercises the actual public
/// contract, not a hand-rolled stub.
Lesson lessonFixture(String id, {String name = 'Fixture Lesson'}) =>
    Lesson.fromEvents(
      id: id,
      name: name,
      bpm: 90,
      events: const <LessonEvent>[],
      totalBeats: 0,
    );

void main() {
  final mappingTable = const LegacyMappingTable(
    version: 3,
    entries: <LegacySkillMapping>[
      LegacySkillMapping(
        lessonId: 'g-major-first-strum',
        skillIds: <String>['chord.gMajor'],
      ),
      LegacySkillMapping(lessonId: 'no-signal-lesson', skillIds: <String>[]),
    ],
  );

  LegacyLessonOutcome outcomeFor(
    String lessonId, {
    String outcomeId = 'outcome-1',
    double accuracy = 0.75,
  }) => LegacyLessonOutcome(
    lesson: lessonFixture(lessonId),
    sourceOutcomeId: OutcomeId(outcomeId),
    measuredAt: DateTime.utc(2026, 8, 10),
    capturedAt: DateTime.utc(2026, 8, 15),
    performance: PerformanceEvidence(
      metricCode: 'chordChangeAccuracy',
      value: accuracy,
    ),
  );

  group('LegacyLessonCatalogAdapter — mapping boundary (§6.1)', () {
    test('a mapped lesson id produces legacy-sourced evidence', () {
      final adapter = LegacyLessonCatalogAdapter(mappingTable: mappingTable);

      final result = adapter.readEvidence(<LegacyLessonOutcome>[
        outcomeFor('g-major-first-strum'),
      ]);

      expect(result.warnings, isEmpty);
      expect(result.evidence, hasLength(1));
      final evidence = result.evidence.single;
      expect(evidence.skillId, 'chord.gMajor');
      expect(evidence.source, EvidenceSource.learn);
    });

    test(
      'a known lesson id with an empty mapping produces no evidence (not a guess)',
      () {
        final adapter = LegacyLessonCatalogAdapter(mappingTable: mappingTable);

        final result = adapter.readEvidence(<LegacyLessonOutcome>[
          outcomeFor('no-signal-lesson'),
        ]);

        expect(result.evidence, isEmpty);
        expect(result.warnings, hasLength(1));
        expect(result.warnings.single.code, 'emptySkillMapping');
      },
    );

    test('an unmapped lesson id produces no evidence and no exception (A2)', () {
      final adapter = LegacyLessonCatalogAdapter(mappingTable: mappingTable);

      Object? thrown;
      late final SkillSnapshotResult result;
      try {
        result = adapter.readEvidence(<LegacyLessonOutcome>[
          outcomeFor('totally-unknown-lesson'),
        ]);
      } catch (e) {
        thrown = e;
      }

      expect(thrown, isNull);
      expect(result.evidence, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single.code, 'unmappedLesson');
    });
  });

  group('LegacyLessonCatalogAdapter — provenance (A3, A4)', () {
    test('the evidence measurementVersion is the mapping table version (A3)', () {
      final adapter = LegacyLessonCatalogAdapter(mappingTable: mappingTable);

      final result = adapter.readEvidence(<LegacyLessonOutcome>[
        outcomeFor('g-major-first-strum'),
      ]);

      expect(result.evidence.single.measurementVersion, 3);
    });

    test('the evidence source is marked legacy learn, not a live source (A4)', () {
      final adapter = LegacyLessonCatalogAdapter(mappingTable: mappingTable);

      final result = adapter.readEvidence(<LegacyLessonOutcome>[
        outcomeFor('g-major-first-strum'),
      ]);

      expect(result.evidence.single.source, EvidenceSource.learn);
      expect(result.evidence.single.source, isNot(EvidenceSource.analyzeV2));
    });
  });

  group('LegacyLessonCatalogAdapter — dedup and determinism (A5, A6)', () {
    test('a duplicated source outcome id is ingested once, order-independent', () {
      final adapter = LegacyLessonCatalogAdapter(mappingTable: mappingTable);
      final first = outcomeFor('g-major-first-strum', outcomeId: 'dup-1');
      final second = outcomeFor('g-major-first-strum', outcomeId: 'dup-1');

      final forward = adapter.readEvidence(<LegacyLessonOutcome>[
        first,
        second,
      ]);
      final reversed = adapter.readEvidence(<LegacyLessonOutcome>[
        second,
        first,
      ]);

      expect(forward.evidence, hasLength(1));
      expect(reversed.evidence, hasLength(1));
      expect(forward.evidence.single.sourceOutcomeId, reversed.evidence.single.sourceOutcomeId);
    });
  });

  group('LegacyLessonCatalogAdapter — real-violation probe (§6.1, documented in §10)', () {
    test(
      'a name-similarity fallback (rejected design) would wrongly map an unmapped lesson',
      () {
        // This test intentionally exercises what the round brief forbids:
        // guessing a skill because the lesson name contains a chord name.
        // It asserts the CORRECT (adapter) behaviour — no evidence — and
        // documents, via the comment, what a heuristic fallback would do
        // instead (produce evidence and turn A1 red). See round handoff §10
        // for the full probe-and-revert record.
        final adapter = LegacyLessonCatalogAdapter(mappingTable: mappingTable);

        final result = adapter.readEvidence(<LegacyLessonOutcome>[
          LegacyLessonOutcome(
            lesson: lessonFixture(
              'totally-unmapped-lesson',
              name: 'G Major Warm-Up',
            ),
            sourceOutcomeId: OutcomeId('probe-1'),
            measuredAt: DateTime.utc(2026, 8, 10),
            capturedAt: DateTime.utc(2026, 8, 15),
            performance: PerformanceEvidence(
              metricCode: 'chordChangeAccuracy',
              value: 0.9,
            ),
          ),
        ]);

        expect(
          result.evidence,
          isEmpty,
          reason:
              'the lesson name contains "G Major" but has no explicit mapping '
              'entry — a name-heuristic fallback would wrongly produce '
              'evidence here (A1)',
        );
        expect(result.warnings.single.code, 'unmappedLesson');
      },
    );
  });
}
