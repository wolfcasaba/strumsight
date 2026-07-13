import 'dart:typed_data';

/// Signal-prep ports feeding [CrnnStrumNet] — each mirrors its Python
/// training-pipeline twin EXACTLY (the r134 parity discipline: the model only
/// knows the distribution it was trained on; feature drift is silent death).
class CrnnFrontend {
  /// Model input window geometry (ml/features.py PRE_FRAMES/POST_FRAMES).
  static const preFrames = 3; // 30 ms before the attack
  static const postFrames = 12; // 120 ms after — attack + early decay

  /// 10 ms log-mel hop at the model's 16 kHz rate (ml/features.py HOP/SR).
  static const modelSampleRate = 16000;
  static const modelHop = 160;

  /// Linear resample, the exact `np.interp(np.linspace(0, n-1, round(n*to/
  /// from)), arange(n), x)` of ml/prepare_dataset.py::_read_wav (round-140
  /// note: linear-interp is the contract; upgrade BOTH sides or neither).
  /// Returns [x] itself when the rates already match.
  static Float64List resampleLinear(Float64List x, int from, int to) {
    if (from == to || x.isEmpty) return x;
    final n = (x.length * to / from).round();
    final out = Float64List(n);
    if (n == 1) {
      out[0] = x[0];
      return out;
    }
    final step = (x.length - 1) / (n - 1);
    for (var i = 0; i < n; i++) {
      final pos = i * step;
      final lo = pos.floor();
      if (lo >= x.length - 1) {
        out[i] = x[x.length - 1];
      } else {
        final frac = pos - lo;
        out[i] = x[lo] * (1 - frac) + x[lo + 1] * frac;
      }
    }
    return out;
  }

  /// The (preFrames+postFrames, mels) log-mel window centred on an onset,
  /// zero-padded past either edge — `ml/features.py::window_at` verbatim.
  static List<List<double>> windowAt(
    List<Float64List> logmel,
    double onsetSec,
  ) {
    final mels = logmel.isEmpty ? 128 : logmel.first.length;
    final center = (onsetSec * modelSampleRate / modelHop).round();
    final lo = center - preFrames;
    return [
      for (var i = 0; i < preFrames + postFrames; i++)
        (lo + i >= 0 && lo + i < logmel.length)
            ? List<double>.from(logmel[lo + i])
            : List<double>.filled(mels, 0),
    ];
  }
}
