// r166 SWEEP (diagnostics, auto-skips without the local dataset): can the
// SuperFlux adaptive threshold recover the labels it misses on REAL takes
// (73 % @0.12 s, r164/r166 probe) without opening the false-alarm gate?
// Sweeps (delta, lambda) at the DETECTOR level over the eval fold.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/superflux_onset_detector.dart';

import 'klangio_real_ab_test.dart' show readWav, readStrums, evalIds, dataDir;

void main() {
  final present = Directory(dataDir).existsSync();

  test(
    'SWEEP: delta × lambda vs real recall / false alarms',
    () {
      // Preload once — the sweep re-runs only the detector.
      final takes = [
        for (final id in evalIds)
          (
            readWav('$dataDir/recording_${id}_phone.wav'),
            readStrums('$dataDir/recording_$id.strums'),
          ),
      ];

      for (final (delta, lambda) in [
        (20.0, 2.0), // current tune (baseline)
        (20.0, 1.0),
        (12.0, 2.0),
        (12.0, 1.0),
        (8.0, 1.0),
        (8.0, 0.5),
      ]) {
        var labels = 0, hit = 0, falseAlarms = 0, detected = 0;
        for (final ((pcm, sr), events) in takes) {
          final det = <double>[];
          final d = SuperFluxOnsetDetector(
              sampleRate: sr, delta: delta, lambda: lambda);
          for (var s = 0; s + d.window <= pcm.length; s += d.hop) {
            final t =
                d.processFrame(Float64List.sublistView(pcm, s, s + d.window));
            if (t != null) det.add(t);
          }
          detected += det.length;
          for (final (t, _) in events) {
            labels++;
            if (det.any((x) => (x - t).abs() <= 0.12)) hit++;
          }
          for (final x in det) {
            if (!events.any((e) => (x - e.$1).abs() <= 0.12)) falseAlarms++;
          }
        }
        // ignore: avoid_print
        print('SWEEP delta=$delta lambda=$lambda '
            'recall=${(100 * hit / labels).round()}% '
            'det=$detected fa=$falseAlarms '
            'precision=${(100 * (detected - falseAlarms) / detected).round()}%');
      }
      expect(present, isTrue);
    },
    skip: present ? false : 'ml/data/klangio absent',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
