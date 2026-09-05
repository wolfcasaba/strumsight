import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:strumsight/features/audio_analysis/public.dart';

import '../../domain/recognition/signal_quality_snapshot.dart';
import 'live_quality_thresholds.dart';

/// Streams raw PCM through the reused `SignalQualityMath` primitives (ADR
/// 0507 D1 — the mathematics is not reimplemented, only reused via the
/// `audio_analysis` public barrel) and turns the result into a debounced
/// [SignalQualitySnapshot].
///
/// Pure Dart, deterministic, platform-free: [addChunk] takes arbitrary-length
/// PCM (mic buffer size ≠ analysis block size, RAG chunk 001 pattern) and
/// [snapshot] always reflects the latest confirmed state. Audio quality only
/// — never a sound-source, speaker, or skill classifier (ADR 0224 §4).
class LiveSignalQualityAnalyzer {
  LiveSignalQualityAnalyzer({
    LiveQualityThresholds thresholds = LiveQualityThresholds.standard,
  }) : assert(
         thresholds.frameHop == thresholds.frameSize,
         'the accumulator below only supports non-overlapping blocks',
       ),
       _thresholds = thresholds,
       _accumulator = Float64List(thresholds.frameSize);

  final LiveQualityThresholds _thresholds;

  // A fixed, reused buffer for the block CURRENTLY filling — deliberately not
  // `SlidingFramer` (which owns a growable, boxed `List<double>` for the
  // general overlapping-window case): this analyzer only ever needs
  // non-overlapping blocks (`frameHop == frameSize`), so a plain indexed
  // Float64List accumulator does the same job with no list growth/shift.
  // This IS the "Live-oldali gyűjtő" (Live-side collector) the round brief
  // (§2/§3) asks this class to build — mechanical buffering, not DSP math.
  final Float64List _accumulator;
  int _accumulatorFill = 0;

  final ListQueue<Float64List> _history = ListQueue<Float64List>();

  int _blocksSeen = 0;
  double _lastPeakDbfs = 0;
  double _lastRmsDbfs = 0;
  double _lastClippedSampleRatio = 0;
  double _lastTonalness = 0;
  double _lastSilentRatio = 0;
  double _lastNoiseFloorDbfs = 0;
  double _lastRmsStdDevDb = 0;
  // Both strides gate a cache, not the FIRST computation: relying on
  // `_blocksSeen % stride == 0` alone would leave the very first
  // post-buffer-fill block reporting fabricated zeros whenever the buffer
  // size and stride don't happen to align (ADR 0507 D6 forbids exactly that).
  bool _statsComputedOnce = false;
  bool _tonalnessComputedOnce = false;

  SignalQualityState _confirmed = SignalQualityState.unknown;
  SignalQualityState? _pendingState;
  int _pendingStreak = 0;

  SignalQualitySnapshot _snapshot = SignalQualitySnapshot.unknown;

  /// The latest confirmed quality snapshot — cheap to read every frame.
  SignalQualitySnapshot get snapshot => _snapshot;

  /// Feed a PCM chunk (any length, -1..1). Raw audio never leaves this
  /// object — only the derived metrics do (ADR 0224 §1).
  void addChunk(List<double> chunk) {
    var index = 0;
    while (index < chunk.length) {
      final space = _accumulator.length - _accumulatorFill;
      final take = math.min(space, chunk.length - index);
      for (var i = 0; i < take; i++) {
        _accumulator[_accumulatorFill + i] = chunk[index + i];
      }
      _accumulatorFill += take;
      index += take;
      if (_accumulatorFill == _accumulator.length) {
        _processBlock(Float64List.fromList(_accumulator));
        _accumulatorFill = 0;
      }
    }
  }

