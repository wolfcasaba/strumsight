// Flicker-tolerance test for LiveSignalQualityAnalyzer (E14-R05, ADR 0507
// D4): an input oscillating ±1 dB across the tooQuiet/good RMS boundary for
// 40 frames must change the CONFIRMED state at most once. The falsification
// evidence (enterFrames = exitFrames = 1 -> RED, reverted -> GREEN) is
// recorded in `docs/rounds/e14-r05-live-signal-quality-analyzer.md` §10.
//
// This test uses `statsStride: 1` / `tonalnessStride: 1` (production
// `frameSize`/`historyBlocks`/`enterFrames`/`exitFrames`/`quietRmsDbfs`
// unchanged): the CPU-cost throttle (`LiveQualityThresholds.standard.statsStride`
// = 64, docs/rag/chunks/live-signal-quality.md) recomputes the raw metric so
// rarely that a 40-block oscillation would never even reach a SECOND raw
// classification, making it impossible to tell hysteresis debouncing apart
// from "the metric simply hasn't been recomputed yet" — an unrelated concern
// already covered by the CPU-cost acceptance cell. This isolates the
// hysteresis STATE MACHINE itself, at the real production enter/exit values.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/recognition/signal_quality_snapshot.dart';
import 'package:strumsight/features/live/engine/quality/live_quality_thresholds.dart';
import 'package:strumsight/features/live/engine/quality/live_signal_quality_analyzer.dart';

const _sr = 44100.0;

const _unthrottledStats = LiveQualityThresholds(
  version: 'test-hysteresis-unthrottled-stats',
  frameSize: 4096,
  frameHop: 4096,
  historyBlocks: 4,
  enterFrames: 5,
  exitFrames: 8,
  statsStride: 1,
  tonalnessStride: 1,
  tonalnessWindowSamples: 4096,
  quietRmsDbfs: -40.0,
  loudPeakDbfs: -2.0,
  clippedRatioThreshold: 0.001,
  unstableRmsStdDevDb: 15.0,
  noisyTonalnessMax: 0.25,
  speechTonalnessMax: 0.5,
);

List<double> _sineBlock({required double amp, double freqHz = 220}) =>
    List<double>.generate(
      _unthrottledStats.frameSize,
      (i) => amp * math.sin(2 * math.pi * freqHz * i / _sr),
    );

/// Amplitude for a target sine RMS in dBFS (rmsAmplitude = amp / sqrt(2)).
double _ampForRmsDbfs(double dbfs) =>
    math.pow(10, dbfs / 20).toDouble() * math.sqrt2;

void main() {
  test('oscillating ±1 dB across the tooQuiet/good boundary changes state at '
      'most once over 40 frames', () {
    final analyzer = LiveSignalQualityAnalyzer(thresholds: _unthrottledStats);
    final quietThreshold = _unthrottledStats.quietRmsDbfs;

    // Lead-in: a comfortably "good" level, long enough (historyBlocks +
    // exitFrames + margin) to establish a confirmed baseline before the
    // oscillation begins.
    for (var i = 0; i < 20; i++) {
      analyzer.addChunk(_sineBlock(amp: 0.3));
    }
    final baseline = analyzer.snapshot.state;
    expect(baseline, SignalQualityState.good); // sanity: lead-in worked

    // ±1 dB around the tooQuiet boundary: one side raw-classifies
    // `tooQuiet`, the other `good` — exactly the flicker case hysteresis
    // exists for.
    final aboveAmp = _ampForRmsDbfs(quietThreshold + 1);
    final belowAmp = _ampForRmsDbfs(quietThreshold - 1);

    final states = <SignalQualityState>[];
    for (var i = 0; i < 40; i++) {
      final amp = i.isEven ? aboveAmp : belowAmp;
      analyzer.addChunk(_sineBlock(amp: amp));
      states.add(analyzer.snapshot.state);
    }

    var transitions = 0;
    var previous = baseline;
    for (final state in states) {
      if (state != previous) transitions++;
      previous = state;
    }

    expect(
      transitions,
      lessThanOrEqualTo(1),
      reason:
          'raw states per oscillating frame: $states (must not flicker '
          'frame-by-frame under production hysteresis)',
    );
  });
}
