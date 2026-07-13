import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../dsp/log_mel_extractor.dart';
import '../dsp/strum_direction_classifier.dart';
import '../../model/strum.dart';
import 'crnn_frontend.dart';
import 'crnn_strum_net.dart';

/// Streaming front-end for the TRUE-70 ms live model (r168): keeps a raw
/// audio ring fed per fast hop and, at the classify instant, rebuilds the
/// EXACT training window of `ml/experiment_deadline.window_truncated` — a
/// 15-row log-mel around the onset over audio that simply ENDS at the
/// verdict deadline (the truncation is the availability; rows past it see
/// zeros, exactly as trained).
class LiveCrnnFrontend {
  LiveCrnnFrontend({
    required this.sampleRate,
    this.window = 1024,
    this.hop = 256,
  })  : _ring = Float64List(sampleRate), // 1 s — window needs ~300 ms
        _logMel = LogMelExtractor(sampleRate: CrnnFrontend.modelSampleRate);

  final int sampleRate;
  final int window;
  final int hop;

  final Float64List _ring;
  final LogMelExtractor _logMel;
  int _end = 0; // absolute sample index one past the newest sample
  bool _first = true;

  /// Feed one analyzer frame ([window] samples advanced by [hop]).
  void observe(Float64List frame) {
    assert(frame.length == window);
    if (_first) {
      _append(frame, 0);
      _first = false;
    } else {
      _append(frame, window - hop); // only the new hop tail
    }
  }

  void _append(Float64List frame, int from) {
    for (var i = from; i < frame.length; i++) {
      _ring[_end % _ring.length] = frame[i];
      _end++;
    }
  }

  /// The (15, 128) truncated log-mel window for a strum whose onset FRAME is
  /// [onsetFrame], evaluated with the audio available at [currentFrame] —
  /// the analyzer's own frame indices.
  List<List<double>> windowAt(int onsetFrame, int currentFrame) {
    // Reported-time semantics (r144): the attack sits ~2.5 hops after the
    // onset frame's start — the same instant the batch path classifies at.
    final onsetSec = (onsetFrame + 2.5) * hop / sampleRate;
    final availableEnd = currentFrame * hop + window;
    return _buildWindow(onsetSec, availableEnd);
  }

  /// The same window computed from a WHOLE signal (no ring) — the test
  /// reference and the parity anchor for the streamed path.
  static List<List<double>> referenceWindow(
      Float64List available, int sampleRate, double onsetFrameStartSec) {
    final fe = LiveCrnnFrontend(sampleRate: sampleRate);
    fe._append(available, 0);
    final onsetSec = onsetFrameStartSec + 2.5 * fe.hop / sampleRate;
    return fe._buildWindow(onsetSec, available.length);
  }

  List<List<double>> _buildWindow(double onsetSec, int availableEnd) {
    const mSr = CrnnFrontend.modelSampleRate; // 16 k
    const mHop = CrnnFrontend.modelHop; // 160
    final center = (onsetSec * mSr / mHop).round();
    final lo16 = (center - CrnnFrontend.preFrames) * mHop;
    final rows = CrnnFrontend.preFrames + CrnnFrontend.postFrames;
    final segLen = (rows - 1) * mHop + _logMel.nFft;
    final seg = Float64List(segLen);

    // The 16 k grid maps to source samples at ratio sr/16k; fill what exists.
    final lo44 = (lo16 * sampleRate / mSr).floor();
    final hi44 = math.min(availableEnd,
        ((lo16 + segLen) * sampleRate / mSr).ceil());
    final oldest = math.max(0, _end - _ring.length);
    final a = math.max(lo44, oldest);
    if (hi44 > a) {
      final slice = Float64List(hi44 - a);
      for (var i = 0; i < slice.length; i++) {
        slice[i] = _ring[(a + i) % _ring.length];
      }
      final res = CrnnFrontend.resampleLinear(slice, sampleRate, mSr);
      final off = ((a * mSr / sampleRate).round()) - lo16;
      for (var i = 0; i < res.length; i++) {
        final j = off + i;
        if (j >= 0 && j < segLen) seg[j] = res[i];
      }
    }

    return [
      for (var r = 0; r < rows; r++)
        _logMel
            .processFrame(
                Float64List.sublistView(seg, r * mHop, r * mHop + _logMel.nFft))
            .toList(),
    ];
  }
}

/// The live ↓/↑ classifier behind the r139 seam: the 70 ms-deadline CRNN
/// (real-fold eval 0.799 vs the heuristic's 0.389, r167) with the analyzer's
/// unchanged verdict timing. Absent/unparseable weights → callers construct
/// the heuristic instead ([tryLoad] returns null).
class LiveCrnnStrumClassifier implements StrumDirectionClassifier {
  LiveCrnnStrumClassifier(this._net, {required int sampleRate})
      : _frontend = LiveCrnnFrontend(sampleRate: sampleRate);

  final CrnnStrumNet _net;
  final LiveCrnnFrontend _frontend;

  static LiveCrnnStrumClassifier? tryLoad(String path,
      {required int sampleRate}) {
    try {
      final bytes = File(path).readAsBytesSync();
      return LiveCrnnStrumClassifier(
        CrnnStrumNet.parse(ByteData.sublistView(bytes)),
        sampleRate: sampleRate,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void observe(Float64List frame, StrumFrameFeatures features) =>
      _frontend.observe(frame);

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) {
    final probs = _net.forward(_frontend.windowAt(onsetFrame, currentFrame));
    final up = probs[1] > probs[0];
    return StrumClassification(
      direction: up ? StrumDirection.up : StrumDirection.down,
      confidence: up ? probs[1] : probs[0],
    );
  }
}
