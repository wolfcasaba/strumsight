/// Onset-detector variant seam for the E14-R16 A/B benchmark (ADR 0524 D1).
///
/// Declares four onset-detecting functions on the SAME public shape
/// ([OnsetDetectorVariant.processFrame]) so `tool/benchmarks/onset_ab_benchmark.dart`
/// can measure them against the identical case set with the identical,
/// merge-elt scoring contract (`recognition_metrics.dart`, ADR 0509). This
/// file does not change, wrap in a re-tuned way, or bypass the shipped
/// `SuperFluxOnsetDetector` — [OnsetVariantId.current] instantiates it
/// directly, with its default constants (ADR 0524 D1/5.2), and the three
/// NEW variants read their tuning (`delta`, `lambda`, `minIoiSec`, `lag`,
/// `window`, `hop`) from a `SuperFluxOnsetDetector` instance's PUBLIC
/// fields — never a re-typed literal (ADR 0524 D2).
///
/// `_medianFrames`, `_postFrames`, `_releaseFrames`, `_peakDecay`,
/// `_peakRatio` and the log-power floor below are a documented, HAND-SYNCED
/// mirror of `SuperFluxOnsetDetector`'s private tuning constants (ADR 0524
/// D2) — this file does not, and cannot, import them; if the shipped file's
/// private constants are retuned, these must be updated by hand.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import 'superflux_onset_detector.dart';

/// The four onset-detecting functions this round measures (ADR 0524 D1).
enum OnsetVariantId {
  current,
  canonicalSuperFlux24,
  complexDomain,
  spectralFlux,
}

/// A single onset-detecting function, framed the same way the live pipeline
/// frames audio: consecutive [window]-sample frames advanced by [hop].
abstract class OnsetDetectorVariant {
  OnsetVariantId get id;
  int get window;
  int get hop;

  /// The adaptive-threshold tuning this variant runs with — for the three
  /// NEW variants, read live off a `SuperFluxOnsetDetector` instance's
  /// public fields (ADR 0524 D2); `current`'s are the shipped detector's
  /// own. Exposed so a test can pin these against the LIVE shipped default
  /// rather than a bare literal (ADR 0524 mérce, 8. pont).
  double get delta;
  double get lambda;
  double get minIoiSec;

  /// The most recent frame's raw ODF value, BEFORE thresholding — mirrors
  /// the shipped detector's public `lastFlux` field. `current` delegates to
  /// it directly; the three NEW variants return their own, just-computed
  /// flux. These numbers are a function of the input only, so they belong
  /// in the deterministic report, not the machine-dependent timing channel
  /// (ADR 0524 D8) — the four variants share one absolute `delta`, but
  /// their flux lives in different units (log-power vs. linear magnitude,
  /// 64 vs. ~200 bands), so this field is what lets the benchmark MEASURE
  /// that scale confound instead of only describing it.
  double get lastFlux;

  /// Human-readable description of the algorithm — surfaced in the report,
  /// not only in source comments (mirrors `RecognitionMetricDefinition`'s
  /// "definition travels with the number" pattern, ADR 0509 D3).
  String describe();

  /// Process one frame of exactly [window] samples. Returns the confirmed
  /// onset TIME in seconds (frame start, same convention as
  /// `SuperFluxOnsetDetector.processFrame`) or `null`.
  double? processFrame(Float64List frame);
}

/// Reads the shared tuning off a plain `SuperFluxOnsetDetector` instance's
/// PUBLIC fields (ADR 0524 D2) — never a re-typed literal.
({double delta, double lambda, double minIoiSec, int lag, int window, int hop})
_shippedTuning(int sampleRate) {
  final shipped = SuperFluxOnsetDetector(sampleRate: sampleRate);
  return (
    delta: shipped.delta,
    lambda: shipped.lambda,
    minIoiSec: shipped.minIoiSec,
    lag: shipped.lag,
    window: shipped.window,
    hop: shipped.hop,
  );
}

/// Builds one variant by id, freshly (no shared mutable state across cases —
/// each call to a benchmark case must start from a clean detector history).
OnsetDetectorVariant createOnsetDetectorVariant(
  OnsetVariantId id, {
  required int sampleRate,
}) {
  switch (id) {
    case OnsetVariantId.current:
      return _CurrentVariant(sampleRate: sampleRate);
    case OnsetVariantId.canonicalSuperFlux24:
      return _CanonicalSuperFlux24Variant(sampleRate: sampleRate);
    case OnsetVariantId.complexDomain:
      return _ComplexDomainVariant(sampleRate: sampleRate);
    case OnsetVariantId.spectralFlux:
      return _SpectralFluxVariant(sampleRate: sampleRate);
  }
}

