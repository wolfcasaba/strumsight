// Fixture-matrix for LiveSignalQualityAnalyzer (E14-R05, ADR 0507). Every
// fixture is deterministic (fixed `math.Random` seeds, no wall-clock), so the
// clipping/silence cells are 100% reproducible by construction — never a
// probabilistic pass. Thresholds and the classification priority order are
// documented in `docs/rag/chunks/live-signal-quality.md`.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/recognition/signal_quality_snapshot.dart';
import 'package:strumsight/features/live/engine/quality/live_quality_thresholds.dart';
import 'package:strumsight/features/live/engine/quality/live_signal_quality_analyzer.dart';

const _sr = 44100.0;

List<double> _sine({
  required int n,
  required double amp,
  double freqHz = 220,
  double sampleRate = _sr,
}) => List<double>.generate(
  n,
  (i) => amp * math.sin(2 * math.pi * freqHz * i / sampleRate),
);

List<double> _whiteNoise({required int n, required double amp, int seed = 7}) {
  final r = math.Random(seed);
  return List<double>.generate(n, (_) => amp * (r.nextDouble() * 2 - 1));
}

List<double> _hardClipSquare({
  required int n,
  double freqHz = 220,
  double sampleRate = _sr,
}) => List<double>.generate(n, (i) {
  final s = math.sin(2 * math.pi * freqHz * i / sampleRate);
  return s >= 0 ? 1.0 : -1.0;
});

/// AM-modulated formant-like mix + a low noise floor — a spectral proxy for
/// speech, never a real speaker/source model (ADR 0224 §4 boundary).
List<double> _speechLike({required int n, int seed = 11}) {
  final r = math.Random(seed);
  return List<double>.generate(n, (i) {
    final t = i / _sr;
    final env = 0.5 + 0.5 * math.sin(2 * math.pi * 6 * t);
    final f1 = 0.35 * math.sin(2 * math.pi * 700 * t);
    final f2 = 0.2 * math.sin(2 * math.pi * 1200 * t);
    final f3 = 0.12 * math.sin(2 * math.pi * 2400 * t);
    final noise = 0.06 * (r.nextDouble() * 2 - 1);
    return (env * (f1 + f2 + f3) + noise).clamp(-1.0, 1.0);
  });
}

/// One cycle (4 blocks at the standard 4096-sample frame size — the exact
/// `historyBlocks` window) of wildly swinging level: loud → silent → quiet →
/// loud-at-a-different-pitch. Segment length matches `frameSize` so each
/// completed block predominantly reflects ONE segment, not an averaged mix.
List<double> _unstableBurstCycle() {
  final segment = LiveQualityThresholds.standard.frameSize; // 4096
  return [
    ..._sine(n: segment, amp: 0.7),
    ...List<double>.filled(segment, 0.0),
    ..._sine(n: segment, amp: 0.05),
    ..._sine(n: segment, amp: 0.8, freqHz: 900),
  ];
}

List<double> _unstable({required int n}) {
  final cycle = _unstableBurstCycle();
  final out = <double>[];
  while (out.length < n) {
    out.addAll(cycle);
  }
  return out.sublist(0, n);
}

/// Long enough to clear the buffer-fill gate (`historyBlocks` = 4) AND the
/// slower hysteresis confirmation (`exitFrames` = 8) with margin, using the
/// real production thresholds — this exercises the full streaming path, not
/// just raw classification.
const _longEnough = 98304; // 24 blocks @ 4096 samples

SignalQualitySnapshot _runFixture(List<double> samples, {int chunkSize = 517}) {
  final analyzer = LiveSignalQualityAnalyzer();
  for (var i = 0; i < samples.length; i += chunkSize) {
    final end = math.min(i + chunkSize, samples.length);
    analyzer.addChunk(samples.sublist(i, end));
  }
  return analyzer.snapshot;
}

void _expectFullyMeasured(SignalQualitySnapshot snapshot) {
  expect(snapshot.peakDbfs, isNotNull);
  expect(snapshot.rmsDbfs, isNotNull);
  expect(snapshot.noiseFloorDbfs, isNotNull);
  expect(snapshot.clippedSampleRatio, isNotNull);
  expect(snapshot.silentRatio, isNotNull);
  expect(snapshot.activeRegionRatio, isNotNull);
  expect(snapshot.tonalness, isNotNull);
}

