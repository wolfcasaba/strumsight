import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/data/adapters/song_practice_adapter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/songs/public.dart';

const _down = StrumDirection.down;
const _up = StrumDirection.up;

PracticeDefinition _defFromSong(AppResult<PracticeDefinition> r) =>
    (r as Success<PracticeDefinition>).value;

void main() {
  group('practiceDefinitionFromSong — parity with toLesson() events', () {
    test('4/4 single-bar 8-slot pattern, 1 chord', () {
      const song = Song(
        id: 's1',
        name: 'Single bar',
        chords: ['Em'],
        pattern: [_down, null, _down, null, _down, null, _down, null],
        bpm: 80,
      );
      final def = _defFromSong(practiceDefinitionFromSong(song));
      final legacy = song.toLesson();
      expect(def.events, hasLength(legacy.events.length));
      for (var i = 0; i < legacy.events.length; i++) {
        expect(def.events[i].position.toLegacyBeats(), legacy.events[i].beat);
        expect(def.events[i].direction, legacy.events[i].direction);
        expect(def.events[i].chord, 'Em');
      }
      expect(def.totalBeats.toLegacyBeats(), legacy.totalBeats);
    });

    test('4/4 four-bar 8-slot pattern with up-strokes', () {
      const song = Song(
        id: 's2',
        name: 'Four bars',
        chords: ['C', 'G', 'Am', 'F'],
        pattern: [_down, null, _down, _up, null, _up, _down, _up],
        bpm: 96,
      );
      final def = _defFromSong(practiceDefinitionFromSong(song));
      final legacy = song.toLesson();
      expect(def.events, hasLength(legacy.events.length));
      for (var i = 0; i < legacy.events.length; i++) {
        expect(def.events[i].position.toLegacyBeats(), legacy.events[i].beat);
        expect(def.events[i].direction, legacy.events[i].direction);
      }
      expect(def.totalBeats.toLegacyBeats(), legacy.totalBeats);
      expect(def.meter.beatsPerBar, 4);
    });

    test('4/4 eight-bar full-eighth pattern', () {
      const song = Song(
        id: 's3',
        name: 'Eight bars',
        chords: ['G', 'G', 'D', 'D', 'Em', 'Em', 'C', 'C'],
        pattern: [_down, _down, _down, _down, _down, _down, _down, _down],
        bpm: 100,
      );
      final def = _defFromSong(practiceDefinitionFromSong(song));
      final legacy = song.toLesson();
      expect(def.events, hasLength(legacy.events.length));
      for (var i = 0; i < legacy.events.length; i++) {
        expect(def.events[i].position.toLegacyBeats(), legacy.events[i].beat);
        expect(def.events[i].direction, legacy.events[i].direction);
      }
    });

    test('3/4 six-slot pattern over four bars', () {
      const song = Song(
        id: 's4',
        name: 'Waltz',
        chords: ['C', 'F', 'C', 'G'],
        pattern: [_down, null, _up, null, _up, null],
        bpm: 84,
        beatsPerBar: 3,
      );
      final def = _defFromSong(practiceDefinitionFromSong(song));
      final legacy = song.toLesson();
      expect(def.meter.beatsPerBar, 3);
      expect(def.events, hasLength(legacy.events.length));
      for (var i = 0; i < legacy.events.length; i++) {
        expect(def.events[i].position.toLegacyBeats(), legacy.events[i].beat);
        expect(def.events[i].direction, legacy.events[i].direction);
      }
    });

    test('mixed rests pattern still expands correctly', () {
      const song = Song(
        id: 's5',
        name: 'Mixed rests',
        chords: ['Am', 'Dm'],
        pattern: [null, _up, null, _up, _down, null, _down, null],
        bpm: 90,
      );
      final def = _defFromSong(practiceDefinitionFromSong(song));
      final legacy = song.toLesson();
      expect(def.events, hasLength(legacy.events.length));
      for (var i = 0; i < legacy.events.length; i++) {
        expect(def.events[i].position.toLegacyBeats(), legacy.events[i].beat);
        expect(def.events[i].direction, legacy.events[i].direction);
      }
    });

    test('empty/whitespace name falls back to null displayTitle', () {
      const song = Song(
        id: 'no-name',
        name: '   ',
        chords: ['Em'],
        pattern: [_down, null, _down, null, _down, null, _down, null],
        bpm: 80,
      );
      final def = _defFromSong(practiceDefinitionFromSong(song));
      expect(def.displayTitle, isNull);
    });
  });

  group('practiceDefinitionFromSong — definition surface', () {
    test('IDs, source, mode, profile match the ADR contract', () {
      const song = Song(
        id: 'my-song',
        name: 'My Song',
        chords: ['C'],
        pattern: [_down, null, _down, null, _down, null, _down, null],
        bpm: 90,
      );
      final def = _defFromSong(practiceDefinitionFromSong(song));
      expect(def.id, 'song.my-song.v1');
      expect(def.source, PracticeSource.song);
      expect(def.sourceReference, 'song:my-song');
      expect(def.mode, PracticeMode.strumPattern);
      expect(def.titleKey, 'practiceSourceSongTitle');
      expect(def.descriptionKey, 'practiceSourceSongDescription');
      expect(def.skillTags, ['songImport']);
      expect(def.displayTitle, 'My Song');
      expect(def.validate(), isEmpty);
    });
  });

  group('practiceDefinitionFromSong — controlled failure modes', () {
    AppResult<PracticeDefinition> call(Song song) =>
        practiceDefinitionFromSong(song);

    AppFailure err(AppResult<PracticeDefinition> r) =>
        (r as Failure<PracticeDefinition>).error;

    test('rejects empty chords', () {
      const song = Song(
        id: 'empty-chords',
        name: 'X',
        chords: <String>[],
        pattern: [_down, null, _down, null, _down, null, _down, null],
        bpm: 80,
      );
      final r = call(song);
      expect(r.isFailure, isTrue);
      expect(err(r).code, FailureCode.practiceContentUnsupported);
    });

    test('rejects pattern length that does not fit the meter', () {
      const song = Song(
        id: 'wrong-len',
        name: 'X',
        chords: ['Em'],
        pattern: [_down, _down, _down, _down], // 4 slots, but beatsPerBar=4
        bpm: 80,
      );
      final r = call(song);
      expect(r.isFailure, isTrue);
      expect(err(r).code, FailureCode.practiceContentUnsupported);
    });

    test('rejects a pattern with only null slots', () {
      const song = Song(
        id: 'rest-only',
        name: 'X',
        chords: ['Em'],
        pattern: [null, null, null, null, null, null, null, null],
        bpm: 80,
      );
      final r = call(song);
      expect(r.isFailure, isTrue);
      expect(err(r).code, FailureCode.practiceContentUnsupported);
    });

    test('rejects bpm above the Tempo ceiling (400)', () {
      const song = Song(
        id: 'too-fast',
        name: 'X',
        chords: ['Em'],
        pattern: [_down, null, _down, null, _down, null, _down, null],
        bpm: 400,
      );
      final r = call(song);
      expect(r.isFailure, isTrue);
      expect(err(r).code, FailureCode.practiceContentUnsupported);
    });

    test('rejects bpm below the Tempo floor (10)', () {
      const song = Song(
        id: 'too-slow',
        name: 'X',
        chords: ['Em'],
        pattern: [_down, null, _down, null, _down, null, _down, null],
        bpm: 10,
      );
      final r = call(song);
      expect(r.isFailure, isTrue);
      expect(err(r).code, FailureCode.practiceContentUnsupported);
    });

    test('none of the failure paths throws', () {
      const songs = <Song>[
        Song(
          id: 'empty-chords',
          name: 'X',
          chords: <String>[],
          pattern: [_down, null, _down, null, _down, null, _down, null],
          bpm: 80,
        ),
        Song(
          id: 'wrong-len',
          name: 'X',
          chords: ['Em'],
          pattern: [_down, _down, _down, _down],
          bpm: 80,
        ),
        Song(
          id: 'rest-only',
          name: 'X',
          chords: ['Em'],
          pattern: [null, null, null, null, null, null, null, null],
          bpm: 80,
        ),
        Song(
          id: 'too-fast',
          name: 'X',
          chords: ['Em'],
          pattern: [_down, null, _down, null, _down, null, _down, null],
          bpm: 400,
        ),
        Song(
          id: 'too-slow',
          name: 'X',
          chords: ['Em'],
          pattern: [_down, null, _down, null, _down, null, _down, null],
          bpm: 10,
        ),
      ];
      for (final song in songs) {
        expect(() => practiceDefinitionFromSong(song), returnsNormally);
      }
    });
  });

  group('song_practice_adapter source guard', () {
    test('forbidden to call Song.toLesson() — source-level scan', () {
      final file = File(
        'lib/features/practice/data/adapters/song_practice_adapter.dart',
      );
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      expect(
        source.contains('toLesson'),
        isFalse,
        reason:
            'Song adapter must not call Song.toLesson(); '
            'the parity check compares against the legacy builder, but the '
            'adapter itself builds events directly.',
      );
    });
  });
}
