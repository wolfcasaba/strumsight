import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/json_validation.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/library/model/analyzed_session.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart';
import 'package:strumsight/features/songs/model/setlist.dart';
import 'package:strumsight/features/songs/model/song.dart';
import 'package:strumsight/features/streak/model/streak_data.dart';

/// E01-R07 §7.1 — every persisted model validates what it decodes.
///
/// The chapter names the cases explicitly: missing fields, a bad enum, a
/// negative duration, a bad date, a missing chord label and an oversized list.
/// Each one below is a record the app could not have written, so decoding must
/// REJECT it (the storage layer then skips that one record) rather than build a
/// half-valid object the UI has to cope with.
void main() {
  Map<String, dynamic> songJson() => {
    'id': 's1',
    'name': 'Riff',
    'chords': ['C', 'G'],
    'pat': 'd-u-d-u-',
    'bpm': 90,
    'bpb': 4,
  };

  Map<String, dynamic> sessionJson() => {
    'id': 'a1',
    'createdAt': '2026-07-12T10:00:00.000',
    'title': 'C · G',
    'result': {
      'duration': 4.0,
      'bpm': 92.0,
      'chords': [
        {'label': 'C', 'start': 0.0, 'end': 2.0},
      ],
      'strums': [
        {'dir': 'down', 'time': 0.5, 'conf': 0.8},
      ],
      'bpb': 4,
    },
  };

  group('a valid record still decodes', () {
    test('song / setlist / session / entry / streak round-trip', () {
      expect(Song.fromJson(songJson()).chords, ['C', 'G']);
      expect(
        Setlist.fromJson({
          'id': 'l',
          'name': 'Gig',
          'songs': ['s1'],
        }).songIds,
        ['s1'],
      );
      expect(AnalyzedSession.fromJson(sessionJson()).id, 'a1');
      expect(
        PracticeEntry.fromJson({
          'day': 20643,
          'src': 'learn',
          'sec': 60,
        }).source,
        PracticeSource.learn,
      );
      expect(StreakData.fromJson({'current': 7}).current, 7);
    });

    test('an older record without the newer fields keeps its defaults', () {
      final legacy = songJson()..remove('bpb'); // pre-round-116: always 4/4
      expect(Song.fromJson(legacy).beatsPerBar, 4);
      expect(
        AnalyzedSession.fromJson(sessionJson()).customTitle,
        isFalse,
        reason: 'customTitle predates round 114',
      );
    });
  });

  group('missing fields', () {
    test('a song without an id is rejected', () {
      expect(
        () => Song.fromJson(songJson()..remove('id')),
        throwsA(isA<JsonRecordException>()),
      );
    });

    test('a practice entry without a day is rejected', () {
      expect(
        () => PracticeEntry.fromJson({'src': 'live'}),
        throwsA(isA<JsonRecordException>()),
      );
    });
  });

  test('a bad enum: an unknown strum direction is rejected', () {
    expect(
      () =>
          TimelineStrum.fromJson({'dir': 'sideways', 'time': 0.5, 'conf': 0.8}),
      throwsA(isA<JsonRecordException>()),
    );
  });

  test('a NEWER practice source degrades instead of losing the moment', () {
    // The deliberate exception (documented on the model): the practice really
    // happened; only its attribution is unknown to this build.
    final entry = PracticeEntry.fromJson({'day': 1, 'src': 'jam-session'});
    expect(entry.source, PracticeSource.live);
    expect(entry.day, 1);
  });

  group('negative duration', () {
    test('an analysis with a negative duration is rejected', () {
      final json = sessionJson();
      (json['result'] as Map<String, dynamic>)['duration'] = -4.0;
      expect(
        () => AnalyzedSession.fromJson(json),
        throwsA(isA<JsonRecordException>()),
      );
    });

    test('a practice entry with negative seconds is rejected', () {
      expect(
        () => PracticeEntry.fromJson({'day': 1, 'src': 'live', 'sec': -60}),
        throwsA(isA<JsonRecordException>()),
      );
    });

    test('a NaN duration is rejected (it poisons every later sum)', () {
      final json = sessionJson();
      (json['result'] as Map<String, dynamic>)['duration'] = double.nan;
      expect(
        () => AnalyzedSession.fromJson(json),
        throwsA(isA<JsonRecordException>()),
      );
    });
  });

  group('a bad date', () {
    test('an unparseable createdAt is rejected, never replaced with now', () {
      expect(
        () =>
            AnalyzedSession.fromJson(sessionJson()..['createdAt'] = 'sometime'),
        throwsA(isA<JsonRecordException>()),
      );
    });
  });

  group('a missing chord label', () {
    test('a blank label in a timeline is rejected', () {
      expect(
        () => TimelineChord.fromJson({'label': '', 'start': 0.0, 'end': 1.0}),
        throwsA(isA<JsonRecordException>()),
      );
    });

    test('a blank bar in a song progression is rejected', () {
      expect(
        () => Song.fromJson(songJson()..['chords'] = ['C', '']),
        throwsA(isA<JsonRecordException>()),
      );
    });
  });

  group('an oversized list', () {
    test('a song claiming more bars than the bound is rejected', () {
      expect(
        () => Song.fromJson(
          songJson()..['chords'] = List.filled(maxSongBars + 1, 'C'),
        ),
        throwsA(isA<JsonRecordException>()),
      );
    });

    test('a setlist claiming more entries than the bound is rejected', () {
      expect(
        () => Setlist.fromJson({
          'id': 'l',
          'name': 'Gig',
          'songs': List.filled(maxSetlistEntries + 1, 's1'),
        }),
        throwsA(isA<JsonRecordException>()),
      );
    });

    test('an analysis with a gigantic timeline is rejected', () {
      final json = sessionJson();
      (json['result'] as Map<String, dynamic>)['chords'] = [
        for (var i = 0; i < maxTimelineChords + 1; i++)
          {'label': 'C', 'start': 0.0, 'end': 1.0},
      ];
      expect(
        () => AnalyzedSession.fromJson(json),
        throwsA(isA<JsonRecordException>()),
      );
    });
  });

  group('out-of-range values', () {
    test('a song tempo outside the playable range is rejected', () {
      expect(
        () => Song.fromJson(songJson()..['bpm'] = 0),
        throwsA(isA<JsonRecordException>()),
      );
    });

    test('a direction accuracy above 1 is rejected', () {
      expect(
        () => PracticeEntry.fromJson({'day': 1, 'src': 'learn', 'dir': 1.4}),
        throwsA(isA<JsonRecordException>()),
      );
    });

    test('the streak keeps its -1 "never practised" sentinel', () {
      expect(StreakData.fromJson({'last': -1}).lastPracticeDay, -1);
      expect(
        () => StreakData.fromJson({'last': -2}),
        throwsA(isA<JsonRecordException>()),
      );
    });
  });
}
