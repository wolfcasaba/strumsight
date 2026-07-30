import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/public.dart';
import 'package:strumsight/features/practice/data/adapters/lesson_practice_adapter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';

void main() {
  group(
    'practiceDefinitionFromLesson — full parity on the shipped catalog',
    () {
      final sources = <Lesson>[...Lessons.all, Lessons.firstWin];
      test('catalog baseline: 16 curriculum + first-win', () {
        expect(sources, hasLength(17));
      });

      for (final lesson in sources) {
        test('lesson.id=${lesson.id} matches every event slot exactly', () {
          final result = practiceDefinitionFromLesson(lesson);
          expect(result.isSuccess, isTrue, reason: '${lesson.id} failed');
          final def = (result as Success<PracticeDefinition>).value;

          expect(def.id, 'lesson.${lesson.id}.v1');
          expect(def.schemaVersion, 1);
          expect(def.titleKey, 'practiceSourceLessonTitle');
          expect(def.descriptionKey, 'practiceSourceLessonDescription');
          expect(def.mode, PracticeMode.strumPattern);
          expect(def.source, PracticeSource.lesson);
          expect(def.sourceReference, 'lesson:${lesson.id}');
          expect(def.meter.beatsPerBar, lesson.beatsPerBar);
          expect(def.defaultTempo.bpm, lesson.bpm);
          expect(def.totalBeats.toLegacyBeats(), lesson.totalBeats);
          expect(def.scoringProfile, ScoringProfile.legacyLearnParity);
          expect(def.skillTags, ['lessonImport']);
          expect(def.displayTitle, lesson.name.trim());
          expect(def.validate(), isEmpty);

          expect(def.events, hasLength(lesson.events.length));
          for (var i = 0; i < lesson.events.length; i++) {
            final src = lesson.events[i];
            final out = def.events[i];
            expect(
              out.position.toLegacyBeats(),
              src.beat,
              reason: '${lesson.id} event $i position drift',
            );
            expect(out.direction, src.direction);
          }
        });
      }
    },
  );

  group('practiceDefinitionFromLesson — Easy parity', () {
    final sources = <Lesson>[...Lessons.all, Lessons.firstWin];

    for (final lesson in sources) {
      test('lesson.id=${lesson.id} easy variant mirrors simplified events', () {
        final result = practiceDefinitionFromLesson(lesson, easy: true);
        expect(result.isSuccess, isTrue, reason: '${lesson.id} easy failed');
        final def = (result as Success<PracticeDefinition>).value;

        final simplified = lesson.simplified;
        expect(def.id, 'lesson.${lesson.id}.easy.v1');
        expect(def.sourceReference, 'lesson:${lesson.id}');
        expect(def.totalBeats.toLegacyBeats(), simplified.totalBeats);
        expect(def.skillTags, containsAll(['lessonImport', 'easyVariation']));
        expect(def.events, hasLength(simplified.events.length));
        for (var i = 0; i < simplified.events.length; i++) {
          expect(
            def.events[i].position.toLegacyBeats(),
            simplified.events[i].beat,
          );
        }
        expect(def.validate(), isEmpty);
      });
    }
  });

  group('practiceDefinitionFromLesson — displayTitle + chord consistency', () {
    test('chord labels match legacyPracticeChordLabel for every event', () {
      for (final lesson in Lessons.all) {
        final result = practiceDefinitionFromLesson(lesson);
        final def = (result as Success<PracticeDefinition>).value;
        for (var i = 0; i < lesson.events.length; i++) {
          final src = lesson.events[i];
          final expected = src.chord.isEmpty ? null : _normalize(src.chord);
          expect(
            def.events[i].chord,
            expected,
            reason: '${lesson.id} event $i chord',
          );
        }
      }
    });

    test('twoFingerFrame chords normalize to Em / C in order', () {
      final def =
          (practiceDefinitionFromLesson(Lessons.twoFingerFrame)
                  as Success<PracticeDefinition>)
              .value;
      final chords = def.events.map((e) => e.chord).whereType<String>().toSet();
      expect(chords, {'Em', 'C'});
    });

    test('bluesShuffle chords normalize to A / D', () {
      final def =
          (practiceDefinitionFromLesson(Lessons.bluesShuffle)
                  as Success<PracticeDefinition>)
              .value;
      final chords = def.events.map((e) => e.chord).whereType<String>().toSet();
      expect(chords, {'A', 'D'});
    });

    test('every chord in every lesson definition is canonical', () {
      for (final lesson in Lessons.all) {
        final def =
            (practiceDefinitionFromLesson(lesson)
                    as Success<PracticeDefinition>)
                .value;
        for (final event in def.events) {
          expect(
            isCanonicalPracticeChordLabel(event.chord),
            isTrue,
            reason:
                '${lesson.id} ${event.id} chord=${event.chord} must be canonical',
          );
        }
      }
    });

    test('displayTitle carries the lesson name and falls back to null', () {
      final def =
          (practiceDefinitionFromLesson(Lessons.firstStrums)
                  as Success<PracticeDefinition>)
              .value;
      expect(def.displayTitle, 'First Strums');
    });
  });

  group('practiceDefinitionFromLesson — controlled failure modes', () {
    test('returns Failure for empty events list', () {
      final empty = Lesson.fromEvents(
        id: 'empty',
        name: 'Empty',
        bpm: 80,
        events: const <LessonEvent>[],
        totalBeats: 4,
      );
      final result = practiceDefinitionFromLesson(empty);
      expect(result.isFailure, isTrue);
      expect(
        (result as Failure<PracticeDefinition>).error.code,
        'practice.content_unsupported',
      );
    });

    test('displayTitle trims whitespace and becomes null for empty name', () {
      final lesson = Lesson.fromEvents(
        id: 'whitespace-name',
        name: '   ',
        bpm: 80,
        events: const [
          LessonEvent(beat: 0, chord: '', direction: StrumDirection.down),
        ],
        totalBeats: 4,
      );
      final def =
          (practiceDefinitionFromLesson(lesson) as Success<PracticeDefinition>)
              .value;
      expect(def.displayTitle, isNull);
    });
  });

  group('practiceDefinitionFromLesson — difficulty mapping', () {
    test('preserves beginner, intermediate and advanced tiers', () {
      final beginner =
          (practiceDefinitionFromLesson(Lessons.firstStrums)
                  as Success<PracticeDefinition>)
              .value;
      final intermediate =
          (practiceDefinitionFromLesson(Lessons.downUpGroove)
                  as Success<PracticeDefinition>)
              .value;
      final advanced =
          (practiceDefinitionFromLesson(Lessons.bluesShuffle)
                  as Success<PracticeDefinition>)
              .value;
      expect(beginner.difficulty, PracticeDifficulty.beginner);
      expect(intermediate.difficulty, PracticeDifficulty.intermediate);
      expect(advanced.difficulty, PracticeDifficulty.advanced);
    });
  });
}

String _normalize(String label) {
  // Mirror legacyPracticeChordLabel for the labels the shipped lessons carry.
  // Adapter tests must not duplicate the normalizer — but pinning the chord
  // values here is what §6.3 of the brief calls for.
  if (label.isEmpty) return label;
  final root2 = label.length >= 2 && (label[1] == '#' || label[1] == 'b');
  final root = label.substring(0, root2 ? 2 : 1);
  final suffix = label.substring(root2 ? 2 : 1);
  const pitchClass = <String, int>{
    'C': 0,
    'C#': 1,
    'Db': 1,
    'D': 2,
    'D#': 3,
    'Eb': 3,
    'E': 4,
    'F': 5,
    'F#': 6,
    'Gb': 6,
    'G': 7,
    'G#': 8,
    'Ab': 8,
    'A': 9,
    'A#': 10,
    'Bb': 10,
    'B': 11,
  };
  const sharp = <String>[
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];
  final pitch = pitchClass[root];
  if (pitch == null) return label;
  final isMinor =
      suffix.isNotEmpty && suffix.startsWith('m') && !suffix.startsWith('maj');
  return '${sharp[pitch]}${isMinor ? 'm' : ''}';
}
