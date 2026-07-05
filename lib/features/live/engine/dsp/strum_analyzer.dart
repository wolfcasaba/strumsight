import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import '../../model/strum.dart';
import 'dsp_config.dart';

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
  double flux = 0;
  double lowEnergy = 0;
  double highEnergy = 0;
  double centroid = 0;
}

/// Onset detection (spectral flux, RAG chunk 005) + strum-direction
/// classification (sub-band rise order × centroid slope fusion, chunk 006)
/// + level. Pure & streaming: push fixed frames via [process]; confirmed,
/// classified strums come back a few frames later (~70–90 ms).
class StrumAnalyzer {
  StrumAnalyzer({
    required this.sampleRate,
    this.window = DspConfig.onsetWindow,
    this.hop = DspConfig.onsetHop,
  })  : _fft = FFT(window),
        _hann = Float64List(window),
        _windowed = Float64List(window),
        _mags = Float64List(window ~/ 2),
        _prevMags = Float64List(window ~/ 2) {
    for (var i = 0; i < window; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (window - 1));
    }
  }

  final int sampleRate;
  final int window;
  final int hop;

  // Tunables (RAG chunks 005–006; update the chunk when retuned).
  // Adaptive whitening (Stowell & Plumbley): normalise each bin by its
  // recent peak so attacks pop out and steady inter-string beating is
  // suppressed. MEASURED: without it, ring-out beating floods the flux
  // baseline and re-strums never cross a median-scaled threshold.
  static const _whitenDecay = 0.995; // per ~5.8 ms frame
  static const _whitenFloor = 1e-4;
  static const _fluxDelta = 1.0; // additive, on whitened linear flux
  static const _fluxLambda = 2.0; // × median, on whitened linear flux
  static const _medianFrames = 20;
  static const _minOnsetGapMs = 60.0;
  static const _lowBandMaxHz = 200.0;
  static const _highBandMinHz = 1000.0;
  static const _classifyAfterFrames = 12; // ~70 ms of post-onset evidence
  static const _historyLen = 48;

  final FFT _fft;
  final Float64List _hann;
  final Float64List _windowed;
  final Float64List _mags;
  final Float64List _prevMags; // previous WHITENED magnitudes
  late final Float64List _binPeaks = Float64List(window ~/ 2);

  final ListQueue<_Frame> _history = ListQueue();
  final ListQueue<double> _fluxWindow = ListQueue();
  int _frameIndex = -1;
  int _lastOnsetFrame = -1 << 30;
  int _pendingOnsetFrame = -1;
  bool _hasPrev = false;

  /// RMS of the most recent frame (level meter).
  double lastRms = 0;

  /// Diagnostics (tests/tuning only).
  double debugLastFlux = 0;
  double debugLastThreshold = 0;

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
    var flux = 0.0, magSum = 0.0, weighted = 0.0;
    for (var k = 1; k < nBins; k++) {
      final re = spectrum[k].x, im = spectrum[k].y;
      final m = math.sqrt(re * re + im * im);
      final freq = k * sampleRate / window;

      // Adaptive whitening: track the recent per-bin peak, normalise by it.
      final p = math.max(m, _whitenDecay * _binPeaks[k]);
      _binPeaks[k] = p;
      final w = m / math.max(p, _whitenFloor);

      final rise = w - _prevMags[k];
      if (rise > 0) flux += rise; // half-wave rectified, whitened
      if (freq <= _lowBandMaxHz) f.lowEnergy += m;
      if (freq >= _highBandMinHz) f.highEnergy += m;
      magSum += m;
      weighted += m * freq;
      _mags[k] = w;
    }
    _prevMags.setAll(0, _mags);
    f.centroid = magSum > 0 ? weighted / magSum : 0;
    f.flux = _hasPrev ? flux : 0; // linear whitened flux; first frame: none
    _hasPrev = true;

    _history.addLast(f);
    if (_history.length > _historyLen) _history.removeFirst();
    _fluxWindow.addLast(f.flux);
    if (_fluxWindow.length > _medianFrames) _fluxWindow.removeFirst();

    // Silence gate: no onsets from the noise floor.
    final gated = lastRms < DspConfig.silenceRms;

    // Peak picking with 2-frame confirmation lag (chunk 005): frame n-2 is an
    // onset if it exceeded the adaptive threshold and is a ±2-frame local max.
    StrumEvent? event;
    debugLastFlux = f.flux;
    if (!gated && _history.length >= 5 && _pendingOnsetFrame < 0) {
      final h = _history.toList();
      final n = h.length;
      final cand = h[n - 3].flux;
      final thr = _fluxDelta + _fluxLambda * _median(_fluxWindow);
      debugLastThreshold = thr;
      final isMax = cand > thr &&
          cand >= h[n - 5].flux &&
          cand >= h[n - 4].flux &&
          cand >= h[n - 2].flux &&
          cand >= h[n - 1].flux;
      final candFrame = _frameIndex - 2;
      final msSinceLast = (candFrame - _lastOnsetFrame) * _frameSec * 1000;
      if (isMax && msSinceLast >= _minOnsetGapMs) {
        _lastOnsetFrame = candFrame;
        _pendingOnsetFrame = candFrame;
      }
    }

    // Classify once enough post-onset evidence has accumulated (chunk 006).
    if (_pendingOnsetFrame >= 0 &&
        _frameIndex - _pendingOnsetFrame >= _classifyAfterFrames) {
      event = _classify(_pendingOnsetFrame);
      _pendingOnsetFrame = -1;
    }
    return event;
  }

  StrumEvent _classify(int onsetFrame) {
    final h = _history.toList();
    // History index of the onset frame.
    final oIdx = h.length - 1 - (_frameIndex - onsetFrame);
    final start = math.max(0, oIdx - 2);
    final win = h.sublist(start);

    // Cue 1 — sub-band rise order: which band reaches 50% of its window peak
    // first. Bass first → down, treble first → up.
    final lowRise = _firstRise(win.map((x) => x.lowEnergy).toList());
    final highRise = _firstRise(win.map((x) => x.highEnergy).toList());
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

  static double _median(Iterable<double> xs) {
    final sorted = xs.toList()..sort();
    if (sorted.isEmpty) return 0;
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
