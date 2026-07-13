import 'dart:io';
import 'dart:typed_data';

import '../dsp/log_mel_extractor.dart';
import '../dsp/strum_direction_classifier.dart';
import '../../model/strum.dart';
import 'crnn_frontend.dart';
import 'crnn_strum_net.dart';

/// The deployment facade over [CrnnStrumNet]: raw clip audio in, per-onset
/// ↓/↑ verdicts out, running the EXACT training-pipeline chain (linear
/// resample to 16 kHz → parity-contracted log-mel → PRE/POST window at the
/// onset → forward pass).
///
/// Batch-first by design (ml-track P1.3 note, 2026-07-13): the model window
/// needs ~240 ms of post-onset audio, which the LIVE path's 70 ms verdict
/// deadline cannot wait for — so the CRNN serves the Analyze/clip path, where
/// the whole recording exists, and the live path keeps the heuristic.
class StrumCrnn {
  StrumCrnn(this._net)
      : _logMel = LogMelExtractor(sampleRate: CrnnFrontend.modelSampleRate);

  final CrnnStrumNet _net;
  final LogMelExtractor _logMel;

  /// Loads the weights asset from [path], or null when it is absent or
  /// unparseable — callers fall back to the heuristic, never crash
  /// (the model is an upgrade, not a dependency).
  static StrumCrnn? tryLoad(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      return StrumCrnn(
        CrnnStrumNet.parse(ByteData.sublistView(bytes)),
      );
    } catch (_) {
      return null;
    }
  }

  /// Classify the strum at each of [onsetTimes] (seconds) in [pcm].
  /// Label order is the training contract: 0 = down, 1 = up (ml/klangio.py).
  List<StrumClassification> classifyClip(
    Float64List pcm,
    int sampleRate,
    List<double> onsetTimes,
  ) {
    final pcm16k = CrnnFrontend.resampleLinear(
        pcm, sampleRate, CrnnFrontend.modelSampleRate);
    final logmel = _logMel.process(pcm16k);
    return [
      for (final t in onsetTimes) _classifyWindow(logmel, t),
    ];
  }

  StrumClassification _classifyWindow(
      List<Float64List> logmel, double onsetSec) {
    final probs = _net.forward(CrnnFrontend.windowAt(logmel, onsetSec));
    final up = probs[1] > probs[0];
    return StrumClassification(
      direction: up ? StrumDirection.up : StrumDirection.down,
      confidence: calibrate(up ? probs[1] : probs[0]),
    );
  }

  /// Raw softmax → empirical P(correct) for the BATCH model (r171, measured
  /// on the eval fold at labeled times, 2 013 strums): <0.7 → 62 %,
  /// 0.7–0.9 → 64 %, 0.9–0.97 → 73 %, 0.97–0.995 → 83 %, ≥0.995 → 96 % —
  /// better top-end calibration than the live 70 ms model (r170) because the
  /// full window is far more decisive, but still overconfident below 0.97.
  /// Keeps timeline/share-card percentages honest.
  static double calibrate(double p) {
    const knots = [
      (0.50, 0.60), (0.60, 0.62), (0.80, 0.64), //
      (0.935, 0.73), (0.9825, 0.83), (0.9975, 0.96), (1.00, 0.96),
    ];
    if (p <= knots.first.$1) return knots.first.$2;
    for (var i = 1; i < knots.length; i++) {
      if (p <= knots[i].$1) {
        final (x0, y0) = knots[i - 1];
        final (x1, y1) = knots[i];
        return y0 + (y1 - y0) * (p - x0) / (x1 - x0);
      }
    }
    return knots.last.$2;
  }
}
