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
  // 10 ms cosine release so the note doesn't END with a click — a hard
  // cutoff is a broadband transient that reads as a (false) onset.
  final ramp = math.min((0.010 * sampleRate).round(), n);
  for (var i = 0; i < ramp; i++) {
    out[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / ramp);
  }
  return out;
}

/// A note with an arbitrary per-harmonic gain — timbre/EQ colouration for
/// whitening tests (round 70): phone mics roll off bass, bodies resonate.
/// [gain] receives the harmonic index (1-based) and its frequency in Hz.
Float64List colouredNote({
  required double freq,
  required double seconds,
  required double Function(int h, double f) gain,
  int sampleRate = 44100,
  int harmonics = 8,
  double decayPerSecond = 1.5,
}) {
  final n = (seconds * sampleRate).round();
  final out = Float64List(n);
  for (var h = 1; h <= harmonics; h++) {
    final f = freq * h;
    if (f > sampleRate / 2) break;
    final a = gain(h, f);
    final w = 2 * math.pi * f / sampleRate;
    for (var i = 0; i < n; i++) {
      final env = math.exp(-decayPerSecond * i / sampleRate);
      out[i] += a * env * math.sin(w * i);
    }
  }
  final ramp = math.min((0.010 * sampleRate).round(), n);
  for (var i = 0; i < ramp; i++) {
    out[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / ramp);
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
  double amp = 0.2,
  double decayPerSecond = 1.5,
}) => mixNotes([
  for (final f in freqs)
    harmonicNote(
      freq: f,
      seconds: seconds,
      sampleRate: sampleRate,
      amp: amp,
      decayPerSecond: decayPerSecond,
    ),
]);

/// Common chord voicings (Hz, standard tuning region).
const cMajorFreqs = [130.81, 164.81, 196.00]; // C3 E3 G3
const gMajorFreqs = [98.00, 123.47, 196.00]; // G2 B2 G3
const aMinorFreqs = [110.00, 130.81, 164.81]; // A2 C3 E3
// F2 A2 C3 — a real root-third-fifth triad. (The old [F2 C3 F3] value was a
// THIRDLESS power chord mislabelled as F major; with no third in the signal,
// F vs Csus4 is genuinely undecidable and power-5 is deliberately out of the
// chord vocabulary — chunk 012.)
const fMajorFreqs = [87.31, 110.00, 130.81];

/// A constant-amplitude tone with sinusoidal VIBRATO (frequency modulation).
/// After a short attack the amplitude never changes — so a correct onset
/// detector must stay silent while the pitch wobbles (the SuperFlux paper's
/// motivating false-positive case for plain spectral flux).
Float64List vibratoNote({
  required double freq,
  required double seconds,
  double vibratoCents = 30,
  double vibratoHz = 6,
  int sampleRate = 44100,
  double amp = 0.2,
  double attackSeconds = 0.02,
}) {
  final n = (seconds * sampleRate).round();
  final out = Float64List(n);
  final depth = math.pow(2.0, vibratoCents / 1200.0) - 1.0;
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final f = freq * (1 + depth * math.sin(2 * math.pi * vibratoHz * t));
    phase += 2 * math.pi * f / sampleRate;
    final attack = t >= attackSeconds ? 1.0 : t / attackSeconds;
    out[i] = amp * attack * math.sin(phase);
  }
  final ramp = math.min((0.010 * sampleRate).round(), n);
  for (var i = 0; i < ramp; i++) {
    out[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / ramp);
  }
  return out;
}

/// Slice [signal] into consecutive frames of [window] advancing by [hop].
Iterable<Float64List> frames(Float64List signal, int window, int hop) sync* {
  for (var start = 0; start + window <= signal.length; start += hop) {
    yield signal.sublist(start, start + window);
  }
}

/// Open-string fundamentals E2..E4 (low → high) — strum test voicing.
const openStrings = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63];

/// A single strum: strings staggered by [staggerMs] each. Down-strum hits the
/// LOW strings first ([lowFirst] = true); up-strum the high strings first.
Float64List strumSignal({
  required bool lowFirst,
  double staggerMs = 8,
  double seconds = 0.8,
  int sampleRate = 44100,
  double leadSilenceSeconds = 0.1,
}) {
  final lead = (leadSilenceSeconds * sampleRate).round();
  final stagger = (staggerMs / 1000 * sampleRate).round();
  final order = lowFirst ? openStrings : openStrings.reversed.toList();
  final notes = [
    for (final f in order)
      harmonicNote(
        freq: f,
        seconds: seconds,
        sampleRate: sampleRate,
        amp: 0.12,
      ),
  ];
  final offsets = [for (var i = 0; i < notes.length; i++) lead + i * stagger];
  return mixNotes(notes, startOffsets: offsets);
}

/// Repeated strums [gapSeconds] apart that each RING for [ringSeconds], so
/// consecutive strums OVERLAP — the previous strum is still sounding when the
/// next lands. This is the ring-out condition that corrupts absolute sub-band
/// direction cues (fixed in round 59 by onset-relative baseline subtraction).
Float64List overlappingStrums({
  required List<bool> lowFirstPerStrum,
  double gapSeconds = 0.25,
  double ringSeconds = 0.5,
  double staggerMs = 8,
  int sampleRate = 44100,
  double leadSilenceSeconds = 0.1,
}) {
  final gap = (gapSeconds * sampleRate).round();
  final lead = (leadSilenceSeconds * sampleRate).round();
  final parts = <Float64List>[];
  final offsets = <int>[];
  for (var i = 0; i < lowFirstPerStrum.length; i++) {
    parts.add(
      strumSignal(
        lowFirst: lowFirstPerStrum[i],
        staggerMs: staggerMs,
        seconds: ringSeconds,
        sampleRate: sampleRate,
        leadSilenceSeconds: 0,
      ),
    );
    offsets.add(lead + i * gap);
  }
  final total = offsets.last + parts.last.length + (0.2 * sampleRate).round();
  return mixNotes(parts, startOffsets: offsets, length: total);
}

