// r167 SWEEP: the CRNN's window-shift constant, measured at the DEPLOYED
// semantics (StrumAnalyzer event times, r144-corrected attack instants —
// exactly what ClipAnalyzer hands the refiner). Auto-skips without data.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/engine/ml/strum_crnn.dart';

import 'klangio_real_ab_test.dart' show readWav, readStrums, evalIds, dataDir;

void main() {
  final present = Directory(dataDir).existsSync();

  test(
    'SWEEP: CRNN accuracy vs window shift at deployed event times',
    () {
      final crnn = StrumCrnn.tryLoad('assets/ml/strum_crnn.bin')!;
      const shifts = [0.0, 0.015, 0.030, 0.045, 0.060];
      final correct = List.filled(shifts.length, 0);
      var n = 0;

      for (final id in evalIds) {
        final (pcm, sr) = readWav('$dataDir/recording_${id}_phone.wav');
        final events = readStrums('$dataDir/recording_$id.strums');
        final analyzer = StrumAnalyzer(sampleRate: sr);
        final det = <double>[];
        for (var s = 0;
            s + DspConfig.onsetWindow <= pcm.length;
            s += DspConfig.onsetHop) {
          final e = analyzer.process(
              Float64List.sublistView(pcm, s, s + DspConfig.onsetWindow));
          if (e != null) det.add(e.timeSec);
        }
        final pairs = <(double, int)>[]; // (event time, label)
        for (final (t, dir) in events) {
          double best = 9e9;
          double? bt;
          for (final x in det) {
            if ((x - t).abs() < best) {
              best = (x - t).abs();
              bt = x;
            }
          }
          if (bt != null && best <= 0.12) pairs.add((bt, dir.index));
        }
        for (var s = 0; s < shifts.length; s++) {
          final v = crnn.classifyClip(
              pcm, sr, [for (final p in pairs) p.$1 + shifts[s]]);
          for (var i = 0; i < pairs.length; i++) {
            if (v[i].direction!.index == pairs[i].$2) correct[s]++;
          }
        }
        n += pairs.length;
      }
      // ignore: avoid_print
      print('SHIFT SWEEP n=$n: ${[
        for (var s = 0; s < shifts.length; s++)
          '+${(shifts[s] * 1000).round()}ms=${(100 * correct[s] / n).toStringAsFixed(1)}%'
      ].join(' ')}');
      expect(n, greaterThan(1500));
    },
    skip: present ? false : 'ml/data/klangio absent',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
