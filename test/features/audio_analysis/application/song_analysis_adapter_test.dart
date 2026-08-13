import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  const adapter = SongAnalysisAdapter();

  test(
    'keeps display pitch distinct from capo and transposition concert pitch',
    () {
      for (final cell
          in <({int capo, int transpose, int display, int concert})>[
            (capo: 0, transpose: 0, display: 60, concert: 60),
            (capo: 0, transpose: -2, display: 58, concert: 58),
            (capo: 2, transpose: 0, display: 60, concert: 62),
            (capo: 2, transpose: -2, display: 58, concert: 60),
            (capo: 5, transpose: 0, display: 60, concert: 65),
            (capo: 5, transpose: -2, display: 58, concert: 63),
          ]) {
        final result = adapter.toAnalysisTarget(
          _snapshot(capo: cell.capo, transposition: cell.transpose),
        );
        expect(result.pitches.single.displayMidi, cell.display);
        expect(result.pitches.single.concertMidi, cell.concert);
        expect(result.target.expectedNotes, <int>[cell.concert]);
      }
    },
  );

  test('applies backing offset after speed-scaled media time', () {
    final baseline = adapter.toAnalysisTarget(_snapshot());
    final offset = adapter.toAnalysisTarget(
      _snapshot(offset: const Duration(milliseconds: 250)),
    );
    final slowed = adapter.toAnalysisTarget(
      _snapshot(offset: const Duration(milliseconds: 250), speed: .75),
    );
    Duration noteTime(SongAnalysisTarget result) =>
        result.target.expectedEvents.first.time;
    expect(noteTime(baseline), const Duration(seconds: 1));
    expect(noteTime(offset), const Duration(milliseconds: 1250));
    expect(noteTime(slowed), const Duration(microseconds: 1583333));
  });

  test(
    'preserves display and concert chords through transposition and capo',
    () {
      for (final cell
          in <
            ({
              String input,
              int capo,
              int transpose,
              String display,
              String concert,
            })
          >[
            (input: 'C', capo: 0, transpose: 0, display: 'C', concert: 'C'),
            (input: 'F#', capo: 0, transpose: -2, display: 'E', concert: 'E'),
            (input: 'F#', capo: 2, transpose: 0, display: 'F#', concert: 'G#'),
            (input: 'Bb', capo: 2, transpose: -2, display: 'G#', concert: 'A#'),
            (input: 'Bb', capo: 5, transpose: 0, display: 'Bb', concert: 'D#'),
            (input: 'C', capo: 5, transpose: -2, display: 'A#', concert: 'D#'),
          ]) {
        final result = adapter.toAnalysisTarget(
          _chordSnapshot(
            chord: cell.input,
            capo: cell.capo,
            transposition: cell.transpose,
          ),
        );

        expect(result.chords.single.displayChord, cell.display);
        expect(result.chords.single.concertChord, cell.concert);
        expect(result.target.expectedChords, <String>[cell.concert]);
      }
    },
  );
}

SongReferenceSnapshot _snapshot({
  int capo = 0,
  int transposition = 0,
  Duration offset = Duration.zero,
  double speed = 1,
}) => SongReferenceSnapshot(
  documentId: 'song',
  documentVersion: 2,
  sectionId: 'verse',
  beatGrid: const <Duration>[],
  events: <SongReferenceEvent>[
    SongReferenceEvent(
      id: 'note',
      time: const Duration(seconds: 1),
      displayMidi: 60,
    ),
  ],
  capo: capo,
  transposition: transposition,
  backingOffset: offset,
  playbackSpeed: speed,
);

SongReferenceSnapshot _chordSnapshot({
  required String chord,
  required int capo,
  required int transposition,
}) => SongReferenceSnapshot(
  documentId: 'song',
  documentVersion: 2,
  sectionId: 'verse',
  beatGrid: const <Duration>[],
  events: <SongReferenceEvent>[
    SongReferenceEvent(
      id: 'chord',
      time: const Duration(seconds: 1),
      displayChord: chord,
    ),
  ],
  capo: capo,
  transposition: transposition,
);
