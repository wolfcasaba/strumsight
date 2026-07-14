import 'dart:math' as math;
import 'dart:typed_data';

/// Median-filtering Harmonic-Percussive Source Separation (Fitzgerald 2010).
///
/// Chord detection reads a **magnitude spectrogram** `S` (T frames × F bins).
/// On full-band audio with drums, broadband percussive transients (a snare /
/// kick hit) dump energy into every frequency bin of a single time frame,
/// smearing the chroma. HPSS exploits the geometry of the two source classes:
///
/// * **Harmonic** content is *horizontally* smooth — a held note is a ridge
///   that persists across many TIME frames at a fixed frequency bin.
/// * **Percussive** content is *vertically* smooth — a drum hit is a ridge
///   that spans many FREQUENCY bins within a single TIME frame.
///
/// So a horizontal median filter (along time, fixed bin) estimates the
/// harmonic component `H`, a vertical median filter (along frequency, fixed
/// frame) estimates the percussive component `P`, and a soft Wiener-ish mask
/// `H^p / (H^p + P^p)` re-weights `S` to keep the harmonics and suppress the
/// drums before chroma extraction. A hard binary variant (`H > P`) is also
/// exposed.
///
/// Pure & deterministic — only `dart:typed_data` + `dart:math`. Median windows
/// are clamped at the edges. Input is never mutated; all methods allocate a
/// fresh result.
abstract final class Hpss {
  /// Harmonic-enhanced spectrogram = `S ⊙ softHarmonicMask(S)`.
  ///
  /// [spectrogram] is a `T`-frame × `F`-bin magnitude spectrogram (a
  /// `List<Float64List>`, each inner list one frame's bins — all frames the
  /// same length). Returns a NEW `List<Float64List>` of the same dimensions;
  /// the input is not touched.
  ///
  /// * [timeMedian] — length (in frames) of the HORIZONTAL median window that
  ///   estimates the harmonic component. Odd values keep the window centred.
  /// * [freqMedian] — length (in bins) of the VERTICAL median window that
  ///   estimates the percussive component.
  /// * [power] — the mask exponent `p` (Fitzgerald uses 2). Higher `p` sharpens
  ///   the harmonic/percussive decision toward a hard mask.
  ///
  /// Empty input, a single frame, or a single bin are handled gracefully — a
  /// plain copy is returned (nothing to separate along the degenerate axis).
  static List<Float64List> harmonicEnhance(
    List<Float64List> spectrogram, {
    int timeMedian = 17,
    int freqMedian = 17,
    double power = 2.0,
  }) {
    final t = spectrogram.length;
    if (t == 0) return const [];
    final f = spectrogram[0].length;
    // Degenerate: with <2 frames there is no time context, and with <2 bins no
    // frequency context — HPSS is meaningless, so pass the input through
    // unchanged (a fresh deep copy; the input is never handed back).
    if (t < 2 || f < 2) {
      return [for (final row in spectrogram) Float64List.fromList(row)];
    }

    final harm = _harmonicMedian(spectrogram, t, f, timeMedian);
    final perc = _percussiveMedian(spectrogram, t, f, freqMedian);

    final out = List<Float64List>.generate(t, (_) => Float64List(f));
    for (var i = 0; i < t; i++) {
      final src = spectrogram[i];
      final h = harm[i];
      final p = perc[i];
      final o = out[i];
      for (var j = 0; j < f; j++) {
        final hp = math.pow(h[j], power).toDouble();
        final pp = math.pow(p[j], power).toDouble();
        final denom = hp + pp;
        final mask = denom > 0 ? hp / denom : 0.0;
        o[j] = src[j] * mask;
      }
    }
    return out;
  }

  /// The soft harmonic mask `H^p / (H^p + P^p)` in `0..1` for every cell.
  ///
  /// Multiply it elementwise with the input spectrogram to reproduce
  /// [harmonicEnhance]. Same dimensions as [spectrogram]; input untouched. On a
  /// degenerate axis (≤1 frame or ≤1 bin) an all-ones mask is returned.
  static List<Float64List> harmonicMask(
    List<Float64List> spectrogram, {
    int timeMedian = 17,
    int freqMedian = 17,
    double power = 2.0,
  }) {
    final t = spectrogram.length;
    if (t == 0) return const [];
    final f = spectrogram[0].length;
    final out = List<Float64List>.generate(t, (_) => Float64List(f));
    // Degenerate axis → identity (all-ones) mask, so S ⊙ mask == S.
    if (t < 2 || f < 2) {
      for (final row in out) {
        row.fillRange(0, row.length, 1.0);
      }
      return out;
    }

    final harm = _harmonicMedian(spectrogram, t, f, timeMedian);
    final perc = _percussiveMedian(spectrogram, t, f, freqMedian);
    for (var i = 0; i < t; i++) {
      final h = harm[i];
      final p = perc[i];
      final o = out[i];
      for (var j = 0; j < f; j++) {
        final hp = math.pow(h[j], power).toDouble();
        final pp = math.pow(p[j], power).toDouble();
        final denom = hp + pp;
        o[j] = denom > 0 ? hp / denom : 0.0;
      }
    }
    return out;
  }

