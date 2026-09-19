// MEASUREMENT: does the calibration round trip actually work, end to end?
//
// `strum_latency_provider.dart` and `gradeRhythm`'s `timingCalibrationUs` are
// covered by unit cells that hand them numbers. What those cells cannot say is
// whether the WHOLE chain works on audio: synthesised strums → the real
// `LivePipeline`'s onset detection → `LatencyCalibrator`'s median → the
// correction → a timing score.
//
// That matters because the chain has a step nobody has measured in this role.
// The calibrator's input is `latestStrumTime`, whatever the ENGINE says — not the
// true acoustic onset. If the detector carried its own systematic lead or lag,
// the calibration would silently absorb it and call it device latency. Feeding
// audio with an exactly known offset is the only way to see that.
//
// What this CANNOT measure, said plainly: the human half. A real learner's
// anticipation (negative mean asynchrony) and a real device's display↔microphone
// skew are not in here, and cannot be — these strums are placed by arithmetic.
// This measures that the machinery recovers an offset it is given, which is the
// half that can be checked without a guitar in the room.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/latency_calibrator.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_grading.dart';
import 'package:strumsight/features/curriculum/domain/rhythm_grid.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';

const int _sampleRate = 44100;

/// One plucked string, physically modelled (Karplus-Strong), faded out.
///
/// The fade is not cosmetic: a truncated decay ENDS ON A STEP, a step is a real
/// broadband transient, and the detector is right to hear it. That cost a full
/// false measurement once already
/// (`test/features/live/onset_double_trigger_diagnosis_test.dart`).
List<double> _pluck({
  required double freqHz,
  required double seconds,
  required int seed,
  double damping = 0.996,
  double amplitude = 0.25,
}) {
  final length = (seconds * _sampleRate).round();
  final delay = math.max(2, (_sampleRate / freqHz).round());
  final random = math.Random(seed);
  final buffer = List<double>.generate(
    delay,
    (_) => random.nextDouble() * 2 - 1,
  );
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 1; i < buffer.length; i++) {
      buffer[i] = (buffer[i] + buffer[i - 1]) / 2;
    }
  }
  final out = List<double>.filled(length, 0);
  var index = 0;
  for (var n = 0; n < length; n++) {
    final current = buffer[index];
    final next = buffer[(index + 1) % delay];
    out[n] = current * amplitude;
    buffer[index] = damping * (current + next) / 2;
    index = (index + 1) % delay;
  }
  final fade = (0.03 * _sampleRate).round();
  for (var i = 0; i < fade && i < length; i++) {
    out[length - 1 - i] *= i / fade;
  }
  return out;
}

/// An open-E-shaped downstroke starting at [atSec]: six strings met in order,
/// 22 ms apart, which is what makes a strum a strum rather than a chord stab.
void _addStrum(List<double> pcm, double atSec) {
  const freqs = [82.41, 123.47, 164.81, 207.65, 246.94, 329.63];
  for (var i = 0; i < freqs.length; i++) {
    final start = ((atSec + i * 0.022) * _sampleRate).round();
    final tone = _pluck(
      freqHz: freqs[i],
      seconds: 0.42,
      seed: 900 + i * 13,
      damping: freqs[i] < 150 ? 0.9975 : 0.9955,
    );
    for (var j = 0; j < tone.length; j++) {
      final at = start + j;
      if (at >= 0 && at < pcm.length) pcm[at] += tone[j];
    }
  }
}

/// Onsets the ENGINE reports, in seconds on the engine clock.
List<double> _detectedOnsets(List<double> pcm) {
  final pipeline = LivePipeline(sampleRate: _sampleRate);
  final out = <double>[];
  var lastSeq = 0;
  const chunk = 1024;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = math.min(i + chunk, pcm.length);
    for (final frame in pipeline.addChunk(pcm.sublist(i, end))) {
      if (frame.strumSeq > lastSeq) {
        lastSeq = frame.strumSeq;
        out.add(frame.latestStrumTime);
      }
    }
  }
  return out;
}

/// A performance: [count] downstrokes, one per beat, every one [offsetSec] late.
/// A whole BEAT of lead-in, not an arbitrary quarter second.
///
/// The calibrator folds each onset to its NEAREST beat, so a fractional lead-in
/// makes the expected answer depend on which side of the midpoint the sum lands —
/// the first version of this file used 0.25 s and derived the wrong expectation
/// from it (arithmetic said -170 ms; I had written +80). A whole beat removes the
/// ambiguity: whatever offset goes in is the offset that must come out.
const double leadInSec = 0.5;

List<double> _performance({
  required double beatSec,
  required double offsetSec,
  required int count,
  double jitterSec = 0,
  int seed = 7,
}) {
  final random = math.Random(seed);
  final pcm = List<double>.filled(
    ((count * beatSec + offsetSec + 1.0) * _sampleRate).round(),
    0,
  );
  for (var i = 0; i < count; i++) {
    final jitter = jitterSec == 0
        ? 0.0
        : (random.nextDouble() * 2 - 1) * jitterSec;
    _addStrum(pcm, leadInSec + i * beatSec + offsetSec + jitter);
  }
  return pcm;
}

