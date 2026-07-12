import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../model/strum.dart';

/// One fast-hop frame's spectral features — computed ONCE by the analyzer's
/// FFT pass and shared with the classifier (no duplicate FFT).
class StrumFrameFeatures {
  const StrumFrameFeatures({
    required this.lowEnergy,
    required this.highEnergy,
    required this.centroid,
  });

  /// Summed magnitude ≤ 200 Hz (bass strings' fundamentals).
  final double lowEnergy;

  /// Summed magnitude ≥ 1 kHz (treble attack content).
  final double highEnergy;

  /// Magnitude-weighted spectral centroid (Hz).
  final double centroid;
}

/// A classifier's verdict for one onset (null direction = honestly ambiguous).
class StrumClassification {
  const StrumClassification({required this.direction, required this.confidence});

  final StrumDirection? direction;
  final double confidence;
}

/// The ↓/↑ decision seam (docs/plans/ml-track.md P1.1, chunk 018 step 2).
///
/// Today's [HeuristicStrumClassifier] and the future TFLite streaming CRNN
/// implement this one interface. The contract is streaming-shaped so both fit:
/// [observe] is called on EVERY fast hop with the raw audio frame (the CRNN
/// computes its log-mel + GRU state from it; the heuristic reads the shared
/// [StrumFrameFeatures] instead), and [classifyAt] is called once the
/// analyzer's post-onset evidence window has elapsed.
abstract class StrumDirectionClassifier {
  /// Observe one [window]-sample frame advanced by one hop, with the
  /// analyzer's precomputed spectral features for that frame.
  void observe(Float64List frame, StrumFrameFeatures features);

  /// Classify the strum whose onset was at [onsetFrame], evaluated at
  /// [currentFrame] (the analyzer calls this a fixed evidence window after
  /// the onset — currently 12 frames ≈ 70 ms).
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  });
}

/// The chunk-006 heuristic: sub-band rise order × centroid slope fusion over
/// an onset-relative BASELINE-SUBTRACTED evidence window (round 59). Moved
/// verbatim out of StrumAnalyzer in round 139 — behaviour is pinned by the
/// analyzer's direction tests and the randomized property gate.
class HeuristicStrumClassifier implements StrumDirectionClassifier {
  static const _historyLen = 48;

  final ListQueue<StrumFrameFeatures> _history = ListQueue();
  int _lastObservedFrame = -1;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) {
    _lastObservedFrame++;
    _history.addLast(features);
    if (_history.length > _historyLen) _history.removeFirst();
  }

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) {
    assert(currentFrame == _lastObservedFrame,
        'classifyAt must be called in step with observe()');
    final h = _history.toList();
    // History index of the onset frame.
    final oIdx = h.length - 1 - (currentFrame - onsetFrame);
    // Onset-relative baseline: mean band energy in the ~5 frames BEFORE the
    // onset. Subtracting it isolates THIS strum's new attack from the ring-out
    // of any previous strum. Without it, during fast strumming the prior
    // strum's decaying energy holds both bands above their 50%-rise line from
    // frame 0, so the rise-order cue collapses (MEASURED: direction fell to
    // 4/7 at 200 BPM 16ths; baseline subtraction restores it).
    final baseStart = math.max(0, oIdx - 5);
    var baseLow = 0.0, baseHigh = 0.0, baseN = 0;
    for (var i = baseStart; i < oIdx && i < h.length; i++) {
      baseLow += h[i].lowEnergy;
      baseHigh += h[i].highEnergy;
      baseN++;
    }
    if (baseN > 0) {
      baseLow /= baseN;
      baseHigh /= baseN;
    }

    // Evidence window: from two frames before the onset (the rising edge)
    // through the post-onset attack. MEASURED sweep: baseline subtraction over
    // this full ~70 ms window holds direction at 8/8 for 100–160 BPM 16ths
    // (the realistic ceiling of hand strumming); attack-anchoring or hard caps
    // regressed the common tempos. Extreme overlap (200 BPM 16ths, ~75 ms
    // apart) still degrades — the next strum bleeds into the tail — which the
    // confidence tier reports honestly rather than faking certainty.
    final start = math.max(0, oIdx - 2);
    final win = h.sublist(start);

    // Cue 1 — sub-band rise order on the BASELINE-SUBTRACTED envelopes: which
    // band's NEW energy reaches 50% of its in-window peak first. Bass first →
    // down, treble first → up.
    final lowRise =
        _firstRise([for (final x in win) math.max(0.0, x.lowEnergy - baseLow)]);
    final highRise = _firstRise(
        [for (final x in win) math.max(0.0, x.highEnergy - baseHigh)]);
    int? gap; // positive → low first → down
    if (lowRise != null && highRise != null) gap = highRise - lowRise;

    // Cue 2 — centroid slope over the evidence window: rising (dark→bright)
    // → down, falling → up.
    final head = win.take(4).map((x) => x.centroid).toList();
    final tail = win.skip(math.max(0, win.length - 4)).map((x) => x.centroid);
    final slope = _mean(tail) - _mean(head);

    final byBands = gap == null || gap == 0
        ? null
        : (gap > 0 ? StrumDirection.down : StrumDirection.up);
    final byCentroid = slope.abs() < 1.0
        ? null
        : (slope > 0 ? StrumDirection.down : StrumDirection.up);

    StrumDirection? direction;
    double confidence;
    if (byBands != null && byBands == byCentroid) {
      direction = byBands;
      confidence = (0.8 + 0.05 * math.min(3, gap!.abs())).clamp(0.0, 0.95);
    } else if (byBands != null && (gap!.abs() >= 2 || byCentroid == null)) {
      direction = byBands;
      confidence = 0.55;
    } else if (byCentroid != null) {
      direction = byCentroid;
      confidence = 0.5;
    } else {
      direction = null; // honestly ambiguous — never fake certainty
      confidence = 0.3;
    }

    return StrumClassification(direction: direction, confidence: confidence);
  }

  /// First index where the series crosses 50% of its max (null if flat).
  static int? _firstRise(List<double> series) {
    var peak = 0.0;
    for (final v in series) {
      peak = math.max(peak, v);
    }
    if (peak <= 0) return null;
    for (var i = 0; i < series.length; i++) {
      if (series[i] >= 0.5 * peak) return i;
    }
    return null;
  }

  static double _mean(Iterable<double> xs) {
    var sum = 0.0;
    var n = 0;
    for (final x in xs) {
      sum += x;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }
}
