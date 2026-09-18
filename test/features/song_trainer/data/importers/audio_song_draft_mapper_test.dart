// K3/A1 — audio analysis → DRAFT song mapping.
//
// The cells below measure the three decisions that separate an honest draft
// from a fabricated song: the progression's ORDER survives quantisation, a
// chord timeline with nothing in it produces a NAMED failure instead of a
// zero-event "finished" song, and an undecided strum is dropped rather than
// written down as a direction the detector never picked.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/song_trainer/data/importers/audio_song_draft_mapper.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/services/song_validator.dart';

const List<TimelineChord> _oneChord = <TimelineChord>[
  TimelineChord(label: 'G', startSec: 0, endSec: 2),
];

void main() {
  test('a G-C-D progression keeps its order and snaps onto the beat', () {
    const chords = <TimelineChord>[
      TimelineChord(label: 'G', startSec: 0, endSec: 2),
      TimelineChord(label: 'C', startSec: 2.02, endSec: 4),
      TimelineChord(label: 'D', startSec: 4, endSec: 6),
    ];
    final result = _map(_analysis(bpm: 120, chords: chords));

    final draft = _success(result);
    final events = _chordTrack(draft).events;
    final labels = events.map((event) => event.symbol.label).toList();
    expect(labels, _gcd);
    expect(events[0].start, Duration.zero);
    expect(events[0].duration, const Duration(seconds: 2));
    // 2.02 s rounds onto beat 4 at 120 BPM — the grid, not the raw time.
    expect(events[1].start, const Duration(seconds: 2));
    expect(events[2].start, const Duration(seconds: 4));
    expect(draft.bpm, 120);
    expect(draft.tempoEstimated, isTrue);
  });

  test('consecutive identical chords are merged into one event', () {
    const chords = <TimelineChord>[
      TimelineChord(label: 'G', startSec: 0, endSec: 1),
      TimelineChord(label: 'G', startSec: 1, endSec: 2),
      TimelineChord(label: 'C', startSec: 2, endSec: 3),
    ];
    final result = _map(_analysis(bpm: 120, chords: chords));

    final draft = _success(result);
    final events = _chordTrack(draft).events;
    expect(events.length, 2);
    expect(events.first.symbol.label, 'G');
    expect(events.first.duration, const Duration(seconds: 2));
    expect(draft.warnings, contains(_merged));
  });

  test('an empty chord timeline is a named failure, not a 0-event song', () {
    final result = _map(_analysis(bpm: 120));

    expect(result, isA<Failure<AudioSongDraft>>());
    expect(_code(result), AudioSongDraftFailureCode.noChords);
  });

  test('a non-positive clip length is refused by name', () {
    final analysis = _analysis(bpm: 120, chords: _oneChord);
    final result = _map(analysis, duration: Duration.zero);

    expect(_code(result), AudioSongDraftFailureCode.invalidDuration);
  });

  test('a missing tempo falls back to 100 BPM and says so', () {
    final result = _map(_analysis(bpm: 0, chords: _oneChord));

    final draft = _success(result);
    expect(draft.bpm, AudioSongDraftMapper.fallbackTempoBpm);
    expect(draft.tempoEstimated, isFalse);
    expect(draft.warnings, contains(_fallback));
    expect(draft.document.tempoMap.changes.single.bpm.bpm, 100);
  });

  test('an implausible tempo is clamped into the practicable range', () {
    final result = _map(_analysis(bpm: 900, chords: _oneChord));

    final draft = _success(result);
    expect(draft.bpm, AudioSongDraftMapper.maxTempoBpm);
    expect(draft.warnings, contains(_clamped));
  });

  test('an uncertain strum is dropped instead of guessed', () {
    const strums = <TimelineStrum>[
      TimelineStrum(
        direction: StrumDirection.down,
        timeSec: 0.5,
        confidence: 0.9,
      ),
      TimelineStrum(direction: StrumDirection.up, timeSec: 1, confidence: 0.2),
    ];
    final analysis = _analysis(bpm: 120, chords: _oneChord, strums: strums);
    final result = _map(analysis);

    final draft = _success(result);
    final events = _strumTrack(draft).events;
    expect(events.length, 1);
    expect(events.single.direction, StrumDirection.down);
    expect(events.single.at, const Duration(milliseconds: 500));
    expect(draft.warnings, contains(_uncertain));
  });

  test('the draft carries audio provenance and passes validation', () {
    const chords = <TimelineChord>[
      TimelineChord(label: 'G', startSec: 0, endSec: 2),
      TimelineChord(label: 'C', startSec: 2, endSec: 4),
    ];
    const strums = <TimelineStrum>[
      TimelineStrum(
        direction: StrumDirection.down,
        timeSec: 0.25,
        confidence: 0.8,
      ),
    ];
    final analysis = _analysis(bpm: 96, chords: chords, strums: strums);
    final result = _map(analysis, fileName: 'practice/My Song.mp3');

    final draft = _success(result);
    final document = draft.document;
    expect(document.source.type, SongSourceType.audioAnalysis);
    expect(document.source.warningSummary, contains(_review));
    expect(document.source.originalFileName, 'practice/My Song.mp3');
    expect(document.metadata.title, 'My Song');
    expect(document.metadata.tags, contains('draft'));

    final section = document.sections.single;
    expect(section.name, 'My Song');
    expect(section.startMeasure, 0);
    expect(section.endMeasureExclusive, document.measures.length);
    expect(document.meterMap.changes.single.meter.numerator, 4);

    final report = const SongValidator().validate(document);
    expect(report.hasFatalIssue, isFalse, reason: report.issues.toString());
  });

  test('a section never runs past the measures it was given', () {
    const chords = <TimelineChord>[
      TimelineChord(label: 'G', startSec: 0, endSec: 7.9),
    ];
    final result = _map(_analysis(bpm: 240, chords: chords));

    final draft = _success(result);
    final document = draft.document;
    final measureCount = document.measures.length;
    expect(measureCount, greaterThan(0));
    final section = document.sections.single;
    expect(section.endMeasureExclusive, lessThanOrEqualTo(measureCount));
  });
}

