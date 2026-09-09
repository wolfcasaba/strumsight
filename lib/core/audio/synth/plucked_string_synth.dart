import 'dart:math' as math;
import 'dart:typed_data';

import '../codec/wav_encoder.dart';

/// Pure-Dart plucked-string synthesis for chord audition (ADR 0535 D1).
///
/// Karplus–Strong: a noise burst circulating in a delay line of
/// `sampleRate / frequency` samples through a two-tap averaging filter. The
/// result decays like a real string (bright attack, darkening tail), which is
/// what makes a tapped chord in the song editor *sound* like the fingering
/// the diagram shows — not the soft sine pad of jam mode.
///
/// Deterministic on purpose: the excitation noise comes from a fixed-seed
/// linear congruential generator, never `Random`, so the same request always
/// yields byte-identical PCM (cache keys, golden bytes and tests all rely on
/// it). Nothing here touches Flutter or a platform channel.
final class PluckedStringSynth {
  PluckedStringSynth._();

  /// The excitation seed — fixed so audition output is reproducible.
  static const int noiseSeed = 0x5EED;

  /// Per-string onset spacing of one strum. 18 ms across six strings is a
  /// relaxed down-stroke (~90 ms low-E → high-E); a real strum measures
  /// 40–120 ms depending on tempo, so the middle of that band reads as a
  /// natural gesture rather than a machine chord.
  static const double defaultStaggerMs = 18;

  /// One plucked string at [freqHz] as float samples in −1…1.
  ///
  /// [decay] is the per-sample loop gain (< 1); 0.996 at 44.1 kHz gives a
  /// ~1.5 s audible tail for a low string. Frequencies above Nyquist/2 or
  /// non-positive are rendered silent rather than aliased.
  static Float64List pluck({
    required double freqHz,
    required double seconds,
    int sampleRate = 44100,
    double amp = 0.5,
    double decay = 0.996,
  }) {
    final n = math.max(0, (seconds * sampleRate).round());
    final out = Float64List(n);
    if (n == 0 || freqHz <= 0 || freqHz >= sampleRate / 4) return out;
    final period = (sampleRate / freqHz).round();
    if (period < 2) return out;
    final ring = Float64List(period);
    var state = noiseSeed;
    for (var i = 0; i < period; i++) {
      // Numerical Recipes LCG — good enough for an excitation burst.
      state = (1664525 * state + 1013904223) & 0xFFFFFFFF;
      ring[i] = (state / 0xFFFFFFFF) * 2 - 1;
    }
    var idx = 0;
    var prev = ring[period - 1];
    for (var i = 0; i < n; i++) {
      final cur = ring[idx];
      final next = 0.5 * (cur + prev) * decay;
      ring[idx] = next;
      prev = cur;
      out[i] = cur * amp;
      idx = (idx + 1) % period;
    }
    return out;
  }

  /// The sample index at which each of [count] strings starts sounding.
  ///
  /// Strings are indexed low → high. A down-stroke sweeps low → high, so the
  /// lowest string starts first; an up-stroke is the reverse. Pure — this is
  /// the unit-tested contract of the stroke direction.
  static List<int> strumOnsets({
    required int count,
    required bool downstroke,
    double staggerMs = defaultStaggerMs,
    int sampleRate = 44100,
  }) {
    final step = (staggerMs / 1000 * sampleRate).round();
    return [
      for (var i = 0; i < count; i++)
        (downstroke ? i : count - 1 - i) * step,
    ];
  }

  /// A strummed chord: [freqs] (low → high) plucked with the direction's
  /// stagger, summed and peak-normalised to [amp].
  static Int16List strumPcm({
    required List<double> freqs,
    required bool downstroke,
    double seconds = 1.6,
    double staggerMs = defaultStaggerMs,
    int sampleRate = 44100,
    double amp = 0.6,
  }) {
    final n = math.max(0, (seconds * sampleRate).round());
    final mix = Float64List(n);
    if (freqs.isEmpty || n == 0) return Int16List(n);
    final onsets = strumOnsets(
      count: freqs.length,
      downstroke: downstroke,
      staggerMs: staggerMs,
      sampleRate: sampleRate,
    );
    for (var s = 0; s < freqs.length; s++) {
      final start = onsets[s];
      if (start >= n) continue;
      final voice = pluck(
        freqHz: freqs[s],
        seconds: (n - start) / sampleRate,
        sampleRate: sampleRate,
        amp: 1,
      );
      for (var i = 0; i < voice.length; i++) {
        mix[start + i] += voice[i];
      }
    }
    // Short fade-out so a cut-off tail never clicks.
    final release = math.min(n, (0.03 * sampleRate).round());
    for (var i = n - release; i < n; i++) {
      mix[i] *= (n - i) / release;
    }
    var peak = 0.0;
    for (final v in mix) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    final gain = peak > 0 ? amp / peak : 0.0;
    final pcm = Int16List(n);
    for (var i = 0; i < n; i++) {
      pcm[i] = (mix[i] * gain * 32767).clamp(-32768.0, 32767.0).toInt();
    }
    return pcm;
  }

  /// [strumPcm] wrapped as a playable 16-bit mono WAV.
  static Uint8List strumWav({
    required List<double> freqs,
    required bool downstroke,
    double seconds = 1.6,
    double staggerMs = defaultStaggerMs,
    int sampleRate = 44100,
    double amp = 0.6,
  }) => pcmToWav(
    strumPcm(
      freqs: freqs,
      downstroke: downstroke,
      seconds: seconds,
      staggerMs: staggerMs,
      sampleRate: sampleRate,
      amp: amp,
    ),
    sampleRate,
  );
}
