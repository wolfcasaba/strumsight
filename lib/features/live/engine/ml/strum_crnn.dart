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
      confidence: up ? probs[1] : probs[0],
    );
  }
}