const List<String> _gcd = <String>['G', 'C', 'D'];
const String _merged = AudioSongDraftWarningCode.chordsMerged;
const String _fallback = AudioSongDraftWarningCode.tempoFallback;
const String _clamped = AudioSongDraftWarningCode.tempoClamped;
const String _review = AudioSongDraftWarningCode.reviewRequired;
const String _uncertain = AudioSongDraftWarningCode.strumDirectionUncertain;

AnalyzeResult _analysis({
  required double bpm,
  List<TimelineChord> chords = const <TimelineChord>[],
  List<TimelineStrum> strums = const <TimelineStrum>[],
  double durationSec = 8,
}) {
  return AnalyzeResult(
    durationSec: durationSec,
    bpm: bpm,
    chords: chords,
    strums: strums,
  );
}

AppResult<AudioSongDraft> _map(
  AnalyzeResult analysis, {
  Duration duration = const Duration(seconds: 8),
  String fileName = 'my-song.mp3',
}) {
  const mapper = AudioSongDraftMapper();
  return mapper.map(
    analysis: analysis,
    duration: duration,
    fileName: fileName,
    songId: SongId('audio-test'),
    sha256: 'b' * 64,
    importedAt: _importedAt,
  );
}

final DateTime _importedAt = DateTime.utc(2026, 9, 17);

String _code(AppResult<AudioSongDraft> result) {
  expect(result, isA<Failure<AudioSongDraft>>());
  return (result as Failure<AudioSongDraft>).error.code;
}

AudioSongDraft _success(AppResult<AudioSongDraft> result) {
  expect(result, isA<Success<AudioSongDraft>>());
  return (result as Success<AudioSongDraft>).value;
}

ChordTrack _chordTrack(AudioSongDraft draft) {
  return draft.document.tracks.whereType<ChordTrack>().single;
}

StrumTrack _strumTrack(AudioSongDraft draft) {
  return draft.document.tracks.whereType<StrumTrack>().single;
}
