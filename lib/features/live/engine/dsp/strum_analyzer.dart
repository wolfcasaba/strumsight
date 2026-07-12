import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import '../../model/strum.dart';
import 'dsp_config.dart';
import 'superflux_onset_detector.dart';

/// A detected strum: when, which direction (null = truly ambiguous), and how
/// confident the direction call is.
class StrumEvent {
  const StrumEvent({
    required this.timeSec,
    required this.direction,
    required this.confidence,
  });

  final double timeSec;
  final StrumDirection? direction;
  final double confidence;
}

/// Per-hop spectral measurements kept in a short history ring.
class _Frame {
  double lowEnergy = 0;
  double highEnergy = 0;
  double centroid = 0;
}

/// Onset detection (SuperFlux, chunk 015 rec #3 — round 136) + strum-direction
/// classification (sub-band rise order × centroid slope fusion, chunk 006)
/// + level. Pure & streaming: push fixed frames via [process]; confirmed,
/// classified strums come back a few frames later (~70–90 ms).
///
/// Round 136 replaced the whitened-flux onset trigger with the r135
/// [SuperFluxOnsetDetector] — A/B MEASURED: vibrato false onsets 23 → 1 on a
/// 3 s constant-amplitude bend, 180/200 BPM 16ths 10–11/12 → 12/12, parity on
/// the mixed randomized suite. The classification stage (with its r59
/// onset-relative baseline subtraction) is unchanged. Cost note: this runs a
/// second 1024-pt FFT per hop (the detector owns its own log-mel) — ~tens of
/// µs, dwarfed by the NNLS path.
class StrumAnalyzer {
  StrumAnalyzer({
    required this.sampleRate,
    this.window = DspConfig.onsetWindow,
    this.hop = DspConfig.onsetHop,
  })  : _fft = FFT(window),
        _hann = Float64List(window),
        _windowed = Float64List(window),
        _onsets = SuperFluxOnsetDetector(sampleRate: sampleRate) {
    assert(window == _onsets.window && hop == _onsets.hop,
        'StrumAnalyzer framing must match the SuperFlux detector');
    for (var i = 0; i < window; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (window - 1));
    }
  }

  final int sampleRate;
  final int window;
  final int hop;

  // Tunables (RAG chunks 005–006; update the chunk when retuned).
  static const _lowBandMaxHz = 200.0;
  static const _highBandMinHz = 1000.0;
  static const _classifyAfterFrames = 12; // ~70 ms of post-onset evidence
  static const _historyLen = 48;

  final FFT _fft;
  final Float64List _hann;
  final Float64List _windowed;
  final SuperFluxOnsetDetector _onsets;

  final ListQueue<_Frame> _history = ListQueue();
  // Onsets awaiting their post-onset evidence window. A queue (not a single
  // slot): at 200 BPM 16ths the next onset (~75 ms) can land while the
  // previous one is still inside its ~70 ms classify window.
  final ListQueue<int> _pendingOnsets = ListQueue();
  int _frameIndex = -1;

  /// RMS of the most recent frame (level meter).
  double lastRms = 0;

  /// True when THIS frame confirmed a new onset (before classification — the
  /// pipeline uses it to trigger the decoder's onset-aligned switch boost,
  /// round 138). Reset every [process] call.
  bool onsetJustFired = false;

  double get _frameSec => hop / sampleRate;

  /// Push the next [window]-sample frame (advanced by [hop]); returns a
  /// confirmed+classified strum when one completes its evidence window.
  StrumEvent? process(Float64List frame) {
    assert(frame.length == window);
    _frameIndex++;

    var sumSq = 0.0;
    for (var i = 0; i < window; i++) {
      final s = frame[i];
      sumSq += s * s;
      _windowed[i] = s * _hann[i];
    }
    lastRms = math.sqrt(sumSq / window);

    final spectrum = _fft.realFft(_windowed);
    final nBins = window ~/ 2;
    final f = _Frame();
    var magSum = 0.0, weighted = 0.0;
    for (var k = 1; k < nBins; k++) {
      final re = spectrum[k].x, im = spectrum[k].y;
      final m = math.sqrt(re * re + im * im);
      final freq = k * sampleRate / window;
      if (freq <= _lowBandMaxHz) f.lowEnergy += m;
      if (freq >= _highBandMinHz) f.highEnergy += m;
      magSum += m;
      weighted += m * freq;
    }
    f.centroid = magSum > 0 ? weighted / magSum : 0;

    _history.addLast(f);
    if (_history.length > _historyLen) _history.removeFirst();

    // SuperFlux onset trigger (silence gate, release hysteresis and the
    // attack-relative peak gate all live inside the detector).
    final onsetSec = _onsets.processFrame(frame);
    onsetJustFired = onsetSec != null;
    if (onsetSec != null) {
      _pendingOnsets.addLast((onsetSec * sampleRate / hop).round());
    }

    // Classify once enough post-onset evidence has accumulated (chunk 006).
    if (_pendingOnsets.isNotEmpty &&
        _frameIndex - _pendingOnsets.first >= _classifyAfterFrames) {
      return _classify(_pendingOnsets.removeFirst());
    }
    return null;
  }

  StrumEvent _classify(int onsetFrame) {
    final h = _history.toList();
    // History index of the onset frame.
    final oIdx = h.length - 1 - (_frameIndex - onsetFrame);
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

    final byBands =
        gap == null || gap == 0 ? null : (gap > 0 ? StrumDirection.down : StrumDirection.up);
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

    return StrumEvent(
      timeSec: onsetFrame * _frameSec,
      direction: direction,
      confidence: confidence,
    );
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