  void _processBlock(Float64List block) {
    _history.addLast(block);
    while (_history.length > _thresholds.historyBlocks) {
      _history.removeFirst();
    }
    _blocksSeen++;

    if (_history.length < _thresholds.historyBlocks) {
      // Too little data yet — the true initial state, never a silent `good`
      // default (ADR 0507 D5).
      _confirmed = SignalQualityState.unknown;
      _pendingState = null;
      _pendingStreak = 0;
      _snapshot = SignalQualitySnapshot.unknown;
      return;
    }

    // Every metric — including the per-block level (peak/rms/clip) — is
    // throttled and cached between updates (ADR 0507 D9's pattern, extended
    // past just `tonalness`): computing even the cheap level primitives on
    // EVERY block measured over the CPU-cost acceptance budget (brief §6/6.1
    // row 6) once the whole stream is summed, because `peakDbfs`/`rmsDbfs`/
    // `clippedSampleRatio` each do their own O(block) pass. A live quality
    // indicator does not need sub-block-period reaction time; the numbers
    // and rationale are in `docs/rag/chunks/live-signal-quality.md`.
    if (_blocksSeen % _thresholds.statsStride == 0 || !_statsComputedOnce) {
      _statsComputedOnce = true;
      _lastPeakDbfs = SignalQualityMath.peakDbfs(block);
      _lastRmsDbfs = SignalQualityMath.rmsDbfs(block);
      _lastClippedSampleRatio = SignalQualityMath.clippedSampleRatio(block);

      // `rmsDbfs` (the reused primitive) is computed EXACTLY ONCE per
      // history block and reused for silence + noise-floor + stability
      // instead of calling `isSilentFrame`/`noiseFloorDbfsForFrames` (each
      // of which would silently recompute `rmsDbfs` a second/third time).
      // The FORMULAS stay identical — `isSilentFrame`'s
      // `<= silentSampleDbfs` comparison (via the exported
      // `QualityThresholds.standard`) and `noiseFloorDbfsForFrames`'s
      // nearest-rank 10th-percentile — only the redundant re-computation of
      // already-known `rmsDbfs` values is removed.
      final historyFrames = _history.toList(growable: false);
      final blockRmsDbfs = <double>[
        for (final frame in historyFrames) SignalQualityMath.rmsDbfs(frame),
      ];
      final silentSampleDbfs = QualityThresholds.standard.silentSampleDbfs;
      final silentBlocks = blockRmsDbfs
          .where((rms) => rms <= silentSampleDbfs)
          .length;
      _lastSilentRatio = silentBlocks / blockRmsDbfs.length;
      _lastNoiseFloorDbfs = _nearestRankPercentile(blockRmsDbfs, 0.10);
      _lastRmsStdDevDb = _standardDeviation(blockRmsDbfs);

      // The tonalness FFT is by far the most expensive primitive — run it
      // only every `tonalnessStride`th block (ADR 0507 D9), and only over
      // the most recent `tonalnessWindowSamples` (not the full history, and
      // wide enough to span multiple internal analysis frames — a
      // single-frame snapshot measured unreliable on envelope-modulated
      // signals like `speechLike`, since an infrequent single 2048-sample
      // sample can land in a near-silent envelope trough by pure chance).
      if (_blocksSeen % _thresholds.tonalnessStride == 0 ||
          !_tonalnessComputedOnce) {
        _tonalnessComputedOnce = true;
        _lastTonalness = SignalQualityMath.tonalness(
          _tailSamples(historyFrames, _thresholds.tonalnessWindowSamples),
        );
      }
    }
    final peakDbfs = _lastPeakDbfs;
    final rmsDbfs = _lastRmsDbfs;
    final clippedSampleRatio = _lastClippedSampleRatio;
    final silentRatio = _lastSilentRatio;
    final activeRegionRatio = 1 - silentRatio;
    final noiseFloorDbfs = _lastNoiseFloorDbfs;
    final tonalness = _lastTonalness;
    final rmsStdDevDb = _lastRmsStdDevDb;

    final raw = _classify(
      peakDbfs: peakDbfs,
      rmsDbfs: rmsDbfs,
      clippedSampleRatio: clippedSampleRatio,
      rmsStdDevDb: rmsStdDevDb,
      tonalness: tonalness,
    );
    _confirmed = _advanceHysteresis(raw);

    _snapshot = SignalQualitySnapshot(
      state: _confirmed,
      peakDbfs: peakDbfs,
      rmsDbfs: rmsDbfs,
      noiseFloorDbfs: noiseFloorDbfs,
      clippedSampleRatio: clippedSampleRatio,
      silentRatio: silentRatio,
      activeRegionRatio: activeRegionRatio,
      tonalness: tonalness,
    );
  }

