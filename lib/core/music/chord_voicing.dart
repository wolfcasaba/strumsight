import 'dart:math' as math;

import 'guitar_strings.dart';

/// The pitches a fingering actually sounds (ADR 0535 D1).
///
/// A chord diagram is six fret numbers, low-E → high-E (`-1` muted, `0`
/// open, `>0` pressed). Sounding pitch = open-string MIDI + fret. Pure music
/// maths, shared by audition (what the editor plays back) and any future
/// voicing-aware detector display.
final class ChordVoicing {
  ChordVoicing._();

  /// MIDI notes of the strings that sound, low → high. Muted strings are
  /// skipped; a fret outside 0…24 is treated as muted rather than guessed.
  static List<int> midiNotes(
    List<int> frets, {
    List<GuitarString> strings = GuitarStrings.standard,
  }) {
    final count = math.min(frets.length, strings.length);
    return [
      for (var i = 0; i < count; i++)
        if (frets[i] >= 0 && frets[i] <= 24) strings[i].midi + frets[i],
    ];
  }

  /// Frequencies (Hz) of [midiNotes] under concert pitch [a4].
  static List<double> frequencies(
    List<int> frets, {
    int a4 = 440,
    List<GuitarString> strings = GuitarStrings.standard,
  }) => [
    for (final midi in midiNotes(frets, strings: strings))
      a4 * math.pow(2, (midi - 69) / 12).toDouble(),
  ];
}
