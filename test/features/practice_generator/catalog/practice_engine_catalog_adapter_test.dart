import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/learn/public.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  const definition = PracticeDefinition(
    id: 'builtin.quarterDownstrokes.v1',
    schemaVersion: 1,
    titleKey: 'title',
    descriptionKey: 'description',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(60),
    totalBeats: BeatPosition(480),
    events: <PracticeEvent>[],
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: <String>['rhythm.quarterNotes'],
  );

  const completeEntry = PracticeCatalogEntry(
    definition: definition,
    prerequisites: <String>['guitar.tuned'],
    offlineAvailable: false,
    contentRevision: 'builtin.quarterDownstrokes.v1',
    loadProfile: ExerciseLoadProfile.all(LoadLevel.low),
  );

  group('PracticeEngineCatalogAdapter — executable references (A1)', () {
    test(
      'maps the supplied practice definition id without inventing content',
      () {
        const adapter = PracticeEngineCatalogAdapter();

        final result = adapter.adapt(<PracticeCatalogEntry>[completeEntry]);

        expect(result.warnings, isEmpty);
        expect(result.candidates, hasLength(1));
        expect(result.candidates.single.exerciseId, definition.id);
        expect(
          result.candidates.single.source,
          CandidateSource.practiceCatalog,
        );
      },
    );
  });

  group(
    'PracticeEngineCatalogAdapter — capability and offline truth (A2, A7)',
    () {
      test('marks source-unsupported capabilities explicitly unsupported', () {
        const adapter = PracticeEngineCatalogAdapter();

        final candidate = adapter
            .adapt(<PracticeCatalogEntry>[completeEntry])
            .candidates
            .single;

        expect(
          candidate.capabilities[ExerciseCapability.requiresCamera],
          CapabilitySupport.unsupported,
        );
        expect(
          candidate.capabilities[ExerciseCapability.requiresBackingTrack],
          CapabilitySupport.unsupported,
        );
        expect(
          candidate.capabilities[ExerciseCapability.supportsDirectionScoring],
          CapabilitySupport.supported,
        );
      });

      test(
        'uses caller-supplied offline metadata without runtime guessing',
        () {
          const adapter = PracticeEngineCatalogAdapter();

          final candidate = adapter
              .adapt(<PracticeCatalogEntry>[completeEntry])
              .candidates
              .single;

          expect(candidate.offlineAvailable, isFalse);
          expect(
            candidate.capabilities[ExerciseCapability.supportsOffline],
            CapabilitySupport.unsupported,
          );
        },
      );
    },
  );

  group('PracticeEngineCatalogAdapter — required metadata (A6)', () {
    test(
      'skips incomplete entries and warns instead of defaulting metadata',
      () {
        const adapter = PracticeEngineCatalogAdapter();

        final result = adapter.adapt(<PracticeCatalogEntry>[
          const PracticeCatalogEntry(
            definition: definition,
            prerequisites: null,
            offlineAvailable: true,
            contentRevision: 'builtin.quarterDownstrokes.v1',
            loadProfile: ExerciseLoadProfile.all(LoadLevel.low),
          ),
          const PracticeCatalogEntry(
            definition: PracticeDefinition(
              id: 'missing-skill',
              schemaVersion: 1,
              titleKey: 'title',
              descriptionKey: 'description',
              mode: PracticeMode.freePractice,
              source: PracticeSource.builtin,
              meter: Meter(beatsPerBar: 4),
              defaultTempo: Tempo(60),
              totalBeats: BeatPosition(480),
              events: <PracticeEvent>[],
              scoringProfile: ScoringProfile.freePracticeOpen,
              skillTags: <String>[],
            ),
            prerequisites: <String>['guitar.tuned'],
            offlineAvailable: true,
            contentRevision: 'missing-skill.v1',
            loadProfile: ExerciseLoadProfile.all(LoadLevel.low),
          ),
        ]);

        expect(result.candidates, isEmpty);
        expect(
          result.warnings.map((warning) => warning.reason),
          everyElement(CandidateExclusionReason.missingPrerequisite),
        );
      },
    );
  });

  group('LegacyLessonCandidateAdapter — fallback references', () {
    test('uses an explicit mapping and preserves the legacy lesson id', () {
      const adapter = LegacyLessonCandidateAdapter(
        mappingTable: LegacyMappingTable(
          version: 1,
          entries: <LegacySkillMapping>[
            LegacySkillMapping(
              lessonId: 'first-strums',
              skillId: 'chord.gMajor',
            ),
          ],
        ),
      );
      final lesson = Lesson.fromEvents(
        id: 'first-strums',
        name: 'First Strums',
        bpm: 60,
        events: const <LessonEvent>[],
        totalBeats: 4,
        difficulty: Difficulty.intermediate,
      );

      final result = adapter.adapt(<LegacyLessonCatalogEntry>[
        LegacyLessonCatalogEntry(
          lesson: lesson,
          prerequisites: const <String>['guitar.tuned'],
          offlineAvailable: true,
          contentRevision: 'legacy.first-strums.v1',
          loadProfile: ExerciseLoadProfile.all(LoadLevel.medium),
        ),
      ]);

      expect(result.warnings, isEmpty);
      expect(result.candidates.single.exerciseId, 'first-strums');
      expect(result.candidates.single.source, CandidateSource.legacyLesson);
      expect(result.candidates.single.skillTargets, <String>['chord.gMajor']);
      expect(result.candidates.single.difficultyRange.minimum, 'intermediate');
    });
  });
}
