import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import '../../model/strum.dart';
import 'dsp_config.dart';
import 'strum_direction_classifier.dart';
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

/// Onset detection (SuperFlux, chunk 015 rec #3 — round 136) + strum-direction
/// classification behind the [StrumDirectionClassifier] seam (round 139) +
/// level. Pure & streaming: push fixed frames via [process]; confirmed,
/// classified strums come back a few frames later (~70–90 ms).
///
/// Round 136 replaced the whitened-flux onset trigger with the r135
/// [SuperFluxOnsetDetector] — A/B MEASURED: vibrato false onsets 23 → 1 on a
/// 3 s constant-amplitude bend, 180/200 BPM 16ths 10–11/12 → 12/12, parity on
/// the mixed randomized suite. Round 139 moved the chunk-006 heuristic (with
/// its r59 onset-relative baseline) verbatim into [HeuristicStrumClassifier];
/// the future TFLite CRNN drops in behind the same seam (ml-track P1).
/// Cost note: this runs a second 1024-pt FFT per hop (the detector owns its
/// own log-mel) — ~tens of µs, dwarfed by the NNLS path.
class StrumAnalyzer {
  StrumAnalyzer({
    required this.sampleRate,
    this.window = DspConfig.onsetWindow,
    this.hop = DspConfig.onsetHop,
    StrumDirectionClassifier? classifier,
  })  : _fft = FFT(window),
        _hann = Float64List(window),
        _windowed = Float64List(window),
        _onsets = SuperFluxOnsetDetector(sampleRate: sampleRate),
        _classifier = classifier ?? HeuristicStrumClassifier() {
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

  // Reported-time correction (r144, MEASURED): the SuperFlux peak frame
  // STARTS a constant ~2.5 hops (14.2 ms) before the true attack instant —
  // invariant across stagger 4–12 ms and level 1.0/0.3. StrumEvent.timeSec
  // reports the estimated ATTACK so the LessonScorer's ±50 ms PERFECT window
  // keeps its full late-side margin for uncalibrated users. The correction is
  // applied ONLY to the reported time — classification and the Viterbi onset
  // boost keep the peak-frame reference (shifting them would slide the r59
  // baseline window into the attack).
  static const double _attackOffsetFrames = 2.5;

  final FFT _fft;
  final Float64List _hann;
  final Float64List _windowed;
  final SuperFluxOnsetDetector _onsets;
  final StrumDirectionClassifier _classifier;

  /// The classifier behind the seam (wiring proof surface, r169).
  StrumDirectionClassifier get debugClassifier => _classifier;

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
    var low = 0.0, high = 0.0, magSum = 0.0, weighted = 0.0;
    for (var k = 1; k < nBins; k++) {
      final re = spectrum[k].x, im = spectrum[k].y;
      final m = math.sqrt(re * re + im * im);
      final freq = k * sampleRate / window;
      if (freq <= _lowBandMaxHz) low += m;
      if (freq >= _highBandMinHz) high += m;
      magSum += m;
      weighted += m * freq;
    }
    _classifier.observe(
      frame,
      StrumFrameFeatures(
        lowEnergy: low,
        highEnergy: high,
        centroid: magSum > 0 ? weighted / magSum : 0,
      ),
    );

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
      final onsetFrame = _pendingOnsets.removeFirst();
      final c = _classifier.classifyAt(
        onsetFrame: onsetFrame,
        currentFrame: _frameIndex,
      );
      // r175: the learned no-strum reject fired — this detected onset is not a
      // strum, so emit NO event. Every downstream consumer (Live arrow, Learn
      // scoring, streak) sees nothing, exactly as if the onset never happened.
      // A 2-class model / the heuristic never set this, so their behaviour is
      // unchanged (a null direction still yields a StrumEvent — ambiguous
      // strum, not no-strum).
      if (c.suppressed) return null;
      return StrumEvent(
        timeSec: (onsetFrame + _attackOffsetFrames) * _frameSec,
        direction: c.direction,
        confidence: c.confidence,
      );
    }
    return null;
  }
}
