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
