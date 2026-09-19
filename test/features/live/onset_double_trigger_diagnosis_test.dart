// DIAGNOSIS: why four strums were reported as eight.
//
// `strum_timestamp_latency_test.dart` measured excellent placement (0.0-3.4 ms)
// and, alongside it, roughly twice as many reported strums as there were strums
// — the surplus landing ~550 ms after each. That is a hearing symptom: in a
// rhythm exercise a phantom stroke is a stroke the learner did not play.
//
// Speculating about the cause would be the wrong move, so this file isolates it
// by varying ONE thing at a time and printing what the engine reports:
//
//   1. a single plucked string, no spread        — is the spread responsible?
//   2. a six-string strum, the original stimulus — reproduces the surplus?
//   3. a single string with the tail cut short   — is it the decay tail?
//   4. one lone strum, nothing after it          — is it a neighbour effect?
//
// The point is to learn whether this is the SYNTHESIS or the ENGINE, because the
// answer decides whether anything in the app needs fixing at all.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

const int _sampleRate = 44100;

void _addPluck(
  List<double> pcm, {
  required double atSec,
  required double freqHz,
  double amplitude = 0.35,
  double decaySec = 0.55,
  double? cutAfterSec,
}) {
  final start = (atSec * _sampleRate).round();
  final length = ((cutAfterSec ?? decaySec) * _sampleRate).round();
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
    // Fade the last 30 ms to zero. Without this the synthesis ENDS on a step,
    // and a step is a genuine broadband transient — the detector is right to
    // hear it. Six of them 22 ms apart is what produced the phantom strums.
    final remaining = (length - i) / _sampleRate;
    final fade = remaining < 0.03 ? remaining / 0.03 : 1.0;
    pcm[index] += amplitude * envelope * fade * sample;
  }
}

const _guitarFreqs = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63];

/// Reported strum onset times, in seconds on the engine clock.
List<double> _reportedOnsets(List<double> pcm) {
  final pipeline = LivePipeline(sampleRate: _sampleRate);
  final out = <double>[];
  var lastSeq = 0;
  const chunk = 1024;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = math.min(i + chunk, pcm.length);
    for (final LiveFrame frame in pipeline.addChunk(pcm.sublist(i, end))) {
      if (frame.strumSeq > lastSeq) {
        lastSeq = frame.strumSeq;
        out.add(frame.latestStrumTime);
      }
    }
  }
  return out;
}

List<double> _silence(double seconds) =>
    List<double>.filled((seconds * _sampleRate).round(), 0);

String _fmt(List<double> xs) => xs.map((x) => x.toStringAsFixed(3)).join(', ');

void main() {
  const onsets = [0.40, 1.15, 1.90, 2.65]; // 80 bpm

  test('0. with the truncation faded out, the surplus should be GONE', () {
    // The hypothesis, stated as a cell: if the phantom strums were the
    // synthesis ending on a step, fading the last 30 ms removes them and the
    // engine reports exactly one strum per strum.
    final pcm = _silence(4.0);
    for (final onset in onsets) {
      for (var i = 0; i < _guitarFreqs.length; i++) {
        _addPluck(pcm, atSec: onset + i * 0.022, freqHz: _guitarFreqs[i]);
      }
    }
    final reported = _reportedOnsets(pcm);
    // ignore: avoid_print
    print(
      'FADED six-string strum: ${reported.length} for 4 -> ${_fmt(reported)}',
    );
    expect(
      reported.length,
      onsets.length,
      reason:
          'with no truncation step left, the engine should hear exactly the '
          'strums that are there — if this fails the cause is NOT the stimulus',
    );
  });

  test('1. a single string, one pluck per beat', () {
    final pcm = _silence(4.0);
    for (final onset in onsets) {
      _addPluck(pcm, atSec: onset, freqHz: 146.83, amplitude: 0.6);
    }
    final reported = _reportedOnsets(pcm);
    // ignore: avoid_print
    print('single string: ${reported.length} for 4 -> ${_fmt(reported)}');
    expect(reported, isNotEmpty);
  });

  test('2. six strings spread 22 ms apart — the original stimulus', () {
    final pcm = _silence(4.0);
    for (final onset in onsets) {
      for (var i = 0; i < _guitarFreqs.length; i++) {
        _addPluck(pcm, atSec: onset + i * 0.022, freqHz: _guitarFreqs[i]);
      }
    }
    final reported = _reportedOnsets(pcm);
    // ignore: avoid_print
    print('six-string strum: ${reported.length} for 4 -> ${_fmt(reported)}');
    final surplus = reported.length - onsets.length;
    // ignore: avoid_print
    print('  surplus: $surplus');
    expect(reported, isNotEmpty);
  });

  test('3. the same, with the decay tail cut at 150 ms', () {
    // If the surplus disappears when the tail is removed, the tail is making it.
    final pcm = _silence(4.0);
    for (final onset in onsets) {
      for (var i = 0; i < _guitarFreqs.length; i++) {
        _addPluck(
          pcm,
          atSec: onset + i * 0.022,
          freqHz: _guitarFreqs[i],
          cutAfterSec: 0.15,
        );
      }
    }
    final reported = _reportedOnsets(pcm);
    // ignore: avoid_print
    print('cut tail: ${reported.length} for 4 -> ${_fmt(reported)}');
    expect(reported, isNotEmpty);
  });

  test('4. one lone strum in silence', () {
    // Isolates any interaction between neighbouring strums.
    final pcm = _silence(3.0);
    for (var i = 0; i < _guitarFreqs.length; i++) {
      _addPluck(pcm, atSec: 0.5 + i * 0.022, freqHz: _guitarFreqs[i]);
    }
    final reported = _reportedOnsets(pcm);
    // ignore: avoid_print
    print('lone strum: ${reported.length} for 1 -> ${_fmt(reported)}');
    expect(reported, isNotEmpty);
  });

  test('5. a hard silence gap after each strum', () {
    // Every strum is followed by true digital silence. Anything reported inside
    // the silence cannot come from the signal.
    final pcm = _silence(4.0);
    for (final onset in onsets) {
      for (var i = 0; i < _guitarFreqs.length; i++) {
        _addPluck(
          pcm,
          atSec: onset + i * 0.022,
          freqHz: _guitarFreqs[i],
          cutAfterSec: 0.30,
        );
      }
    }
    final reported = _reportedOnsets(pcm);
    final inSilence = reported
        .where((t) => onsets.every((onset) => t < onset || t > onset + 0.45))
        .toList();
    // ignore: avoid_print
    print('gapped: ${reported.length} for 4 -> ${_fmt(reported)}');
    // ignore: avoid_print
    print('  reported DURING digital silence: ${_fmt(inSilence)}');
    expect(reported, isNotEmpty);
  });
}