/// [count] identical strums, [gapSeconds] apart (onset-to-onset).
Float64List strumPattern({
  required List<bool> lowFirstPerStrum,
  double gapSeconds = 0.5,
  int sampleRate = 44100,
}) {
  final one = (gapSeconds * sampleRate).round();
  final parts = <Float64List>[];
  final offsets = <int>[];
  for (var i = 0; i < lowFirstPerStrum.length; i++) {
    parts.add(
      strumSignal(
        lowFirst: lowFirstPerStrum[i],
        sampleRate: sampleRate,
        seconds: gapSeconds * 0.9,
        leadSilenceSeconds: 0,
      ),
    );
    offsets.add((i * one) + (0.1 * sampleRate).round());
  }
  final total = offsets.last + parts.last.length + (0.2 * sampleRate).round();
  return mixNotes(parts, startOffsets: offsets, length: total);
}

/// A plucked string by **Karplus–Strong** physical modelling (E14-R28 / H3):
/// a short broadband excitation fed through a tuned delay line with a one-pole
/// lowpass in the feedback path. Unlike [harmonicNote] — a sum of ideal sine
/// partials with a single exponential envelope — KS produces the *inharmonic
/// attack, per-partial decay and slight detune* of a real string, which is why
/// the H3 report uses it: the chord latch's failure to engage was reported on
/// real guitar audio, and a sum of perfect sinusoids is exactly the input that
/// cannot reproduce it.
///
/// Deterministic by construction: the excitation comes from a fixed 32-bit LCG
/// seeded by [seed], never from `dart:math`'s `Random`, so two runs (and two
/// machines) produce bit-identical samples.
Float64List karplusStrongNote({
  required double freq,
  required double seconds,
  int sampleRate = 44100,
  double amp = 0.2,
  double damping = 0.996,
  int seed = 1,
}) {
  final n = (seconds * sampleRate).round();
  final out = Float64List(n);
  if (n == 0) return out;
  final delay = math.max(2, (sampleRate / freq).round());
  final buf = Float64List(delay);
  // 32-bit LCG (Numerical Recipes constants) → white noise burst in -1..1.
  var state = (seed * 2654435761) & 0xFFFFFFFF;
  int next() {
    state = (1664525 * state + 1013904223) & 0xFFFFFFFF;
    return state;
  }

  for (var i = 0; i < delay; i++) {
    buf[i] = (next() / 0xFFFFFFFF) * 2 - 1;
  }
  var idx = 0;
  for (var i = 0; i < n; i++) {
    out[i] = amp * buf[idx];
    final nextIdx = (idx + 1) % delay;
    buf[idx] = damping * 0.5 * (buf[idx] + buf[nextIdx]);
    idx = nextIdx;
  }
  // Same 10 ms cosine release as [harmonicNote]: a hard cutoff is a broadband
  // transient that reads as a (false) onset.
  final ramp = math.min((0.010 * sampleRate).round(), n);
  for (var i = 0; i < ramp; i++) {
    out[n - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / ramp);
  }
  return out;
}

/// A strummed chord of [freqs] played as Karplus–Strong strings, each string
/// starting [strumSpreadSeconds] after the previous one (a down-strum's
/// low-to-high rake). Each string gets its OWN excitation seed, so the strings
/// are uncorrelated the way six real strings are — while the whole signal
/// stays reproducible.
Float64List karplusStrongChord(
  List<double> freqs, {
  double seconds = 1.5,
  int sampleRate = 44100,
  double amp = 0.2,
  double damping = 0.996,
  double strumSpreadSeconds = 0.012,
  int seed = 1,
}) {
  final step = (strumSpreadSeconds * sampleRate).round();
  return mixNotes(
    [
      for (var i = 0; i < freqs.length; i++)
        karplusStrongNote(
          freq: freqs[i],
          seconds: seconds,
          sampleRate: sampleRate,
          amp: amp,
          damping: damping,
          seed: seed + i,
        ),
    ],
    startOffsets: [for (var i = 0; i < freqs.length; i++) i * step],
  );
}

/// [count] Karplus–Strong strums of the same voicing, [gapSeconds] apart
/// (onset to onset) — the "sustained chord, re-struck" input the chord latch
/// is supposed to hold through.
Float64List karplusStrongStrumPattern(
  List<double> freqs, {
  int count = 4,
  double gapSeconds = 0.6,
  int sampleRate = 44100,
  double amp = 0.2,
  double damping = 0.996,
  int seed = 1,
}) {
  final step = (gapSeconds * sampleRate).round();
  final parts = <Float64List>[
    for (var i = 0; i < count; i++)
      karplusStrongChord(
        freqs,
        seconds: gapSeconds * 1.4,
        sampleRate: sampleRate,
        amp: amp,
        damping: damping,
        seed: seed + i * 100,
      ),
  ];
  return mixNotes(
    parts,
    startOffsets: [for (var i = 0; i < count; i++) i * step],
  );
}