// ---------------------------------------------------------------------
// current — the SHIPPED detector, called directly (ADR 0524 D1/5.2).
// ---------------------------------------------------------------------

final class _CurrentVariant implements OnsetDetectorVariant {
  _CurrentVariant({required int sampleRate})
    : _detector = SuperFluxOnsetDetector(sampleRate: sampleRate);

  final SuperFluxOnsetDetector _detector;

  @override
  final OnsetVariantId id = OnsetVariantId.current;

  @override
  int get window => _detector.window;

  @override
  int get hop => _detector.hop;

  @override
  double get delta => _detector.delta;

  @override
  double get lambda => _detector.lambda;

  @override
  double get minIoiSec => _detector.minIoiSec;

  @override
  double get lastFlux => _detector.lastFlux;

  @override
  String describe() =>
      'The shipped SuperFluxOnsetDetector, instantiated with its default '
      'constants — not copied or reimplemented (ADR 0524 D1/5.2).';

  @override
  double? processFrame(Float64List frame) => _detector.processFrame(frame);
}

// ---------------------------------------------------------------------
// Shared peak-picker (ADR 0524 D2): adaptive threshold + local-max
// confirmation + min-IOI + release hysteresis. A documented, hand-synced
// mirror of SuperFluxOnsetDetector's confirmation state machine — the
// tuning knobs (delta/lambda/minIoiSec/hop) are injected from the shipped
// detector's public fields; the shape knobs below are the hand-copied
// private mirror (ADR 0524 D2).
// ---------------------------------------------------------------------

/// Hand-synced mirror of `SuperFluxOnsetDetector._floor` — used by the
/// log-power flux path ([_CanonicalSuperFlux24Variant]) exactly as in the
/// shipped detector.
const double _logPowerFloor = -9.0;

final class _PeakPicker {
  _PeakPicker({
    required this.delta,
    required this.lambda,
    required this.minIoiSec,
    required this.sampleRate,
    required this.hop,
  });

  final double delta;
  final double lambda;
  final double minIoiSec;
  final int sampleRate;
  final int hop;

  // Hand-synced mirror of SuperFluxOnsetDetector's private shape constants
  // (ADR 0524 D2) — NOT read from the shipped file.
  static const int _medianFrames = 69;
  static const int _postFrames = 2;
  static const int _releaseFrames = 3;
  static const double _peakDecay = 0.985;
  static const double _peakRatio = 0.15;

  final ListQueue<double> _fluxWindow = ListQueue();
  final List<double> _fluxHist = [];
  final List<double> _thrHist = [];
  int _lastOnsetFrame = -1 << 30;
  int _belowStreak = _releaseFrames;
  bool _eligible = true;
  double _fluxPeak = 0;
  int _dropped = 0;

  /// The flux value most recently fed to [confirm] — mirrors the shipped
  /// detector's public `lastFlux` (ADR 0524 D8).
  double lastFlux = 0;

  /// Feed one frame's flux value; returns the confirmed onset TIME in
  /// seconds (`absC * hop / sampleRate`, the PEAK frame's START — same
  /// convention as the shipped detector's `processFrame`) or `null`. The
  /// DECISION instant (peak frame end plus the `_postFrames` confirmation
  /// delay) is a separate quantity the benchmark computes for algorithmic
  /// latency (`onset_ab_benchmark.dart`'s `decisionMs`), not this method's
  /// return value.
  double? confirm(double flux) {
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

    final c = _fluxHist.length - 1 - _postFrames;
    if (c < 0) return null;
    final fc = _fluxHist[c];
    if (fc <= _thrHist[c]) return null;
    if (fc < _peakRatio * _fluxPeak) return null;
    for (var i = math.max(0, c - _postFrames); i <= c + _postFrames; i++) {
      if (_fluxHist[i] > fc) return null;
    }
    final absC = c + _dropped;
    final minIoiFrames = (minIoiSec * sampleRate / hop).ceil();
    if (absC - _lastOnsetFrame < minIoiFrames) return null;
    if (!_eligible) return null;
    _lastOnsetFrame = absC;
    _eligible = false;
    _belowStreak = 0;

    if (_fluxHist.length > 4 * _medianFrames) {
      final drop = _fluxHist.length - 2 * _medianFrames;
      _fluxHist.removeRange(0, drop);
      _thrHist.removeRange(0, drop);
      _dropped += drop;
    }
    return absC * hop / sampleRate;
  }

