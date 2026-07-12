import 'package:flutter/foundation.dart';

/// A recognised chord, e.g. C, Am, F#m, G.
///
/// v1 carries the display [label] only; root/quality decomposition (for
/// transpose/capo) can be added without touching consumers.
@immutable
class Chord {
  const Chord(this.label);

  /// Human display label ("C", "Am", "F#m").
  final String label;

  /// This chord with its root shifted by [semitones] (±), quality suffix kept.
  /// Used for **capo display**: the detector always hears concert pitch, but a
  /// capo'd player wants the SHAPE they're fretting, i.e. detected − capoFret.
  Chord transposed(int semitones) => Chord(transposeLabel(label, semitones));

  static const _sharpNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];
  static const _pitchClass = <String, int>{
    'C': 0, 'B#': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, //
    'E': 4, 'Fb': 4, 'F': 5, 'E#': 5, 'F#': 6, 'Gb': 6, 'G': 7, //
    'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11, 'Cb': 11,
  };

  /// Transpose a `" · "`-joined chord summary (e.g. "C · G · Am"), token by
  /// token, for capo display. Non-chord tokens (e.g. a fallback title) pass
  /// through untouched via [transposeLabel].
  static String transposeSummary(String summary, int semitones) {
    if (summary.isEmpty || semitones % 12 == 0) return summary;
    return summary
        .split(' · ')
        .map((t) => transposeLabel(t, semitones))
        .join(' · ');
  }

  /// Transpose a chord label's root by [semitones], preserving its quality
  /// suffix (spelled with sharps). Unparseable roots are returned untouched.
  /// A slash chord ("G/B") shifts BOTH the chord and its bass note (round 129).
  static String transposeLabel(String label, int semitones) {
    if (label.isEmpty || semitones % 12 == 0) return label;
    // Slash chord: transpose each side independently (the bass moves too).
    final slash = label.indexOf('/');
    if (slash >= 0) {
      return '${transposeLabel(label.substring(0, slash), semitones)}'
          '/${transposeLabel(label.substring(slash + 1), semitones)}';
    }
    // Root = first letter plus an optional accidental.
    var rootLen = 1;
    if (label.length > 1 && (label[1] == '#' || label[1] == 'b')) rootLen = 2;
    final pc = _pitchClass[label.substring(0, rootLen)];
    if (pc == null) return label;
    final shifted = ((pc + semitones) % 12 + 12) % 12;
    return _sharpNames[shifted] + label.substring(rootLen);
  }

  @override
  bool operator ==(Object other) => other is Chord && other.label == label;

  @override
  int get hashCode => label.hashCode;

  @override
  String toString() => label;
}
