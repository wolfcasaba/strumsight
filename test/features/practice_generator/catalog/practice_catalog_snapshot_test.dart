import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  ExerciseCandidate candidate({
    required String exerciseId,
    CandidateSource source = CandidateSource.practiceCatalog,
    String contentRevision = 'content.v1',
  }) => ExerciseCandidate(
    exerciseId: exerciseId,
    source: source,
    skillTargets: const <String>['rhythm.quarterNotes'],
    prerequisites: const <String>['guitar.tuned'],
    supportedDurations: SupportedDurations.exact(const Duration(minutes: 1)),
    difficultyRange: DifficultyRange.exact('beginner'),
    capabilities: allCapabilitiesUnsupported(),
    loadProfile: const ExerciseLoadProfile.all(LoadLevel.low),
    offlineAvailable: true,
    contentRevision: contentRevision,
  );

  group('PracticeCatalogSnapshot — revisions (A3, A4)', () {
    test('carries independent catalog and content revisions', () {
      final snapshot = PracticeCatalogSnapshot(
        catalogRevision: 'catalog.v3',
        contentRevision: 'content.v8',
        candidates: <ExerciseCandidate>[candidate(exerciseId: 'exercise.a')],
      );

      expect(snapshot.catalogRevision, 'catalog.v3');
      expect(snapshot.contentRevision, 'content.v8');
    });

    test('reports the exact revision dimension that mismatches', () {
      final baseline = PracticeCatalogSnapshot(
        catalogRevision: 'catalog.v3',
        contentRevision: 'content.v8',
        candidates: <ExerciseCandidate>[candidate(exerciseId: 'exercise.a')],
      );
      final changedContent = PracticeCatalogSnapshot(
        catalogRevision: 'catalog.v3',
        contentRevision: 'content.v9',
        candidates: <ExerciseCandidate>[candidate(exerciseId: 'exercise.a')],
      );

      expect(
        baseline.mismatchesAgainst(changedContent),
        <CatalogRevisionMismatch>{CatalogRevisionMismatch.content},
      );
    });
  });

  group('PracticeCatalogSnapshot — deterministic ordering (A5)', () {
    test(
      'sorts the complete candidate set by stable source and exercise id',
      () {
        final input = <ExerciseCandidate>[
          candidate(exerciseId: 'z', source: CandidateSource.legacyLesson),
          candidate(exerciseId: 'b'),
          candidate(exerciseId: 'a'),
        ];

        final first = PracticeCatalogSnapshot(
          catalogRevision: 'catalog.v1',
          contentRevision: 'content.v1',
          candidates: input,
        );
        final second = PracticeCatalogSnapshot(
          catalogRevision: 'catalog.v1',
          contentRevision: 'content.v1',
          candidates: input.reversed,
        );

        expect(
          first.candidates.map((candidate) => candidate.sortKey),
          second.candidates.map((candidate) => candidate.sortKey),
        );
        expect(first.candidates.map((candidate) => candidate.sortKey), <String>[
          'legacyLesson:z:content.v1',
          'practiceCatalog:a:content.v1',
          'practiceCatalog:b:content.v1',
        ]);
      },
    );
  });

  group('Practice catalog values — equality (F2)', () {
    test('ExerciseCandidate compares every value field', () {
      expect(
        candidate(exerciseId: 'exercise.a'),
        candidate(exerciseId: 'exercise.a'),
      );
      expect(
        candidate(exerciseId: 'exercise.a'),
        isNot(candidate(exerciseId: 'exercise.b')),
      );
    });

    test('SupportedDurations compares both bounds', () {
      expect(
        SupportedDurations.exact(const Duration(minutes: 1)),
        SupportedDurations.exact(const Duration(minutes: 1)),
      );
      expect(
        SupportedDurations.exact(const Duration(minutes: 1)),
        isNot(SupportedDurations.exact(const Duration(minutes: 2))),
      );
    });

    test('DifficultyRange compares both bounds', () {
      expect(
        DifficultyRange.exact('beginner'),
        DifficultyRange.exact('beginner'),
      );
      expect(
        DifficultyRange.exact('beginner'),
        isNot(DifficultyRange.exact('intermediate')),
      );
    });

    test('ExerciseLoadProfile compares every load dimension', () {
      expect(
        const ExerciseLoadProfile.all(LoadLevel.low),
        const ExerciseLoadProfile.all(LoadLevel.low),
      );
      expect(
        const ExerciseLoadProfile.all(LoadLevel.low),
        isNot(const ExerciseLoadProfile.all(LoadLevel.high)),
      );
    });

    test('PracticeCatalogSnapshot compares revisions and content', () {
      final same = PracticeCatalogSnapshot(
        catalogRevision: 'catalog.v1',
        contentRevision: 'content.v1',
        candidates: <ExerciseCandidate>[candidate(exerciseId: 'exercise.a')],
      );
      final different = PracticeCatalogSnapshot(
        catalogRevision: 'catalog.v2',
        contentRevision: 'content.v1',
        candidates: <ExerciseCandidate>[candidate(exerciseId: 'exercise.a')],
      );

      expect(
        same,
        PracticeCatalogSnapshot(
          catalogRevision: 'catalog.v1',
          contentRevision: 'content.v1',
          candidates: <ExerciseCandidate>[candidate(exerciseId: 'exercise.a')],
        ),
      );
      expect(same, isNot(different));
    });

    test('CandidateExclusionWarning compares every value field', () {
      const warning = CandidateExclusionWarning(
        reason: CandidateExclusionReason.missingPrerequisite,
        source: 'practiceCatalog',
        exerciseId: 'exercise.a',
        detail: 'prerequisites',
      );

      expect(
        warning,
        const CandidateExclusionWarning(
          reason: CandidateExclusionReason.missingPrerequisite,
          source: 'practiceCatalog',
          exerciseId: 'exercise.a',
          detail: 'prerequisites',
        ),
      );
      expect(
        warning,
        isNot(
          const CandidateExclusionWarning(
            reason: CandidateExclusionReason.missingPrerequisite,
            source: 'practiceCatalog',
            exerciseId: 'exercise.a',
            detail: 'loadProfile',
          ),
        ),
      );
    });
  });
}