void main() {
  const beatSec = 0.5; // 120 bpm
  const strumCount = 8;

  ({double? offsetSec, double jitterSec, int samples}) calibrate(
    List<double> pcm,
  ) {
    final calibrator = LatencyCalibrator(beatPeriodSec: beatSec, minSamples: 5);
    for (final onset in _detectedOnsets(pcm)) {
      calibrator.registerTap(onset);
    }
    return (
      offsetSec: calibrator.offsetSec,
      jitterSec: calibrator.jitterSec,
      samples: calibrator.sampleCount,
    );
  }

  test('MEASURE: the calibration recovers an offset it was never told', () {
    // 80 ms late, the size of skew that destroys an attempt uncorrected.
    const injected = 0.080;
    final result = calibrate(
      _performance(beatSec: beatSec, offsetSec: injected, count: strumCount),
    );

    expect(result.offsetSec, isNotNull, reason: 'enough strums were detected');
    final measuredMs = result.offsetSec! * 1000;
    final engineBiasMs = measuredMs - injected * 1000;
    // ignore: avoid_print
    print(
      'injected ${(injected * 1000).toStringAsFixed(0)} ms '
      '-> measured ${measuredMs.toStringAsFixed(1)} ms '
      '| ENGINE BIAS ${engineBiasMs.toStringAsFixed(1)} ms '
      '(jitter ${(result.jitterSec * 1000).toStringAsFixed(1)} ms, '
      '${result.samples} samples)',
    );

    // The gap between what went in and what came out IS the engine's own onset
    // bias, and this is the only place it gets isolated in this role: the
    // calibration cannot tell such a bias from device latency, so it would be
    // absorbed silently and attributed to the learner's hardware.
    expect(
      engineBiasMs.abs(),
      lessThan(10),
      reason:
          'the detector must not contribute a bias of its own; the independent '
          'onset-placement measurement puts it at 0.0-3.4 ms, and anything much '
          'larger here would mean the calibration is absorbing engine error',
    );
    // And the detection has to be consistent enough to be worth a median at all.
    expect(result.jitterSec, lessThan(0.01));
  });

  test('MEASURE: an uneven performance is refused, not averaged', () {
    // 120 ms of jitter on a 500 ms beat. A median would still produce a number;
    // `isStable` is what stops it being saved and inherited by every later score.
    final result = calibrate(
      _performance(
        beatSec: beatSec,
        offsetSec: 0.080,
        count: strumCount,
        jitterSec: 0.12,
      ),
    );
    final calibrator = LatencyCalibrator(beatPeriodSec: beatSec, minSamples: 5);
    for (final onset in _detectedOnsets(
      _performance(
        beatSec: beatSec,
        offsetSec: 0.080,
        count: strumCount,
        jitterSec: 0.12,
      ),
    )) {
      calibrator.registerTap(onset);
    }
    // ignore: avoid_print
    print(
      'jittered: jitter ${(result.jitterSec * 1000).toStringAsFixed(1)} ms, '
      'stable=${calibrator.isStable}',
    );
    expect(
      result.jitterSec,
      greaterThan(0.04),
      reason: 'a ±120 ms performance must not read as consistent',
    );
    expect(calibrator.isStable, isFalse);
  });

  test('MEASURE: the round trip — calibrate, then score the same player', () {
    // The whole point, end to end. The same synthetic player performs twice. The
    // first run calibrates; the second is graded with and without it.
    const injected = 0.080;
    final calibration = calibrate(
      _performance(beatSec: beatSec, offsetSec: injected, count: strumCount),
    );
    expect(calibration.offsetSec, isNotNull);
    final calibrationUs = (calibration.offsetSec! * 1e6).round();

    // A second performance by the same player, scored against a four-beat
    // down-quarters bar starting at its first beat.
    final onsets = _detectedOnsets(
      _performance(beatSec: beatSec, offsetSec: injected, count: 4, seed: 21),
    );
    final strokes = [
      for (final onset in onsets)
        DetectedStroke(
          atUs: (onset * 1e6).round(),
          direction: StrumDirection.down,
          isConfirmed: true,
        ),
    ];
    final grid = RhythmGrid.pendulum(
      subdivision: RhythmSubdivision.quarter,
      struck: const [true, true, true, true],
    );
    // Bar 1 beat 1 is the first beat the calibrator folded to: the lead-in is
    // half a beat, so the grid starts one beat in.
    final startUs = (beatSec * 1e6).round();

    final uncorrected = gradeRhythm(
      grid,
      bpm: 120,
      bars: 1,
      strokes: strokes,
      startUs: startUs,
    );
    final corrected = gradeRhythm(
      grid,
      bpm: 120,
      bars: 1,
      strokes: strokes,
      startUs: startUs,
      timingCalibrationUs: calibrationUs,
    );

    // ignore: avoid_print
    print(
      'round trip: uncorrected heard ${uncorrected.heard}/${uncorrected.notatedStrokes} '
      '(reportable ${uncorrected.isReportable}) | '
      'corrected heard ${corrected.heard}/${corrected.notatedStrokes} '
      'mean |err| ${((corrected.meanAbsTimingErrorUs ?? 0) / 1000).toStringAsFixed(1)} ms '
      'bias ${((corrected.timingBiasUs ?? 0) / 1000).toStringAsFixed(1)} ms '
      'shape ${corrected.timingShape}',
    );

    expect(
      corrected.heard,
      greaterThanOrEqualTo(uncorrected.heard),
      reason: 'the correction can only ever help a consistently offset player',
    );
    expect(
      corrected.hasTimingReport,
      isTrue,
      reason: 'a calibrated device with full coverage may report timing',
    );
    // The residual is what the player's own unevenness leaves behind, not the
    // device's skew — so it must be well inside the tolerance window.
    expect(
      corrected.meanAbsTimingErrorUs!,
      lessThan(rhythmToleranceUs),
      reason:
          'after correcting the measured offset, what is left must be smaller '
          'than the window the recogniser is measured against',
    );
  });
}
