// r168: the live 70 ms model measured through the FULL Dart SERVE chain —
// StrumAnalyzer streaming (detection + classify instants) with the
// LiveCrnnStrumClassifier behind the r139 seam, over the real eval fold.
// The training eval said 0.799 at labeled times; this measures the deployed
// condition (detected onsets, ring-streamed audio, slice resampling).
// Auto-skips without the local dataset.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/engine/ml/live_crnn_classifier.dart';

import 'klangio_real_ab_test.dart' show readWav, readStrums, evalIds, dataDir;

void main() {
  final present = Directory(dataDir).existsSync();

  test(
    'live serve chain: CRNN-70ms direction accuracy on the eval fold',
    () {
      var n = 0, correct = 0;
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
        for (final (t, want) in events) {
          StrumEvent? best;
          var bestDt = 0.12;
          for (final e in det) {
            final dt = (e.timeSec - t).abs();
            if (dt < bestDt) {
              bestDt = dt;
              best = e;
            }
          }
          if (best?.direction == null) continue;
          n++;
          if (best!.direction == want) correct++;
        }
      }
      final acc = correct / n;
      // ignore: avoid_print
      print('LIVE SERVE n=$n acc=${(100 * acc).toStringAsFixed(1)}% '
          '(training eval 79.9%; heuristic serve was 39.2%)');
      expect(n, greaterThan(1500));
      expect(acc, greaterThan(0.70),
          reason: 'a big drop vs the 0.799 training eval = serve-chain '
              'drift (resample grid / window alignment / ring bug)');
    },
    skip: present ? false : 'ml/data/klangio absent',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
