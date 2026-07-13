// r167 PROBE: the Analyze path classifies at DETECTED onset times, not the
// labeled ones the 86.7 % eval used. How much does detector time error cost
// the CRNN? (Its training windows are label-centred; a shifted window is a
// mild domain shift.) Auto-skips without the local dataset.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/superflux_onset_detector.dart';
import 'package:music_theory/features/live/engine/ml/strum_crnn.dart';

import 'klangio_real_ab_test.dart' show readWav, readStrums, evalIds, dataDir;

void main() {
  final present = Directory(dataDir).existsSync();

  test(
    'PROBE: CRNN accuracy at detected vs labeled times',
    () {
      final crnn = StrumCrnn.tryLoad('assets/ml/strum_crnn.bin')!;
      var n = 0, atLabel = 0, atDetected = 0, atShifted = 0;
      final offsets = <double>[];

      for (final id in evalIds) {
        final (pcm, sr) = readWav('$dataDir/recording_${id}_phone.wav');
        final events = readStrums('$dataDir/recording_$id.strums');
        final det = <double>[];
        final d = SuperFluxOnsetDetector(sampleRate: sr);
        for (var s = 0; s + d.window <= pcm.length; s += d.hop) {
          final t =
              d.processFrame(Float64List.sublistView(pcm, s, s + d.window));
          if (t != null) det.add(t);
        }
        // Pair each label with its nearest detection within 0.12 s.
        final pairs = <(double, double, int)>[]; // (label t, detected t, y)
        for (final (t, dir) in events) {
          double best = 9e9;
          double? bt;
          for (final x in det) {
            if ((x - t).abs() < best) {
              best = (x - t).abs();
              bt = x;
            }
          }
          if (bt != null && best <= 0.12) {
            pairs.add((t, bt, dir.index)); // StrumDirection.down=0? verify
          }
        }
        final labelVerdicts =
            crnn.classifyClip(pcm, sr, [for (final p in pairs) p.$1]);
        final detVerdicts =
            crnn.classifyClip(pcm, sr, [for (final p in pairs) p.$2]);
        final shiftVerdicts = crnn
            .classifyClip(pcm, sr, [for (final p in pairs) p.$2 + 0.042]);
        for (var i = 0; i < pairs.length; i++) {
          n++;
          offsets.add(pairs[i].$2 - pairs[i].$1);
          final want = pairs[i].$3;
          if (labelVerdicts[i].direction!.index == want) atLabel++;
          if (detVerdicts[i].direction!.index == want) atDetected++;
          if (shiftVerdicts[i].direction!.index == want) atShifted++;
        }
      }
      offsets.sort();
      final med = offsets[offsets.length ~/ 2];
      // ignore: avoid_print
      print('PROBE n=$n atLabel=${(100 * atLabel / n).toStringAsFixed(1)}% '
          'atDetected=${(100 * atDetected / n).toStringAsFixed(1)}% '
          'atShifted+42ms=${(100 * atShifted / n).toStringAsFixed(1)}% '
          'medianOffset=${(med * 1000).toStringAsFixed(0)}ms '
          'p10=${(offsets[(offsets.length * 0.1).floor()] * 1000).toStringAsFixed(0)}ms '
          'p90=${(offsets[(offsets.length * 0.9).floor()] * 1000).toStringAsFixed(0)}ms');
      expect(n, greaterThan(1500));
    },
    skip: present ? false : 'ml/data/klangio absent',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
