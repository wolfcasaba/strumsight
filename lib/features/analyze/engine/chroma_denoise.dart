import 'dart:typed_data';

/// Temporal denoising of the per-hop chroma sequence, applied BEFORE chord
/// decoding to suppress spurious chord detections on full-band audio
/// (drums + bass).
///
/// The batch chord path (`clip_analyzer.dart` `_chordPass`) produces two
/// parallel `List<Float64List>` sequences — `bassFrames` and `trebleFrames`,
/// one 12-dim chroma (pitch classes C..B) per STFT hop (~93 ms). On a
/// full-band mix, drum hits and bass passing-notes are TRANSIENT: their energy
/// appears in a single frame (or two) and vanishes. Genuine chord tones are
/// SUSTAINED: they persist across many consecutive frames.
///
/// A per-pitch-class temporal MEDIAN filter over a small odd sliding window
/// exploits exactly that asymmetry. For each pitch class, a lone spike inside
/// the window is outvoted by the surrounding frames and collapses to (near)
/// zero, while a value that is present in a MAJORITY of the window survives
/// unchanged. Unlike a mean/box filter, the median does not smear a transient's
/// energy into its neighbours — it removes it outright.
///
/// Pure Dart, deterministic, allocation-per-call (never mutates the input).
abstract final class ChromaDenoise {
  /// Per-pitch-class temporal median filter over a sliding [window] centered on
  /// each frame (window clamped at the sequence edges).
  ///
  /// Returns a NEW list of the same length; `output[i][pc]` is the median of
  /// `input[j][pc]` for `j` in the window of radius `window ~/ 2` centered at
  /// `i`, computed for each of the 12 pitch classes independently.
  ///
  /// [window] is expected to be odd (an even value is treated by its
  /// symmetric radius `window ~/ 2`, so `4` behaves like `5`). If `window <= 1`
  /// or the sequence is shorter than [window], an unchanged deep copy is
  /// returned. The input frames are never mutated.
  static List<Float64List> temporalMedian(
    List<Float64List> frames, {
    int window = 5,
  }) {
    final n = frames.length;
    if (window <= 1 || n < window) {
      return _copy(frames);
    }

    final radius = window ~/ 2;
    final out = List<Float64List>.generate(n, (_) => Float64List(12));
    // Scratch buffer reused per (frame, pitch-class) to avoid per-cell alloc.
    final scratch = Float64List(2 * radius + 1);

    for (var i = 0; i < n; i++) {
      final lo = i - radius < 0 ? 0 : i - radius;
      final hi = i + radius >= n ? n - 1 : i + radius;
      final count = hi - lo + 1;
      final dst = out[i];
      for (var pc = 0; pc < 12; pc++) {
        for (var k = 0; k < count; k++) {
          scratch[k] = frames[lo + k][pc];
        }
        dst[pc] = _median(scratch, count);
      }
    }
    return out;
  }

  /// Median of the first [count] entries of [buf] (only that prefix is read).
  ///
  /// Sorts a small copy of the prefix; for the odd counts a centered odd
  /// window produces this is the middle element, for an even count the mean of
  /// the two central elements. Does not mutate [buf].
  static double _median(Float64List buf, int count) {
    final tmp = Float64List(count);
    for (var i = 0; i < count; i++) {
      tmp[i] = buf[i];
    }
    tmp.sort();
    final mid = count ~/ 2;
    if (count.isOdd) {
      return tmp[mid];
    }
    return 0.5 * (tmp[mid - 1] + tmp[mid]);
  }

  static List<Float64List> _copy(List<Float64List> frames) {
    return List<Float64List>.generate(
      frames.length,
      (i) => Float64List.fromList(frames[i]),
      growable: false,
    );
  }
}