  /// The HARD binary harmonic mask (`H > P` → 1, else 0), the classic
  /// Fitzgerald hard-mask variant. Same dimensions as [spectrogram]; input
  /// untouched. Ties (`H == P`) resolve to 0 (not harmonic).
  static List<Float64List> hardHarmonicMask(
    List<Float64List> spectrogram, {
    int timeMedian = 17,
    int freqMedian = 17,
  }) {
    final t = spectrogram.length;
    if (t == 0) return const [];
    final f = spectrogram[0].length;
    final out = List<Float64List>.generate(t, (_) => Float64List(f));
    // Degenerate axis → identity (all-ones) mask, so S ⊙ mask == S.
    if (t < 2 || f < 2) {
      for (final row in out) {
        row.fillRange(0, row.length, 1.0);
      }
      return out;
    }

    final harm = _harmonicMedian(spectrogram, t, f, timeMedian);
    final perc = _percussiveMedian(spectrogram, t, f, freqMedian);
    for (var i = 0; i < t; i++) {
      final h = harm[i];
      final p = perc[i];
      final o = out[i];
      for (var j = 0; j < f; j++) {
        o[j] = h[j] > p[j] ? 1.0 : 0.0;
      }
    }
    return out;
  }

  /// Harmonic estimate: for each bin, the median of the input over a horizontal
  /// (time) window of length [len], clamped at the frame edges.
  static List<Float64List> _harmonicMedian(
    List<Float64List> s,
    int t,
    int f,
    int len,
  ) {
    final out = List<Float64List>.generate(t, (_) => Float64List(f));
    if (t < 2 || len <= 1) {
      for (var i = 0; i < t; i++) {
        out[i].setAll(0, s[i]);
      }
      return out;
    }
    final half = len ~/ 2;
    final win = Float64List(len);
    for (var j = 0; j < f; j++) {
      for (var i = 0; i < t; i++) {
        var n = 0;
        for (var k = i - half; k <= i + half; k++) {
          final ci = k < 0 ? 0 : (k >= t ? t - 1 : k); // clamp
          win[n++] = s[ci][j];
        }
        out[i][j] = _median(win, n);
      }
    }
    return out;
  }

  /// Percussive estimate: for each frame, the median of the input over a
  /// vertical (frequency) window of length [len], clamped at the bin edges.
  static List<Float64List> _percussiveMedian(
    List<Float64List> s,
    int t,
    int f,
    int len,
  ) {
    final out = List<Float64List>.generate(t, (_) => Float64List(f));
    if (f < 2 || len <= 1) {
      for (var i = 0; i < t; i++) {
        out[i].setAll(0, s[i]);
      }
      return out;
    }
    final half = len ~/ 2;
    final win = Float64List(len);
    for (var i = 0; i < t; i++) {
      final row = s[i];
      final orow = out[i];
      for (var j = 0; j < f; j++) {
        var n = 0;
        for (var k = j - half; k <= j + half; k++) {
          final cj = k < 0 ? 0 : (k >= f ? f - 1 : k); // clamp
          win[n++] = row[cj];
        }
        orow[j] = _median(win, n);
      }
    }
    return out;
  }

  /// Median of the first [n] entries of [buf]. Copies into a scratch list so
  /// the caller's buffer is left intact, sorts, and averages the two middle
  /// elements for an even count.
  static double _median(Float64List buf, int n) {
    final tmp = Float64List(n);
    for (var i = 0; i < n; i++) {
      tmp[i] = buf[i];
    }
    tmp.sort();
    final mid = n ~/ 2;
    if (n.isOdd) return tmp[mid];
    return 0.5 * (tmp[mid - 1] + tmp[mid]);
  }
}