  static double _median(ListQueue<double> q) {
    if (q.isEmpty) return 0;
    final sorted = q.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }
}

// ---------------------------------------------------------------------
// Shared STFT core (Hann window + fftea real FFT), mirroring the framing
// convention `LogMelExtractor` already uses.
// ---------------------------------------------------------------------

final class _Stft {
  _Stft(this.window)
    : _fft = FFT(window),
      _hann = Float64List(window),
      _windowed = Float64List(window) {
    for (var i = 0; i < window; i++) {
      _hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (window - 1));
    }
  }

  final int window;
  final FFT _fft;
  final Float64List _hann;
  final Float64List _windowed;

  /// The full-length complex spectrum; only bins `[0, window/2]` are the
  /// unique (non-conjugate) half (same convention `LogMelExtractor` uses).
  Float64x2List process(Float64List frame) {
    for (var i = 0; i < window; i++) {
      _windowed[i] = frame[i] * _hann[i];
    }
    return _fft.realFft(_windowed);
  }
}

// ---------------------------------------------------------------------
// canonicalSuperFlux24 — Böck–Widmer SuperFlux over a 24-band/octave
// log-frequency triangular filterbank built directly on the STFT (NOT
// CqtExtractor: its 2048-sample hop @ 22.05 kHz ≈ 93 ms is far too coarse
// for onset resolution, ADR 0524 Consequences).
// ---------------------------------------------------------------------

final class _LogFreqFilterbank {
  _LogFreqFilterbank({required this.sampleRate, required this.nFft})
    : nBins = nFft ~/ 2 + 1 {
    _build();
  }

  // Canonical SuperFlux resolution (ADR 0524 D1): 27.5 Hz (A0) to Nyquist,
  // 24 bins/octave (quarter-tone) — not configurable, this variant's whole
  // point is measuring THIS fixed resolution against the shipped 64-mel-band
  // filterbank.
  static const double fMin = 27.5;
  static const int binsPerOctave = 24;

  final int sampleRate;
  final int nFft;
  final int nBins;

  late final int bandCount;
  late final List<int> _filterStart;
  late final List<Float64List> _filterWeights;

  void _build() {
    final fMax = sampleRate / 2;
    final octaves = math.log(fMax / fMin) / math.ln2;
    final n = (octaves * binsPerOctave).floor();
    bandCount = n;
    final centerHz = List<double>.generate(
      n + 2,
      (i) => fMin * math.pow(2, i / binsPerOctave),
    );
    _filterStart = List<int>.filled(n, 0);
    _filterWeights = List<Float64List>.generate(n, (_) => Float64List(0));
    for (var m = 0; m < n; m++) {
      final lo = centerHz[m], ce = centerHz[m + 1], hi = centerHz[m + 2];
      var start = -1;
      final weights = <double>[];
      for (var k = 0; k < nBins; k++) {
        final f = k * sampleRate / 2 / (nBins - 1);
        double w;
        if (f >= lo && f <= ce && ce > lo) {
          w = (f - lo) / (ce - lo);
        } else if (f > ce && f <= hi && hi > ce) {
          w = (hi - f) / (hi - ce);
        } else {
          w = 0.0;
        }
        if (w > 0) {
          if (start < 0) start = k;
          weights.add(w);
        } else if (start >= 0 && f > hi) {
          break; // the non-zero run is contiguous
        }
      }
      _filterStart[m] = start < 0 ? 0 : start;
      _filterWeights[m] = Float64List.fromList(weights);
    }
  }

  Float64List apply(Float64List power) {
    final out = Float64List(bandCount);
    for (var m = 0; m < bandCount; m++) {
      final start = _filterStart[m];
      final w = _filterWeights[m];
      var acc = 0.0;
      for (var j = 0; j < w.length; j++) {
        acc += w[j] * power[start + j];
      }
      out[m] = acc;
    }
    return out;
  }
}

