// The shape lookup must resolve ENHARMONIC spellings.
//
// `ChordShapes.forLabel` is an exact-label map lookup, and the same lookup
// feeds the chord diagram, the chord detail view and the tap-to-hear audition
// (`features/learn/audio/chord_audition.dart`). Two parts of the app disagree
// about how to spell one pitch class:
//
//   - the live recogniser's dictionary spells roots with SHARPS only
//     (`chord_dictionary.dart`: C C# D D# E F F# G G# A A# B), so it can only
//     ever emit `A#`;
//   - the shape catalogue stores that chord under `Bb`, which is how a
//     guitarist names it.
//
// MEASURED consequence: a recognised Bb chord found NO diagram and NO audio,
// even though the app knows the shape perfectly well. The song validator also
// accepts both spellings, so an imported song written with `A#` hit the same
// hole.
//
// The catalogue's own mixed spelling is NOT the bug and is left alone: `Bb` but
// `C#m`, `F#m`, `G#m` is exactly conventional naming — those are the names real
// players and real charts use. The bug is that the LOOKUP insisted on one
// spelling. Display spelling is a separate question and deliberately not decided
// here; `ChordLabelNormalizer` already documents that choice as the UI's.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/chords/chord_shape.dart';

void main() {
  test('a sharp-spelled root finds the flat-spelled shape', () {
    // The only spelling the live recogniser can produce for this chord.
    final sharp = ChordShapes.forLabel('A#');
    final flat = ChordShapes.forLabel('Bb');
    expect(flat, isNotNull, reason: 'the catalogue stores this one as Bb');
    expect(
      sharp,
      isNotNull,
      reason: 'the recogniser can only emit A#, and it must find that shape',
    );
    expect(sharp!.frets, flat!.frets);
    expect(ChordShapes.has('A#'), isTrue);
  });

  test('a flat-spelled root finds a sharp-spelled shape', () {
    for (final (flatLabel, sharpLabel) in const <(String, String)>[
      ('Dbm', 'C#m'),
      ('Gbm', 'F#m'),
      ('Abm', 'G#m'),
    ]) {
      final viaFlat = ChordShapes.forLabel(flatLabel);
      final viaSharp = ChordShapes.forLabel(sharpLabel);
      expect(viaSharp, isNotNull, reason: '$sharpLabel is in the catalogue');
      expect(viaFlat, isNotNull, reason: '$flatLabel must resolve to it');
      expect(viaFlat!.frets, viaSharp!.frets);
    }
  });

  test('the returned shape keeps the label that was ASKED for', () {
    // The lookup resolves the SHAPE, it does not rename the chord. Anything
    // drawing a caption from the result must show what the caller asked about,
    // so the fallback cannot quietly relabel a detected chord.
    expect(ChordShapes.forLabel('A#')!.label, 'A#');
    expect(ChordShapes.forLabel('Bb')!.label, 'Bb');
  });

  test('the quality suffix is preserved across the fallback', () {
    // Only the ROOT is respelled; `m`, `7`, `maj7`, `sus4` must survive intact,
    // and a quality the catalogue does not have must stay absent rather than
    // resolve to some other chord.
    expect(ChordShapes.forLabel('A#m'), isNull);
    expect(ChordShapes.forLabel('Bbm'), isNull);
    expect(ChordShapes.forLabel('A#7'), isNull);
  });

  test('enharmonic resolution never invents a shape', () {
    // A root with no entry under either spelling stays null — the fallback adds
    // reach, never guesses.
    expect(ChordShapes.forLabel('D#'), isNull);
    expect(ChordShapes.forLabel('Eb'), isNull);
    expect(ChordShapes.forLabel('H'), isNull);
    expect(ChordShapes.forLabel(''), isNull);
  });

  test('allLabels still lists each shape ONCE, in its catalogue spelling', () {
    // The fallback must not double the catalogue: the library screen renders
    // `allLabels`, and a learner should not meet the same chord twice under two
    // names.
    final labels = ChordShapes.allLabels;
    expect(labels.where((l) => l == 'Bb').length, 1);
    expect(labels, isNot(contains('A#')));
    expect(labels.toSet().length, labels.length);
  });
}
