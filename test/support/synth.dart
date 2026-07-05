// Synthesized guitar-like PCM for DSP tests (shared by R7–R9 chunks).
// Deterministic: no Random — tests must be reproducible.
import 'dart:math' as math;
import 'dart:typed_data';

/// A note as fundamental + decaying harmonic series (1, 1/2, 1/3 …) — close
/// enough to a plucked string's spectrum for chroma/onset testing.
Float64List harmonicNote({
  required double freq,
  required double seconds,
  int sampleRate = 44100,
  double amp = 0.2,
  int harmonics = 6,
  double decayPerSecond = 1.5,
}) {
  final n = (seconds * sampleRate).round();
  final out = Float64List(n);
  for (var h = 1; h <= harmonics; h++) {
    final f = freq * h;
    if (f > sampleRate / 2) break;
    final a = amp / h;
    final w = 2 * math.pi * f / sampleRate;
    for (var i = 0; i < n; i++) {
      final env = math.exp(-decayPerSecond * i / sampleRate);
      out[i] += a * env * math.sin(w * i);
    }
  }
  return out;
}

/// Mix several notes, optionally staggering each start (used for strums: a
/// down-strum = low strings first, up-strum = high strings first).
Float64List mixNotes(
  List<Float64List> notes, {
  List<int>? startOffsets,
  int? length,
}) {
  final offs = startOffsets ?? List.filled(notes.length, 0);
  var end = 0;
  for (var i = 0; i < notes.length; i++) {
    end = math.max(end, offs[i] + notes[i].length);
  }
  final out = Float64List(length ?? end);
  for (var i = 0; i < notes.length; i++) {
    final note = notes[i];
    final off = offs[i];
    for (var j = 0; j < note.length && off + j < out.length; j++) {
      out[off + j] += note[j];
    }
  }
  return out;
}

/// A guitar-voiced chord (root-3rd-5th around octave 3) as simultaneous notes.
Float64List chordSignal(
  List<double> freqs, {
  double seconds = 1.0,
  int sampleRate = 44100,
}) =>
    mixNotes([
      for (final f in freqs)
        harmonicNote(freq: f, seconds: seconds, sampleRate: sampleRate),
    ]);

/// Common chord voicings (Hz, standard tuning region).
const cMajorFreqs = [130.81, 164.81, 196.00]; // C3 E3 G3
const gMajorFreqs = [98.00, 123.47, 196.00]; // G2 B2 G3
const aMinorFreqs = [110.00, 130.81, 164.81]; // A2 C3 E3
const fMajorFreqs = [87.31, 130.81, 174.61]; // F2 C3 F3 (F power-ish + third)

/// Slice [signal] into consecutive frames of [window] advancing by [hop].
Iterable<Float64List> frames(Float64List signal, int window, int hop) sync* {
  for (var start = 0; start + window <= signal.length; start += hop) {
    yield signal.sublist(start, start + window);
  }
}
