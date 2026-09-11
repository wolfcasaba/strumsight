// MEASUREMENT: what a strum's reported timestamp means, and how late the frame
// carrying it arrives.
//
// This exists because the Curriculum rhythm pillar is about to score TIMING, and
// scoring needs to know which number to trust. `LiveFrame`'s doc comment already
// says the frame ARRIVES 85–165 ms late (measured, r145) — but a doc comment is
// not a measurement I have taken, and the pillar's whole premise is that the app
// never tells a learner something it has not verified.
//
// So this drives the REAL `LivePipeline` with a synthetic signal whose onsets are
// known exactly, and measures two different things that are easy to confuse:
//
//   placement error = latestStrumTime − trueOnset
//       How wrong the app would be about WHEN the stroke happened. This is the
//       number that decides whether timing can be scored at all against a ±50 ms
//       window.
//
//   reporting lag  = engineTimeSec − latestStrumTime
//       How long after the stroke the app LEARNS about it. This one does not
//       affect placement — it only delays feedback — as long as the grid and the
//       detection are read on the same clock.
//
// Confusing the two is exactly the mistake that would tell a learner they were
// late when they were not: timestamping a stroke at frame-arrival folds the
// second number into the first.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/onset_matching.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

const int _sampleRate = 44100;

/// One plucked string: an instant attack and an exponential decay, with a few
/// harmonics so the spectral-flux detector sees a real note rather than a click.
void _addPluck(
  List<double> pcm, {
  required double atSec,
  required double freqHz,
  double amplitude = 0.5,
  double decaySec = 0.55,
}) {
  final start = (atSec * _sampleRate).round();
  final length = (decaySec * _sampleRate).round();
  for (var i = 0; i < length; i++) {
    final index = start + i;
    if (index < 0 || index >= pcm.length) continue;
    final t = i / _sampleRate;
    final envelope = math.exp(-t / (decaySec / 4));
    var sample = 0.0;
    for (var harmonic = 1; harmonic <= 6; harmonic++) {
      sample +=
          math.sin(2 * math.pi * freqHz * harmonic * t) / (harmonic * harmonic);
    }
    // Fade the last 30 ms out. A synthesis that simply STOPS ends on a step, and
    // a step is a real broadband transient the detector is right to hear — six
    // of them 22 ms apart produced phantom strums in this file's first run.
    // Diagnosed in `onset_double_trigger_diagnosis_test.dart`.
    final remaining = (length - i) / _sampleRate;
    final fade = remaining < 0.03 ? remaining / 0.03 : 1.0;
    pcm[index] += amplitude * envelope * fade * sample;
  }
}

/// A strum: six strings struck in sequence, ~22 ms apart, low-to-high for a
/// downstroke. The spread is real — a pick crosses the strings one at a time —
/// and it is why "the onset" is not a single instant.
void _addStrum(
  List<double> pcm, {
  required double atSec,
  bool down = true,
  double perStringSec = 0.022,
}) {
  // E2 A2 D3 G3 B3 E4, in string order from the thickest.
  const freqs = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63];
  final ordered = down ? freqs : freqs.reversed.toList();
  for (var i = 0; i < ordered.length; i++) {
    _addPluck(
      pcm,
      atSec: atSec + i * perStringSec,
      freqHz: ordered[i],
      amplitude: 0.35,
    );
  }
}

/// Feeds [pcm] through the pipeline in realistic chunks and returns the frames.
List<LiveFrame> _run(List<double> pcm) {
  final pipeline = LivePipeline(sampleRate: _sampleRate);
  final frames = <LiveFrame>[];
  const chunk = 1024;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = math.min(i + chunk, pcm.length);
    frames.addAll(pipeline.addChunk(pcm.sublist(i, end)));
  }
  return frames;
}

/// The frame on which each distinct strum first appears.
List<LiveFrame> _firstFramePerStrum(List<LiveFrame> frames) {
  final out = <LiveFrame>[];
  var lastSeq = 0;
  for (final frame in frames) {
    if (frame.strumSeq > lastSeq) {
      lastSeq = frame.strumSeq;
      out.add(frame);
    }
  }
  return out;
}

