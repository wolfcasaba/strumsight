import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp_config.dart';
import 'log_mel_extractor.dart';

/// SuperFlux onset detection (Böck & Widmer 2013; docs/plans/ml-track.md P0.2,
/// RAG chunk 015 rec #3).
///
/// Plain spectral flux fires on vibrato/pitch glides (energy MOVES between
/// bins and reads as new energy) and smears at 16th-note rates. SuperFlux
/// fixes both: compare each log-mel band against a MAXIMUM-FILTERED (±1 band)
/// reference [lag] frames back, so energy that merely slid to a neighbouring
/// band is cancelled, while a true broadband attack still rises everywhere.
///
/// Feed [processFrame] consecutive frames of [window] samples advanced by
/// [hop] (the StrumAnalyzer framing). Returns the onset TIME in seconds when
/// a peak is confirmed (decision is [`_postFrames`] frames after the peak —
/// the same delayed local-max pattern the whitened-flux path uses).
class SuperFluxOnsetDetector {
  SuperFluxOnsetDetector({
    required this.sampleRate,
    this.window = 1024,
    this.hop = 256,
    this.bands = 64,
    this.lag = 2,
    this.minIoiSec = 0.06,
    this.delta = _delta,
    this.lambda = _lambda,
  }) : _mel = LogMelExtractor(
          sampleRate: sampleRate,
          nFft: window,
          hop: hop,
          nMels: bands,
          fMin: 30.0,
        );

  final int sampleRate;
  final int window;
  final int hop;
  final int bands;

  /// Trajectory lag in frames: the reference frame for the rectified
  /// difference. ~11.6 ms at 1024/256 @ 44.1 kHz — enough that a slow vibrato
  /// stays inside the max-filter's reach while an attack clearly escapes it.
  final int lag;

  final double minIoiSec;

  /// Adaptive-threshold knobs (default = the tuned constants below). Made
  /// injectable in r166 so the REAL-recording recall harness can sweep them;
  /// production paths pass nothing and keep the pinned behaviour.
  final double delta;
  final double lambda;

  // The log-mel floor: bands below this are treated as silent so noise-floor
  // log-ratios (log of tiny power fluctuations) cannot register as flux.
  // -9.0 in log-power ≈ per-band amplitude ~1e-2 — well under any real pluck.
  static const double _floor = -9.0;

  // Adaptive threshold: flux > delta + lambda × median(recent flux), matching
  // the whitened-flux path's shape (chunk 005). Values are in summed
  // log-power units (tuned on the deterministic + randomized suites).
  // Delta is deliberately HIGH: log-domain flux is amplitude-invariant (a log
  // difference is a power ratio), so even a soft attack rises strongly across
  // most bands (measured ≥100) while ring-out beating bumps localise to a few
  // bands (measured ≤10, e.g. 0.836 s into a single default strum) — 20 splits
  // the two populations with margin on both sides.
  // r166 RETUNE on real data: the synth-tuned (20, 2.0) missed 27 % of the
  // 2 013 labeled strums on the Klangio eval takes (fast strumming raises the
  // median-flux floor and the threshold self-masks; real attacks are far
  // weaker in flux than synth ones). Sweep on the real fold:
  //   (20,2.0) 72 % recall / 87 % precision  ← old
  //   (12,1.0) 90 % recall / 83 % precision  ← new (chunk 005/018)
  // All synth pins (vibrato-immunity, one-strum-one-onset, 180-BPM 16ths,
  // ring-out silence) re-verified green at the new values.
  static const double _delta = 12.0;
  static const double _lambda = 1.0;
  static const int _medianFrames = 69; // ~0.4 s @ 44.1 kHz / 256 hop

  // Local-max confirmation: the candidate must top ±2 neighbouring frames.
  static const int _postFrames = 2;


  final LogMelExtractor _mel;
  // Release hysteresis (same idea as the whitened-flux path, chunk 005): one
  // strum = ONE continuous flux plateau. A new onset is eligible only after
  // the flux dipped below the threshold for ≥3 consecutive frames, so a lazy
  // 50–60 ms rake stays a single onset instead of firing per string.
  static const int _releaseFrames = 3;

  final ListQueue<Float64List> _ring = ListQueue();
  final ListQueue<double> _fluxWindow = ListQueue();
  final List<double> _fluxHist = [];
  final List<double> _thrHist = [];
  int _lastOnsetFrame = -1 << 30;
  int _belowStreak = _releaseFrames;
  bool _eligible = true;

