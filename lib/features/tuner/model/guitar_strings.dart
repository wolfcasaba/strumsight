import 'dart:math' as math;

/// One standard-tuning guitar string (round 84 — GuitarTuna-class tuner UX).
class GuitarString {
  const GuitarString(this.label, this.midi);

  /// Display label, e.g. `E2` (6th string) … `E4` (1st string).
  final String label;

  /// MIDI note of the string in standard tuning.
  final int midi;

  /// The string's frequency under concert-pitch reference [a4].
  double frequencyHz(int a4) => a4 * math.pow(2, (midi - 69) / 12).toDouble();
}

/// Standard tuning E-A-D-G-B-E and the nearest-string mapping the tuner
/// screen uses to highlight which string is being tuned.
class GuitarStrings {
  GuitarStrings._();

  /// Low → high: E2 A2 D3 G3 B3 E4.
  static const List<GuitarString> standard = [
    GuitarString('E2', 40),
    GuitarString('A2', 45),
    GuitarString('D3', 50),
    GuitarString('G3', 55),
    GuitarString('B3', 59),
    GuitarString('E4', 64),
  ];

  /// How far (in semitones) a pitch may sit from a string and still be
  /// claimed as "tuning that string". Beyond this (voice, whistling, a
  /// harmonic) no chip lights up — better honest than wrong.
  static const double maxSemitoneDistance = 5;

  /// The string nearest to [freqHz] by LOG distance (pitch is geometric —
  /// the boundary between two strings is their geometric mean), or null for
  /// silence / far-out-of-range pitches. Searches [strings] (defaults to
  /// standard tuning; pass the selected tuning's set — round 89).
  static GuitarString? nearest(double freqHz,
      {int a4 = 440, List<GuitarString> strings = standard}) {
    if (freqHz <= 0) return null;
    GuitarString? best;
    var bestDist = double.infinity;
    for (final s in strings) {
      final dist =
          (12 * (math.log(freqHz / s.frequencyHz(a4)) / math.ln2)).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = s;
      }
    }
    return bestDist <= maxSemitoneDistance ? best : null;
  }

  /// Signed cents of [freqHz] against a SPECIFIC string (round 91 — manual
  /// mode): negative = flat, positive = sharp. Unlike the chromatic reading
  /// this stays anchored to the target even a whole semitone away.
  static double centsTo(GuitarString s, double freqHz, {int a4 = 440}) =>
      1200 * (math.log(freqHz / s.frequencyHz(a4)) / math.ln2);
}
