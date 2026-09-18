// A room the user is not playing in must not grow the detector's decision
// histories without bound.
//
// DEFECT: `_fluxHist` / `_thrHist` / `_riseBandsHist` take one entry per frame
// on BOTH the silence-gated and the analysed path, but the trim that bounds
// them sat after every early `return null` of the confirmation block — so it
// only ran on a CONFIRMED onset. Room tone or a quiet room confirms none, so
// the three lists grew at 172 frames/s (~35 MB/h at 1024/256 @ 44.1 kHz) and
// the first real onset then paid an O(n) `removeRange` on the audio path.
//
// The pins below are the INVARIANT (the histories stay bounded on EVERY
// frame), not the absence of a symptom, so they stay valid on both sides of
// any later retune of the trim constants.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/superflux_onset_detector.dart';

import '../../../support/synth.dart';

const _sr = 44100;

/// Frames of continuous input — 9.3 s of audio, and several times the largest
/// window the confirmation logic can consult.
const _totalFrames = 1600;

/// The ceiling this test holds the detector to. Deliberately expressed against
/// the frame count: a history that tracks run length fails it, a bounded one
/// passes with room for a retune of the trim constants.
const _historyCeiling = _totalFrames ~/ 4;

/// Stationary room tone: one broadband noise block repeated at the frame hop,
/// so every frame carries the SAME spectrum, plus a little fresh jitter.
/// Loud (RMS ~0.02 against the 0.008 silence gate) but with no attack anywhere
/// — amp hiss or air conditioning, the input a Live screen sits in while the
/// user is not playing.
Float64List _roomTone(int sampleCount, {required int period}) {
  final random = math.Random(20260918);
  final block = Float64List(period);
  for (var i = 0; i < period; i++) {
    block[i] = (random.nextDouble() * 2 - 1) * 0.035;
  }
  final out = Float64List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    out[i] = block[i % period] * (1 + (random.nextDouble() * 2 - 1) * 0.005);
  }
  return out;
}

void main() {
  test('above-silence room tone leaves the histories bounded', () {
    final detector = SuperFluxOnsetDetector(sampleRate: _sr);
    final signal = _roomTone(
      _totalFrames * detector.hop + detector.window,
      period: detector.hop,
    );
    final onsets = <double>[];
    var peakHistory = 0;
    var processed = 0;

    for (final frame in frames(signal, detector.window, detector.hop)) {
      final onset = detector.processFrame(frame);
      if (onset != null) onsets.add(onset);
      peakHistory = math.max(peakHistory, detector.decisionHistoryFrames);
      processed++;
    }

    // The premise: this signal confirms no onset, so the trim must not be
    // reachable only through one.
    expect(onsets, isEmpty);
    expect(processed, greaterThanOrEqualTo(_totalFrames));
    expect(peakHistory, greaterThan(0));
    expect(peakHistory, lessThan(_historyCeiling));
  });

  test('silence-gated frames leave the histories bounded', () {
    final detector = SuperFluxOnsetDetector(sampleRate: _sr);
    final silence = Float64List(_totalFrames * detector.hop + detector.window);
    var peakHistory = 0;
    var processed = 0;

    for (final frame in frames(silence, detector.window, detector.hop)) {
      expect(detector.processFrame(frame), isNull);
      peakHistory = math.max(peakHistory, detector.decisionHistoryFrames);
      processed++;
    }

    expect(detector.lastFlux, 0);
    expect(processed, greaterThanOrEqualTo(_totalFrames));
    expect(peakHistory, greaterThan(0));
    expect(peakHistory, lessThan(_historyCeiling));
  });

  test('the room tone takes the ANALYSED path on every frame', () {
    final detector = SuperFluxOnsetDetector(sampleRate: _sr);
    final signal = _roomTone(
      _totalFrames * detector.hop + detector.window,
      period: detector.hop,
    );
    var minRms = double.infinity;

    // Exactly the detector's own gate computation — if the quietest frame
    // clears it, none of them was silence-gated.
    for (final frame in frames(signal, detector.window, detector.hop)) {
      var sumSq = 0.0;
      for (var i = 0; i < frame.length; i++) {
        sumSq += frame[i] * frame[i];
      }
      minRms = math.min(minRms, math.sqrt(sumSq / frame.length));
    }

    expect(minRms, greaterThan(DspConfig.silenceRms));
  });
}
