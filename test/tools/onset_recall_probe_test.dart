// r166 PROBE (throwaway diagnostics, auto-skips without the local dataset):
// WHY does the live analyzer match only 73 % of labeled strums on real takes
// (r164)? Hypotheses: (a) ring-out masking — a label too soon after the
// previous one gets suppressed by the onset detector's refractory/threshold,
// (b) soft strums under the adaptive threshold, (c) a timing offset larger
// than the ±0.12 s matching window, (d) label style (legato/ghost strokes).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';

import 'klangio_real_ab_test.dart' show readWav, readStrums, evalIds, dataDir;

void main() {
  final present = Directory(dataDir).existsSync();

  test(
    'PROBE: where do the 27% missed labels come from?',
    () {
      var labels = 0, m12 = 0, m20 = 0, m35 = 0;
      var missAfterClose = 0, missAfterFar = 0; // gap to PREVIOUS label
      var falseAlarms = 0, detectedTotal = 0;
      final perRec = <String>[];

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
        detectedTotal += det.length;

        var recM12 = 0;
        for (var i = 0; i < events.length; i++) {
          final t = events[i].$1;
          double best = 9e9;
          for (final d in det) {
            if ((d - t).abs() < best) best = (d - t).abs();
          }
          labels++;
          if (best <= 0.12) {
            m12++;
            recM12++;
          }
          if (best <= 0.20) m20++;
          if (best <= 0.35) m35++;
          if (best > 0.12) {
            final gapPrev = i == 0 ? 99.0 : t - events[i - 1].$1;
            if (gapPrev < 0.25) {
              missAfterClose++;
            } else {
              missAfterFar++;
            }
          }
        }
        // Detections with no label within 0.12 s = false alarms.
        for (final d in det) {
          var ok = false;
          for (final (t, _) in events) {
            if ((d - t).abs() <= 0.12) {
              ok = true;
              break;
            }
          }
          if (!ok) falseAlarms++;
        }
        perRec.add('$id:${(100 * recM12 / events.length).round()}%');
      }

      // ignore: avoid_print
      print('PROBE labels=$labels recall@0.12=${(100 * m12 / labels).round()}% '
          '@0.20=${(100 * m20 / labels).round()}% '
          '@0.35=${(100 * m35 / labels).round()}% | misses: '
          'afterClose(<0.25s)=$missAfterClose afterFar=$missAfterFar | '
          'detected=$detectedTotal falseAlarms=$falseAlarms');
      // ignore: avoid_print
      print('PROBE per-recording recall@0.12: ${perRec.join(' ')}');
      expect(labels, greaterThan(1900));
    },
    skip: present ? false : 'ml/data/klangio absent',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
