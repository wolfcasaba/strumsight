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

void main() {
  test('a G-C-D progression keeps its order and snaps onto the beat', () {
    final result = _map(
      _analysis(
        bpm: 120,
        chords: const <TimelineChord>[
          TimelineChord(label: 'G', startSec: 0, endSec: 2),
          TimelineChord(label: 'C', startSec: 2.02, endSec: 4),
          TimelineChord(label: 'D', startSec: 4, endSec: 6),
        ],
      ),
    );

    final draft = _success(result);
    final chords = _chordTrack(draft).events;
    expect(
      chords.map((event) => event.symbol.label).toList(),
      <String>['G', 'C', 'D'],
    );
    expect(chords[0].start, Duration.zero);
    expect(chords[0].duration, const Duration(seconds: 2));
    // 2.02 s rounds onto beat 4 at 120 BPM — the grid, not the raw time.
    expect(chords[1].start, const Duration(seconds: 2));
    expect(chords[2].start, const Duration(seconds: 4));
    expect(draft.bpm, 120);
    expect(draft.tempoEstimated, isTrue);
  });

  test('consecutive identical chords are merged into one event', () {
    final result = _map(
      _analysis(
        bpm: 120,
        chords: const <TimelineChord>[
          TimelineChord(label: 'G', startSec: 0, endSec: 1),
          TimelineChord(label: 'G', startSec: 1, endSec: 2),
          TimelineChord(label: 'C', startSec: 2, endSec: 3),
        ],
      ),
    );

    final draft = _success(result);
    final chords = _chordTrack(draft).events;
    expect(chords.length, 2);
    expect(chords.first.symbol.label, 'G');
    expect(chords.first.duration, const Duration(seconds: 2));
    expect(draft.warnings, contains(AudioSongDraftWarningCode.chordsMerged));
  });

  test('an empty chord timeline is a named failure, not a 0-event song', () {
    final result = _map(_analysis(bpm: 120));

    expect(result, isA<Failure<AudioSongDraft>>());
    expect(
      (result as Failure<AudioSongDraft>).error.code,
      AudioSongDraftFailureCode.noChords,
    );
  });

  test('a non-positive clip length is refused by name', () {
    final result = _map(
      _analysis(
        bpm: 120,
        chords: const <TimelineChord>[
          TimelineChord(label: 'G', startSec: 0, endSec: 2),
        ],
      ),
      duration: Duration.zero,
    );

    expect(
      (result as Failure<AudioSongDraft>).error.code,
      AudioSongDraftFailureCode.invalidDuration,
    );
  });

  test('a missing tempo falls back to 100 BPM and says so', () {
    final result = _map(
      _analysis(
        bpm: 0,
        chords: const <TimelineChord>[
          TimelineChord(label: 'G', startSec: 0, endSec: 2),
        ],
      ),
    );

    final draft = _success(result);
    expect(draft.bpm, AudioSongDraftMapper.fallbackTempoBpm);
    expect(draft.tempoEstimated, isFalse);
    expect(draft.warnings, contains(AudioSongDraftWarningCode.tempoFallback));
    expect(draft.document.tempoMap.changes.single.bpm.bpm, 100);
  });

  test('an implausible tempo is clamped into the practicable range', () {
    final result = _map(
      _analysis(
        bpm: 900,
        chords: const <TimelineChord>[
          TimelineChord(label: 'G', startSec: 0, endSec: 2),
        ],
      ),
    );

    final draft = _success(result);
    expect(draft.bpm, AudioSongDraftMapper.maxTempoBpm);
    expect(draft.warnings, contains(AudioSongDraftWarningCode.tempoClamped));
  });

  test('an uncertain strum is dropped instead of guessed', () {
    final result = _map(
      _analysis(
        bpm: 120,
        chords: const <TimelineChord>[
          TimelineChord(label: 'G', startSec: 0, endSec: 2),
        ],
        strums: const <TimelineStrum>[
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.5,
            confidence: 0.9,
          ),
          TimelineStrum(
            direction: StrumDirection.up,
            timeSec: 1,
            confidence: 0.2,
          ),
        ],
      ),
    );

    final draft = _success(result);
    final strums = _strumTrack(draft).events;
    expect(strums.length, 1);
    expect(strums.single.direction, StrumDirection.down);
    expect(strums.single.at, const Duration(milliseconds: 500));
    expect(
      draft.warnings,
      contains(AudioSongDraftWarningCode.strumDirectionUncertain),
    );
  });

  test('the draft carries audio provenance and passes validation', () {
    final result = _map(
      _analysis(
        bpm: 96,
        chords: const <TimelineChord>[
          TimelineChord(label: 'G', startSec: 0, endSec: 2),
          TimelineChord(label: 'C', startSec: 2, endSec: 4),
        ],
        strums: const <TimelineStrum>[
          TimelineStrum(
            direction: StrumDirection.down,
            timeSec: 0.25,
            confidence: 0.8,
          ),
        ],
      ),
      fileName: 'practice/My Song.mp3',
    );

    final draft = _success(result);
    final document = draft.document;
    expect(document.source.type, SongSourceType.audioAnalysis);
    expect(
      document.source.warningSummary,
      contains(AudioSongDraftWarningCode.reviewRequired),
    );
    expect(document.source.originalFileName, 'practice/My Song.mp3');
    expect(document.metadata.title, 'My Song');
    expect(document.metadata.tags, contains('draft'));
    expect(document.sections.single.name, 'My Song');
    expect(document.sections.single.startMeasure, 0);
    expect(
      document.sections.single.endMeasureExclusive,
      document.measures.length,
    );
    expect(document.meterMap.changes.single.meter.numerator, 4);

    final report = const SongValidator().validate(document);
    expect(report.hasFatalIssue, isFalse, reason: report.issues.toString());
  });

  test('a section never runs past the measures it was given', () {
    final result = _map(
      _analysis(
        bpm: 240,
        chords: const <TimelineChord>[
          TimelineChord(label: 'G', startSec: 0, endSec: 7.9),
        ],
      ),
    );

    final draft = _success(result);
    final document = draft.document;
    expect(document.measures, isNotEmpty);
    expect(
      document.sections.single.endMeasureExclusive,
      lessThanOrEqualTo(document.measures.length),
    );
  });
}

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
  return const AudioSongDraftMapper().map(
    analysis: analysis,
    duration: duration,
    fileName: fileName,
    songId: SongId('audio-test'),
    sha256: 'b' * 64,
    importedAt: DateTime.utc(2026, 9, 17),
  );
}

AudioSongDraft _success(AppResult<AudioSongDraft> result) {
  expect(result, isA<Success<AudioSongDraft>>());
  return (result as Success<AudioSongDraft>).value;
}

ChordTrack _chordTrack(AudioSongDraft draft) =>
    draft.document.tracks.whereType<ChordTrack>().single;

StrumTrack _strumTrack(AudioSongDraft draft) =>
    draft.document.tracks.whereType<StrumTrack>().single;
