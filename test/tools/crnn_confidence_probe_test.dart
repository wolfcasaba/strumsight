// r170 PROBE: is the live CRNN's confidence CALIBRATED — and what does it
// say on FALSE-ALARM onsets? The r166 threshold retune buys 91 % recall at
// 83 % precision, so ~1-in-6 live onsets is not a labeled strum; if the
// model is as confident there as on real strums, the UI's confidence tier
// cannot dampen noise arrows. Auto-skips without the local dataset.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/engine/ml/live_crnn_classifier.dart';
import 'package:music_theory/features/live/model/strum.dart';

import 'klangio_real_ab_test.dart' show readWav, readStrums, evalIds, dataDir;

void main() {
  final present = Directory(dataDir).existsSync();

  test(
    'PROBE: live CRNN confidence on matched vs false-alarm onsets',
    () {
      final matchedConf = <double>[];
      final faConf = <double>[];
      // Calibration buckets over matched detections.
      const edges = [0.7, 0.9, 0.97, 0.995];
      final bucketN = List.filled(edges.length + 1, 0);
      final bucketCorrect = List.filled(edges.length + 1, 0);
      int bucketOf(double c) {
        for (var i = 0; i < edges.length; i++) {
          if (c < edges[i]) return i;
        }
        return edges.length;
      }

      for (final id in evalIds) {
        final (pcm, sr) = readWav('$dataDir/recording_${id}_phone.wav');
        final events = readStrums('$dataDir/recording_$id.strums');
        final classifier = LiveCrnnStrumClassifier.tryLoad(
            'assets/ml/strum_crnn_live.bin',
            sampleRate: sr)!;
        final analyzer = StrumAnalyzer(sampleRate: sr, classifier: classifier);
        final det = <StrumEvent>[];
        for (var s = 0;
            s + DspConfig.onsetWindow <= pcm.length;
            s += DspConfig.onsetHop) {
          final e = analyzer.process(
              Float64List.sublistView(pcm, s, s + DspConfig.onsetWindow));
          if (e != null) det.add(e);
        }
        for (final e in det) {
          (double, StrumDirection)? label;
          for (final (t, dir) in events) {
            if ((e.timeSec - t).abs() <= 0.12) {
              label = (t, dir);
              break;
            }
          }
          if (label == null) {
            faConf.add(e.confidence);
          } else {
            matchedConf.add(e.confidence);
            final b = bucketOf(e.confidence);
            bucketN[b]++;
            if (e.direction == label.$2) bucketCorrect[b]++;
          }
        }
      }

      matchedConf.sort();
      faConf.sort();
      double med(List<double> xs) => xs[xs.length ~/ 2];
      // ignore: avoid_print
      print('CONF PROBE matched=${matchedConf.length} '
          'median=${med(matchedConf).toStringAsFixed(2)} | '
          'falseAlarms=${faConf.length} median=${med(faConf).toStringAsFixed(2)} | '
          'calibration: ${[
        for (var b = 0; b < bucketN.length; b++)
          '${b == 0 ? '<${edges[0]}' : b == bucketN.length - 1 ? '>=${edges.last}' : '${edges[b - 1]}-${edges[b]}'}'
              ' -> n=${bucketN[b]} acc='
              '${(100 * bucketCorrect[b] / (bucketN[b] == 0 ? 1 : bucketN[b])).round()}%'
      ].join(', ')}');
      expect(matchedConf.length, greaterThan(1000));
    },
    skip: present ? false : 'ml/data/klangio absent',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