  /// Priority order (highest first): clipping is always worth flagging on
  /// its own; instability is checked before quiet/loud because a wildly
  /// swinging level makes those two judgements unreliable; tonal checks run
  /// last, once level and stability are settled. Documented alongside the
  /// tuned numbers in `docs/rag/chunks/live-signal-quality.md`.
  SignalQualityState _classify({
    required double peakDbfs,
    required double rmsDbfs,
    required double clippedSampleRatio,
    required double rmsStdDevDb,
    required double tonalness,
  }) {
    if (clippedSampleRatio >= _thresholds.clippedRatioThreshold) {
      return SignalQualityState.clipping;
    }
    if (rmsStdDevDb >= _thresholds.unstableRmsStdDevDb) {
      return SignalQualityState.unstable;
    }
    if (rmsDbfs <= _thresholds.quietRmsDbfs) {
      return SignalQualityState.tooQuiet;
    }
    if (peakDbfs >= _thresholds.loudPeakDbfs) {
      return SignalQualityState.tooLoud;
    }
    if (tonalness <= _thresholds.noisyTonalnessMax) {
      return SignalQualityState.tooNoisy;
    }
    if (tonalness <= _thresholds.speechTonalnessMax) {
      return SignalQualityState.speechLike;
    }
    return SignalQualityState.good;
  }

  /// Hysteresis, not smoothing (ADR 0507 D4): a transition INTO
  /// [SignalQualityState.good] needs [LiveQualityThresholds.exitFrames]
  /// consecutive identical raw classifications (slow release — this also
  /// gates the very first `unknown` → `good` confirmation, D5); a transition
  /// into any other state needs [LiveQualityThresholds.enterFrames] (fast
  /// attack). The thresholds themselves never move to fight flicker.
  SignalQualityState _advanceHysteresis(SignalQualityState raw) {
    if (raw == _confirmed) {
      _pendingState = null;
      _pendingStreak = 0;
      return _confirmed;
    }
    if (raw == _pendingState) {
      _pendingStreak++;
    } else {
      _pendingState = raw;
      _pendingStreak = 1;
    }
    final needed = raw == SignalQualityState.good
        ? _thresholds.exitFrames
        : _thresholds.enterFrames;
    if (_pendingStreak >= needed) {
      _pendingState = null;
      _pendingStreak = 0;
      return raw;
    }
    return _confirmed;
  }

  /// The most recent [maxSamples] samples across [historyFrames] (already
  /// oldest → newest), for a `tonalness` call that spans more than one block.
  static Float64List _tailSamples(
    List<Float64List> historyFrames,
    int maxSamples,
  ) {
    var totalAvailable = 0;
    for (final frame in historyFrames) {
      totalAvailable += frame.length;
    }
    final windowLength = math.min(maxSamples, totalAvailable);
    final out = Float64List(windowLength);
    var skip = totalAvailable - windowLength;
    var writeIndex = 0;
    for (final frame in historyFrames) {
      for (var i = 0; i < frame.length; i++) {
        if (skip > 0) {
          skip--;
          continue;
        }
        out[writeIndex++] = frame[i];
      }
    }
    return out;
  }

  /// Nearest-rank percentile — the exact algorithm
  /// `SignalQualityMath.noiseFloorDbfsForFrames` uses internally, applied to
  /// the already-computed [blockRmsDbfs] instead of recomputing `rmsDbfs`
  /// from scratch a second time.
  static double _nearestRankPercentile(List<double> values, double percentile) {
    final sorted = List<double>.of(values)..sort();
    final rank = (sorted.length * percentile).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  static double _standardDeviation(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    var sumSquares = 0.0;
    for (final value in values) {
      final delta = value - mean;
      sumSquares += delta * delta;
    }
    return math.sqrt(sumSquares / values.length);
  }

  /// Resets to the true initial state: every buffered block, history entry
  /// and hysteresis counter is dropped (ADR 0507 D5; mirrors the reset shape
  /// of the pipeline components it lives alongside).
  void reset() {
    _accumulatorFill = 0;
    _history.clear();
    _blocksSeen = 0;
    _lastPeakDbfs = 0;
    _lastRmsDbfs = 0;
    _lastClippedSampleRatio = 0;
    _lastTonalness = 0;
    _lastSilentRatio = 0;
    _lastNoiseFloorDbfs = 0;
    _lastRmsStdDevDb = 0;
    _statsComputedOnce = false;
    _tonalnessComputedOnce = false;
    _confirmed = SignalQualityState.unknown;
    _pendingState = null;
    _pendingStreak = 0;
    _snapshot = SignalQualitySnapshot.unknown;
  }
}