  // Attack-relative gate (chunk 005, same constants as the whitened-flux
  // path): a candidate must reach ≥15% of the decayed recent flux peak, so
  // ring-out beating bumps far below the true attacks cannot fire.
  static const double _peakDecay = 0.985; // per frame
  static const double _peakRatio = 0.15;
  double _fluxPeak = 0;

  /// Flux of the most recent frame (debug/telemetry).
  double lastFlux = 0;

  /// Process one frame of exactly [window] samples advanced by [hop].
  /// Returns the confirmed onset's time (seconds, frame start) or null.
  double? processFrame(Float64List frame) {
    assert(frame.length == window);

    // Silence gate (chunk 005 convention): the noise floor's log-power
    // fluctuations must never register as flux, so a below-gate frame
    // contributes a floored band vector and zero flux.
    var sumSq = 0.0;
    for (var i = 0; i < window; i++) {
      sumSq += frame[i] * frame[i];
    }
    if (math.sqrt(sumSq / window) < DspConfig.silenceRms) {
      _ring.addLast(Float64List(bands)..fillRange(0, bands, _floor));
      if (_ring.length > lag) _ring.removeFirst();
      lastFlux = 0;
      _fluxWindow.addLast(0);
      if (_fluxWindow.length > _medianFrames) _fluxWindow.removeFirst();
      _fluxHist.add(0);
      _thrHist.add(double.infinity); // a gated frame can never be a peak
      // Silence still advances the release + peak state machines (r142 audit:
      // a staccato stab hard-cut to silence must re-arm eligibility, and a
      // frozen flux peak must not suppress a later soft strum).
      _belowStreak++;
      if (_belowStreak >= _releaseFrames) _eligible = true;
      _fluxPeak *= _peakDecay;
      return null;
    }

    final cur = _mel.processFrame(frame);
    final banded = Float64List(bands);
    for (var m = 0; m < bands; m++) {
      banded[m] = math.max(cur[m], _floor);
    }

    var flux = 0.0;
    if (_ring.length >= lag) {
      final ref = _ring.first; // the frame `lag` hops back
      for (var m = 0; m < bands; m++) {
        var maxRef = ref[m];
        if (m > 0 && ref[m - 1] > maxRef) maxRef = ref[m - 1];
        if (m < bands - 1 && ref[m + 1] > maxRef) maxRef = ref[m + 1];
        final rise = banded[m] - maxRef;
        if (rise > 0) flux += rise;
      }
    }
    _ring.addLast(banded);
    if (_ring.length > lag) _ring.removeFirst();
    lastFlux = flux;

    _fluxWindow.addLast(flux);
    if (_fluxWindow.length > _medianFrames) _fluxWindow.removeFirst();
    final thr = delta + lambda * _median(_fluxWindow);

    _fluxHist.add(flux);
    _thrHist.add(thr);
    _fluxPeak = math.max(flux, _peakDecay * _fluxPeak);
    if (flux < thr) {
      _belowStreak++;
      if (_belowStreak >= _releaseFrames) _eligible = true;
    } else {
      _belowStreak = 0;
    }

    // Confirm the local max at (now - _postFrames): it must beat its ±2
    // neighbours, exceed its threshold, and respect the min inter-onset gap.
    final c = _fluxHist.length - 1 - _postFrames;
    if (c < 0) return null;
    final fc = _fluxHist[c];
    if (fc <= _thrHist[c]) return null;
    if (fc < _peakRatio * _fluxPeak) return null;
    for (var i = math.max(0, c - _postFrames); i <= c + _postFrames; i++) {
      if (_fluxHist[i] > fc) return null;
    }
    final absC = c + _dropped; // absolute frame index survives trimming
    final minIoiFrames = (minIoiSec * sampleRate / hop).ceil();
    if (absC - _lastOnsetFrame < minIoiFrames) return null;
    if (!_eligible) return null;
    _lastOnsetFrame = absC;
    _eligible = false;
    _belowStreak = 0;

    // Trim histories (only the confirmation window is ever consulted).
    if (_fluxHist.length > 4 * _medianFrames) {
      final drop = _fluxHist.length - 2 * _medianFrames;
      _fluxHist.removeRange(0, drop);
      _thrHist.removeRange(0, drop);
      _dropped += drop;
    }
    return absC * hop / sampleRate;
  }

  int _dropped = 0;

  static double _median(ListQueue<double> q) {
    if (q.isEmpty) return 0;
    final sorted = q.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }
}
