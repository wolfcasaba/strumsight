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
}