final class _CanonicalSuperFlux24Variant implements OnsetDetectorVariant {
  factory _CanonicalSuperFlux24Variant({required int sampleRate}) {
    final tuning = _shippedTuning(sampleRate);
    return _CanonicalSuperFlux24Variant._(
      window: tuning.window,
      hop: tuning.hop,
      lag: tuning.lag,
      delta: tuning.delta,
      lambda: tuning.lambda,
      minIoiSec: tuning.minIoiSec,
      stft: _Stft(tuning.window),
      filterbank: _LogFreqFilterbank(
        sampleRate: sampleRate,
        nFft: tuning.window,
      ),
      picker: _PeakPicker(
        delta: tuning.delta,
        lambda: tuning.lambda,
        minIoiSec: tuning.minIoiSec,
        sampleRate: sampleRate,
        hop: tuning.hop,
      ),
    );
  }

  _CanonicalSuperFlux24Variant._({
    required this.window,
    required this.hop,
    required this.lag,
    required this.delta,
    required this.lambda,
    required this.minIoiSec,
    required this._stft,
    required this._filterbank,
    required this._picker,
  });

  @override
  final OnsetVariantId id = OnsetVariantId.canonicalSuperFlux24;

  @override
  final int window;
  @override
  final int hop;
  @override
  final double delta;
  @override
  final double lambda;
  @override
  final double minIoiSec;
  final int lag;

  final _Stft _stft;
  final _LogFreqFilterbank _filterbank;
  final _PeakPicker _picker;
  final ListQueue<Float64List> _ring = ListQueue();

  @override
  double get lastFlux => _picker.lastFlux;

  @override
  String describe() =>
      'SuperFlux (Böck–Widmer 2013) over a 24-band/octave log-frequency '
      'triangular filterbank built directly on the STFT — the canonical '
      'quarter-tone resolution, not the shipped 64-band mel filterbank '
      '(ADR 0524 D1).';

  @override
  double? processFrame(Float64List frame) {
    assert(frame.length == window);
    final spectrum = _stft.process(frame);
    final nBins = window ~/ 2 + 1;
    final power = Float64List(nBins);
    for (var k = 0; k < nBins; k++) {
      final re = spectrum[k].x, im = spectrum[k].y;
      power[k] = re * re + im * im;
    }
    final bandPower = _filterbank.apply(power);
    final banded = Float64List(_filterbank.bandCount);
    for (var m = 0; m < banded.length; m++) {
      banded[m] = math.max(math.log(bandPower[m] + 1e-6), _logPowerFloor);
    }

    var flux = 0.0;
    if (_ring.length >= lag) {
      final ref = _ring.first;
      for (var m = 0; m < banded.length; m++) {
        var maxRef = ref[m];
        if (m > 0 && ref[m - 1] > maxRef) maxRef = ref[m - 1];
        if (m < banded.length - 1 && ref[m + 1] > maxRef) maxRef = ref[m + 1];
        final rise = banded[m] - maxRef;
        if (rise > 0) flux += rise;
      }
    }
    _ring.addLast(banded);
    if (_ring.length > lag) _ring.removeFirst();

    return _picker.confirm(flux);
  }
}

// ---------------------------------------------------------------------
// spectralFlux — half-wave rectified magnitude flux (Bello et al. 2005),
// the simplest baseline ODF: no phase term, no log domain.
// ---------------------------------------------------------------------

final class _SpectralFluxVariant implements OnsetDetectorVariant {
  factory _SpectralFluxVariant({required int sampleRate}) {
    final tuning = _shippedTuning(sampleRate);
    return _SpectralFluxVariant._(
      window: tuning.window,
      hop: tuning.hop,
      delta: tuning.delta,
      lambda: tuning.lambda,
      minIoiSec: tuning.minIoiSec,
      stft: _Stft(tuning.window),
      picker: _PeakPicker(
        delta: tuning.delta,
        lambda: tuning.lambda,
        minIoiSec: tuning.minIoiSec,
        sampleRate: sampleRate,
        hop: tuning.hop,
      ),
    );
  }

  _SpectralFluxVariant._({
    required this.window,
    required this.hop,
    required this.delta,
    required this.lambda,
    required this.minIoiSec,
    required this._stft,
    required this._picker,
  });

  @override
  final OnsetVariantId id = OnsetVariantId.spectralFlux;

  @override
  final int window;
  @override
  final int hop;
  @override
  final double delta;
  @override
  final double lambda;
  @override
  final double minIoiSec;

  final _Stft _stft;
  final _PeakPicker _picker;
  Float64List? _prevMag;

  @override
  double get lastFlux => _picker.lastFlux;

