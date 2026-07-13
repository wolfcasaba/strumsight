// r171 PROBES.
// (b) CPU cost of the live CRNN per strum inside the DSP isolate: observe()
//     per fast hop (ring append) + classifyAt() per onset (15 FFTs + the
//     forward pass). The pipeline emits frames at ~15 Hz and processes fast
//     hops at ~172 Hz — a classifyAt that costs tens of ms would back up the
//     isolate's inbox during fast strumming. Synth-driven, runs everywhere.
// (c) Batch (Analyze) model confidence calibration on the real fold — the
//     r170 live finding said raw softmax is overconfident; the Analyze
//     timeline/share confidences come from the SAME family. Data-gated.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:music_theory/features/live/engine/ml/live_crnn_classifier.dart';
import 'package:music_theory/features/live/engine/ml/strum_crnn.dart';

import 'klangio_real_ab_test.dart' show readWav, readStrums, evalIds, dataDir;

void main() {
  const sr = 44100;
  const window = 1024;
  const hop = 256;

  test('PROBE(b): live CRNN cost per hop and per strum', () {
    final classifier = LiveCrnnStrumClassifier.tryLoad(
        'assets/ml/strum_crnn_live.bin',
        sampleRate: sr)!;
    final rng = math.Random(1);
    final signal = Float64List(sr * 2);
    for (var i = 0; i < signal.length; i++) {
      signal[i] = 0.4 * math.sin(2 * math.pi * 196 * i / sr) +
          0.1 * (rng.nextDouble() * 2 - 1);
    }
    final nFrames = 1 + (signal.length - window) ~/ hop;
    const features =
        StrumFrameFeatures(lowEnergy: 0, highEnergy: 0, centroid: 0);

    final swObserve = Stopwatch()..start();
    for (var f = 0; f < nFrames; f++) {
      classifier.observe(
          Float64List.sublistView(signal, f * hop, f * hop + window),
          features);
    }
    swObserve.stop();
    final observeUs = swObserve.elapsedMicroseconds / nFrames;

    const runs = 50;
    final swClassify = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      classifier.classifyAt(
          onsetFrame: nFrames - 13 - i, currentFrame: nFrames - 1 - i);
    }
    swClassify.stop();
    final classifyMs = swClassify.elapsedMilliseconds / runs;

    // ignore: avoid_print
    print('COST PROBE observe=${observeUs.toStringAsFixed(1)}us/hop '
        'classify=${classifyMs.toStringAsFixed(2)}ms/strum '
        '(hop budget ~5.8ms, fastest strums ~150ms apart)');
    // Measured r171 (THIS box, JIT test VM): observe 8.7 µs/hop; classify
    // 44 ms → 33 ms after the conv-kernel repack. AOT release is typically
    // 3–5× faster, and a verdict runs ONCE per strum (real strums ≥150 ms
    // apart) — the isolate inbox backs up a few hops and drains; acceptable,
    // recorded in chunk 018. The bounds below catch a REGRESSION class
    // (e.g. accidental per-hop forward, or a repack that stops caching).
    expect(observeUs, lessThan(1000), reason: 'ring append must stay trivial');
    expect(classifyMs, lessThan(60),
        reason: 'JIT classify regressed far past the measured 33 ms — '
            'check the conv repack cache and the forward loops');
  });

  final present = Directory(dataDir).existsSync();
  test(
    'PROBE(c): batch model confidence calibration on the eval fold',
    () {
      final crnn = StrumCrnn.tryLoad('assets/ml/strum_crnn.bin')!;
      const edges = [0.7, 0.9, 0.97, 0.995];
      final n = List.filled(edges.length + 1, 0);
      final ok = List.filled(edges.length + 1, 0);
      int bucketOf(double c) {
        for (var i = 0; i < edges.length; i++) {
          if (c < edges[i]) return i;
        }
        return edges.length;
      }

      for (final id in evalIds) {
        final (pcm, sr) = readWav('$dataDir/recording_${id}_phone.wav');
        final events = readStrums('$dataDir/recording_$id.strums');
        final verdicts =
            crnn.classifyClip(pcm, sr, [for (final (t, _) in events) t]);
        for (var i = 0; i < events.length; i++) {
          final b = bucketOf(verdicts[i].confidence);
          n[b]++;
          if (verdicts[i].direction == events[i].$2) ok[b]++;
        }
      }
      // ignore: avoid_print
      print('BATCH CALIB ${[
        for (var b = 0; b < n.length; b++)
          '${b == 0 ? '<${edges[0]}' : b == n.length - 1 ? '>=${edges.last}' : '${edges[b - 1]}-${edges[b]}'}'
              ' -> n=${n[b]} acc=${(100 * ok[b] / (n[b] == 0 ? 1 : n[b])).round()}%'
      ].join(', ')}');
      expect(n.reduce((a, b) => a + b), greaterThan(1900));
    },
    skip: present ? false : 'ml/data/klangio absent',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