void main() {
  test(
    'unknown — before the history buffer fills, no metric is fabricated',
    () {
      // Well under historyBlocks(4) * frameSize(4096) = 16384 samples.
      final snapshot = _runFixture(_sine(n: 8000, amp: 0.3));
      expect(snapshot, equals(SignalQualitySnapshot.unknown));
      expect(snapshot.state, SignalQualityState.unknown);
    },
  );

  test('good — a clean, steady tone at a healthy level', () {
    final snapshot = _runFixture(_sine(n: _longEnough, amp: 0.3));
    expect(snapshot.state, SignalQualityState.good);
    _expectFullyMeasured(snapshot);
  });

  test('good — a realistic multi-harmonic chord-like signal', () {
    const openStrings = [82.4, 110.0, 146.8, 196.0, 246.9, 329.6];
    final chord = List<double>.generate(_longEnough, (i) {
      var v = 0.0;
      for (final f in openStrings) {
        v += (0.3 / openStrings.length) * math.sin(2 * math.pi * f * i / _sr);
      }
      return v;
    });
    final snapshot = _runFixture(chord);
    expect(snapshot.state, SignalQualityState.good);
  });

  test('tooQuiet — a weak but present tone', () {
    final snapshot = _runFixture(_sine(n: _longEnough, amp: 0.01));
    expect(snapshot.state, SignalQualityState.tooQuiet);
    _expectFullyMeasured(snapshot);
  });

  test('tooLoud — near full-scale but not clipped', () {
    final snapshot = _runFixture(_sine(n: _longEnough, amp: 0.9));
    expect(snapshot.state, SignalQualityState.tooLoud);
    expect(snapshot.clippedSampleRatio, 0.0);
    _expectFullyMeasured(snapshot);
  });

  test('clipping — a hard-clipped square wave, 100% reproducible', () {
    final snapshot = _runFixture(_hardClipSquare(n: _longEnough));
    expect(snapshot.state, SignalQualityState.clipping);
    expect(snapshot.clippedSampleRatio, 1.0);
    _expectFullyMeasured(snapshot);
  });

  test('tooNoisy — broadband white noise at a moderate level', () {
    final snapshot = _runFixture(_whiteNoise(n: _longEnough, amp: 0.3));
    expect(snapshot.state, SignalQualityState.tooNoisy);
    _expectFullyMeasured(snapshot);
  });

  test(
    'speechLike — a spectral proxy only, never a speaker classification',
    () {
      final snapshot = _runFixture(_speechLike(n: _longEnough));
      expect(snapshot.state, SignalQualityState.speechLike);
      _expectFullyMeasured(snapshot);
    },
  );

  test(
    'unstable — a wildly swinging level over the rolling history window',
    () {
      final snapshot = _runFixture(_unstable(n: _longEnough));
      expect(snapshot.state, SignalQualityState.unstable);
      _expectFullyMeasured(snapshot);
    },
  );

  test('silence — RMS floor, 100% reproducible', () {
    final snapshot = _runFixture(List<double>.filled(_longEnough, 0.0));
    // Digital silence is the deepest case of "too quiet", not a distinct
    // state (ADR 0507 §2 — no new state vocabulary beyond the brief's eight).
    expect(snapshot.state, SignalQualityState.tooQuiet);
    expect(snapshot.rmsDbfs, closeTo(-120.0, 0.01));
    _expectFullyMeasured(snapshot);
  });

  group('clippedSampleRatio boundary — inclusive on the clipping side', () {
    // clippedRatioThreshold (0.001, reused from
    // QualityThresholds.standard.clippedRatioWarning) * frameSize(3000) = 3
    // exactly: python3 -c "print(0.001 * 3000)" -> 3.0. historyBlocks/enter/
    // exitFrames = 1 so a single block's raw classification is immediately
    // confirmed — this group tests pure classification, not hysteresis (that
    // is `live_signal_quality_hysteresis_test.dart`'s job).
    const boundaryThresholds = LiveQualityThresholds(
      version: 'test-clip-boundary',
      frameSize: 3000,
      frameHop: 3000,
      historyBlocks: 1,
      enterFrames: 1,
      exitFrames: 1,
      statsStride: 1,
      tonalnessStride: 1,
      tonalnessWindowSamples: 3000,
      quietRmsDbfs: -40.0,
      loudPeakDbfs: -2.0,
      clippedRatioThreshold: 0.001,
      unstableRmsStdDevDb: 15.0,
      noisyTonalnessMax: 0.25,
      speechTonalnessMax: 0.5,
    );

    List<double> blockWithClippedCount(int clippedCount) {
      final block = _sine(n: 3000, amp: 0.3, freqHz: 220);
      for (var i = 0; i < clippedCount; i++) {
        block[i * 37] = 1.0; // spread out — no natural overlap at amp 0.3
      }
      return block;
    }

    test('below the threshold (2/3000 = 0.000667) is NOT clipping', () {
      final analyzer = LiveSignalQualityAnalyzer(
        thresholds: boundaryThresholds,
      );
      analyzer.addChunk(blockWithClippedCount(2));
      // The two full-scale samples still make the block "the level's own
      // appropriate state" (peak 0 dBFS -> tooLoud), matching the brief's
      // §6.1 wording for the below-threshold cell — just never `clipping`.
      expect(analyzer.snapshot.state, isNot(SignalQualityState.clipping));
      expect(analyzer.snapshot.clippedSampleRatio, closeTo(2 / 3000, 1e-9));
    });

    test(
      'exactly at the threshold (3/3000 = 0.001) IS clipping (inclusive)',
      () {
        final analyzer = LiveSignalQualityAnalyzer(
          thresholds: boundaryThresholds,
        );
        analyzer.addChunk(blockWithClippedCount(3));
        expect(analyzer.snapshot.state, SignalQualityState.clipping);
        expect(analyzer.snapshot.clippedSampleRatio, closeTo(0.001, 1e-9));
      },
    );

    test('above the threshold (4/3000) is clipping', () {
      final analyzer = LiveSignalQualityAnalyzer(
        thresholds: boundaryThresholds,
      );
      analyzer.addChunk(blockWithClippedCount(4));
      expect(analyzer.snapshot.state, SignalQualityState.clipping);
      expect(analyzer.snapshot.clippedSampleRatio, closeTo(4 / 3000, 1e-9));
    });
  });
}