  @override
  String describe() =>
      'Half-wave rectified magnitude spectral flux: the sum of positive '
      'per-bin magnitude increases frame-over-frame, no phase term (Bello '
      'et al. 2005 baseline ODF).';

  @override
  double? processFrame(Float64List frame) {
    assert(frame.length == window);
    final spectrum = _stft.process(frame);
    final nBins = window ~/ 2 + 1;
    final mag = Float64List(nBins);
    for (var k = 0; k < nBins; k++) {
      final re = spectrum[k].x, im = spectrum[k].y;
      mag[k] = math.sqrt(re * re + im * im);
    }

    var flux = 0.0;
    final prev = _prevMag;
    if (prev != null) {
      for (var k = 0; k < nBins; k++) {
        final rise = mag[k] - prev[k];
        if (rise > 0) flux += rise;
      }
    }
    _prevMag = mag;
    return _picker.confirm(flux);
  }
}

// ---------------------------------------------------------------------
// complexDomain — complex-domain ODF (Duxbury/Bello): magnitude+phase are
// linearly extrapolated from the previous two frames per bin, and the flux
// is the summed magnitude of the deviation between the predicted and
// actual complex spectrum.
// ---------------------------------------------------------------------

final class _ComplexDomainVariant implements OnsetDetectorVariant {
  factory _ComplexDomainVariant({required int sampleRate}) {
    final tuning = _shippedTuning(sampleRate);
    return _ComplexDomainVariant._(
      window: tuning.window,
      hop: tuning.hop,
      delta: tuning.delta,
      lambda: tuning.lambda,
      minIoiSec: tuning.minIoiSec,
      stft: _Stft(tuning.window),
      picker: _PeakPicker(
        delta: tuning.delta,
        lambda: tuning.lambda,
        minIoiSec: tuning.minIoiSec,
        sampleRate: sampleRate,
        hop: tuning.hop,
      ),
    );
  }

  _ComplexDomainVariant._({
    required this.window,
    required this.hop,
    required this.delta,
    required this.lambda,
    required this.minIoiSec,
    required this._stft,
    required this._picker,
  });

  @override
  final OnsetVariantId id = OnsetVariantId.complexDomain;

  @override
  final int window;
  @override
  final int hop;
  @override
  final double delta;
  @override
  final double lambda;
  @override
  final double minIoiSec;

  final _Stft _stft;
  final _PeakPicker _picker;
  Float64List? _prevMag;
  Float64List? _prevPhase;
  Float64List? _prevPrevPhase;

  @override
  double get lastFlux => _picker.lastFlux;

  @override
  String describe() =>
      'Complex-domain onset detection function (Duxbury/Bello): magnitude '
      'and phase are linearly extrapolated from the previous two frames '
      'per bin, and the flux is the summed magnitude of the deviation '
      'between the predicted and actual complex spectrum.';

  @override
  double? processFrame(Float64List frame) {
    assert(frame.length == window);
    final spectrum = _stft.process(frame);
    final nBins = window ~/ 2 + 1;
    final mag = Float64List(nBins);
    final phase = Float64List(nBins);
    for (var k = 0; k < nBins; k++) {
      final re = spectrum[k].x, im = spectrum[k].y;
      mag[k] = math.sqrt(re * re + im * im);
      phase[k] = math.atan2(im, re);
    }

    var flux = 0.0;
    final prevMag = _prevMag;
    final prevPhase = _prevPhase;
    final prevPrevPhase = _prevPrevPhase;
    if (prevMag != null && prevPhase != null && prevPrevPhase != null) {
      for (var k = 0; k < nBins; k++) {
        final predictedPhase = _wrapPhase(2 * prevPhase[k] - prevPrevPhase[k]);
        final predictedRe = prevMag[k] * math.cos(predictedPhase);
        final predictedIm = prevMag[k] * math.sin(predictedPhase);
        final actualRe = spectrum[k].x, actualIm = spectrum[k].y;
        final devRe = actualRe - predictedRe;
        final devIm = actualIm - predictedIm;
        flux += math.sqrt(devRe * devRe + devIm * devIm);
      }
    }
    _prevPrevPhase = prevPhase;
    _prevPhase = phase;
    _prevMag = mag;
    return _picker.confirm(flux);
  }

  static double _wrapPhase(double phase) {
    var wrapped = phase;
    while (wrapped > math.pi) {
      wrapped -= 2 * math.pi;
    }
    while (wrapped < -math.pi) {
      wrapped += 2 * math.pi;
    }
    return wrapped;
  }
}