void main() {
  // Four downstrokes on the beat at 80 bpm — the course's own eighth-note
  // tempo, so the measurement is taken where the exercise actually lives.
  const beatSec = 60.0 / 80.0;
  const onsets = [0.40, 0.40 + beatSec, 0.40 + 2 * beatSec, 0.40 + 3 * beatSec];

  late List<LiveFrame> reported;

  setUpAll(() {
    final pcm = List<double>.filled((6.0 * _sampleRate).round(), 0);
    for (final onset in onsets) {
      _addStrum(pcm, atSec: onset);
    }
    reported = _firstFramePerStrum(_run(pcm));
  });

  test('the synthetic strums are detected at all', () {
    // Without this the numbers below would be vacuous. If this ever fails, the
    // measurement has stopped measuring rather than the engine having improved.
    expect(
      reported.length,
      greaterThanOrEqualTo(2),
      reason: 'no strums reported — the rest of this file measures nothing',
    );
  });

  test('PLACEMENT: latestStrumTime lands on the true onset, not on arrival', () {
    // The claim the timing score rests on. Detections are matched one-to-one to
    // the true onsets with the SHARED maximum-cardinality matcher — the same one
    // the recogniser's own metrics and the rhythm grader use — so a detection
    // cannot be counted twice and the greedy under-count of L269 cannot creep in.
    final matchOfDetected = matchWithinTolerance(
      expected: [for (final onset in onsets) (onset * 1e6).round()],
      detected: [
        for (final frame in reported) (frame.latestStrumTime * 1e6).round(),
      ],
      tolerance: 50000,
    );
    final matchedErrorsMs = <double>[];
    for (var j = 0; j < matchOfDetected.length; j++) {
      final i = matchOfDetected[j];
      if (i == -1) continue;
      matchedErrorsMs.add((reported[j].latestStrumTime - onsets[i]) * 1000);
    }
    final unmatched = matchOfDetected.where((i) => i == -1).length;

    // ignore: avoid_print
    print(
      'MEASURED placement error ms (matched): '
      '${matchedErrorsMs.map((e) => e.toStringAsFixed(1)).join(', ')}',
    );
    // ignore: avoid_print
    print(
      'MEASURED detections: ${reported.length} for ${onsets.length} strums '
      '($unmatched unmatched)',
    );

    expect(
      matchedErrorsMs.length,
      onsets.length,
      reason:
          'every strum must be found once for the errors below to mean anything',
    );
    for (final error in matchedErrorsMs) {
      expect(
        error.abs(),
        lessThan(10),
        reason:
            'latestStrumTime is the ONSET time, so it should sit within a few ms '
            'of the true onset — not 85-165 ms late like the frame that carries it',
      );
    }
  });

  test('NO surplus detections — one strum reported per strum', () {
    // This file's first run measured about twice as many reported strums as
    // there were strums and recorded it as unexplained. It is now explained, and
    // the engine is NOT at fault: the synthesis ended on a step, and six steps
    // 22 ms apart are a real transient. With the truncation faded (see
    // `_addPluck`) the surplus is zero. Kept as a cell so the stimulus cannot
    // silently regress into testing its own artifacts again.
    final matchOfDetected = matchWithinTolerance(
      expected: [for (final onset in onsets) (onset * 1e6).round()],
      detected: [
        for (final frame in reported) (frame.latestStrumTime * 1e6).round(),
      ],
      tolerance: 50000,
    );
    final unmatched = matchOfDetected.where((i) => i == -1).length;
    // ignore: avoid_print
    print('MEASURED surplus detections: $unmatched');
    expect(
      unmatched,
      0,
      reason:
          'a surplus means either the stimulus has grown an artifact again, or '
          'the engine has started hearing strums that were not played',
    );
  });

  test('REPORTING LAG: the frame arrives well after the stroke it carries', () {
    // The number that makes frame-arrival timestamping wrong. It is expected to
    // be LARGE — that is the point — and it must not be mistaken for placement
    // error above.
    final lagsMs = <double>[];
    for (final frame in reported) {
      if (frame.engineTimeSec < 0) continue;
      lagsMs.add((frame.engineTimeSec - frame.latestStrumTime) * 1000);
    }
    // ignore: avoid_print
    print(
      'MEASURED reporting lag ms: '
      '${lagsMs.map((e) => e.toStringAsFixed(1)).join(', ')}',
    );
    expect(lagsMs, isNotEmpty, reason: 'the producer must track its own clock');
    for (final lag in lagsMs) {
      expect(
        lag,
        greaterThan(0),
        reason: 'a frame cannot carry a stroke it has not seen yet',
      );
    }
    // Independently reproduces the 85-165 ms the `LiveFrame` doc comment cites
    // from r145, on a different stimulus and a different code path.
    expect(
      lagsMs.reduce(math.max),
      greaterThan(50),
      reason:
          'if this ever dropped below the onset window, arrival-time '
          'stamping would stop being dangerous and this file could be retired',
    );
  });

  test('the two numbers are DIFFERENT — which is the whole point', () {
    // If placement error and reporting lag were interchangeable, timestamping at
    // frame arrival would be harmless. They are not, and this cell is what stops
    // a future refactor from quietly treating them as the same thing.
    final matchOfDetected = matchWithinTolerance(
      expected: [for (final onset in onsets) (onset * 1e6).round()],
      detected: [
        for (final frame in reported) (frame.latestStrumTime * 1e6).round(),
      ],
      tolerance: 50000,
    );
    var worstPlacementMs = 0.0;
    for (var j = 0; j < matchOfDetected.length; j++) {
      final i = matchOfDetected[j];
      if (i == -1) continue;
      worstPlacementMs = math.max(
        worstPlacementMs,
        ((reported[j].latestStrumTime - onsets[i]) * 1000).abs(),
      );
    }
    final worstLagMs = reported
        .where((frame) => frame.engineTimeSec >= 0)
        .map((frame) => (frame.engineTimeSec - frame.latestStrumTime) * 1000)
        .reduce(math.max);
    // ignore: avoid_print
    print(
      'MEASURED worst placement ${worstPlacementMs.toStringAsFixed(1)} ms vs '
      'worst lag ${worstLagMs.toStringAsFixed(1)} ms',
    );
    expect(
      worstLagMs,
      greaterThan(worstPlacementMs * 5),
      reason:
          'the arrival delay dwarfs the placement error — timestamping a stroke '
          'when its frame arrives would import the difference as false lateness',
    );
  });
}
