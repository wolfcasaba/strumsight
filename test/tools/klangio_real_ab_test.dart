// The REAL-recording A/B (ml-track r164): heuristic vs CRNN strum-direction
// on the Klangio EVAL fold (16 recordings, ~2k labeled strums, phone mic) —
// the measurement that ARBITRATES deployment, because the synth suite cannot
// (r163: the real-trained CRNN is off-domain on synth and vice versa the
// heuristic was never measured on real guitar until now).
//
// Auto-skips when ml/data/klangio is absent (the dataset is gitignored,
// third-party data stays out of the repo) — it runs on the dev box where the
// 82 takes live. Protocol mirrors training: verdicts at the LABELED times.
//   heuristic: full StrumAnalyzer stream (detection included), nearest event
//              within ±0.12 s of the label, its direction scored.
//   CRNN:      StrumCrnn.classifyClip at the labeled times (the deployment
//              chain: linear resample -> log-mel -> window -> forward).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/engine/ml/strum_crnn.dart';
import 'package:music_theory/features/live/model/strum.dart';

/// Eval-fold ids = ml/klangio.py split_by_recording(seed 42) — keep in sync.
const evalIds = [
  '1001', '1003', '1005', '1019', '1026', '1028', '2001', '2003', //
  '2007', '2014', '2026', '4002', '4005', '4007', '4008', '4009',
];

const dataDir = 'ml/data/klangio';

/// Minimal 16-bit PCM WAV reader (mono or stereo-averaged), [-1, 1] doubles.
(Float64List, int) readWav(String path) {
  final b = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(b);
  assert(String.fromCharCodes(b.sublist(0, 4)) == 'RIFF', 'not RIFF');
  var off = 12;
  int? sr;
  int channels = 1;
  Float64List? pcm;
  while (off + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(off, off + 4));
    final size = bd.getUint32(off + 4, Endian.little);
    if (id == 'fmt ') {
      channels = bd.getUint16(off + 10, Endian.little);
      sr = bd.getUint32(off + 12, Endian.little);
      assert(bd.getUint16(off + 22, Endian.little) == 16, '16-bit only');
    } else if (id == 'data') {
      final n = size ~/ (2 * channels);
      pcm = Float64List(n);
      for (var i = 0; i < n; i++) {
        var acc = 0.0;
        for (var c = 0; c < channels; c++) {
          acc += bd.getInt16(off + 8 + 2 * (i * channels + c), Endian.little);
        }
        pcm[i] = acc / channels / 32768.0;
      }
    }
    off += 8 + size + (size & 1);
  }
  return (pcm!, sr!);
}

List<(double, StrumDirection)> readStrums(String path) => [
      for (final line in File(path).readAsLinesSync())
        if (line.trim().isNotEmpty)
          (
            double.parse(line.split('\t')[0]),
            switch (line.split('\t')[1]) {
              'D' => StrumDirection.down,
              'U' => StrumDirection.up,
              final d => throw FormatException('unknown direction $d'),
            },
          ),
    ];

void main() {
  final present = Directory(dataDir).existsSync();

  test(
    'REAL A/B: heuristic vs CRNN on the Klangio eval fold',
    () {
      final crnn = StrumCrnn.tryLoad('assets/ml/strum_crnn.bin')!;
      var labels = 0;
      var heurMatched = 0, heurDirected = 0, heurCorrect = 0;
      var crnnCorrect = 0;

      for (final id in evalIds) {
        final (pcm, sr) = readWav('$dataDir/recording_${id}_phone.wav');
        final events = readStrums('$dataDir/recording_$id.strums');
        labels += events.length;

        // Heuristic: stream the whole take through the live analyzer.
        final analyzer = StrumAnalyzer(sampleRate: sr);
        final detected = <StrumEvent>[];
        for (var s = 0;
            s + DspConfig.onsetWindow <= pcm.length;
            s += DspConfig.onsetHop) {
          final e = analyzer
              .process(Float64List.sublistView(pcm, s, s + DspConfig.onsetWindow));
          if (e != null) detected.add(e);
        }
        for (final (t, want) in events) {
          StrumEvent? best;
          var bestDt = 0.12; // matching window
          for (final e in detected) {
            final dt = (e.timeSec - t).abs();
            if (dt < bestDt) {
              bestDt = dt;
              best = e;
            }
          }
          if (best == null) continue;
          heurMatched++;
          if (best.direction != null) {
            heurDirected++;
            if (best.direction == want) heurCorrect++;
          }
        }

        // CRNN: the deployment chain at the labeled times.
        final verdicts =
            crnn.classifyClip(pcm, sr, [for (final (t, _) in events) t]);
        for (var i = 0; i < events.length; i++) {
          if (verdicts[i].direction == events[i].$2) crnnCorrect++;
        }
      }

      final heurAcc = heurCorrect / heurDirected;
      final crnnAcc = crnnCorrect / labels;
      // The scoreboard that decides the Analyze-path deployment.
      // ignore: avoid_print
      print('REAL A/B (eval fold, $labels labels): '
          'heuristic matched=$heurMatched directed=$heurDirected '
          'acc=${(heurAcc * 100).toStringAsFixed(1)}% | '
          'crnn acc=${(crnnAcc * 100).toStringAsFixed(1)}%');

      expect(labels, greaterThan(1900), reason: 'the whole eval fold ran');
      // Sanity floors only — the print IS the deliverable; findings go to
      // chunk 018 and the deployment decision follows the numbers.
      expect(heurMatched / labels, greaterThanOrEqualTo(0.85),
          reason: 'r166 retune locked: onset recall on real takes was 73% '
              'at the synth-tuned threshold, 91% after (12, 1.0) — a drop '
              'back means the detector regressed on real audio');
      expect(crnnAcc, greaterThan(0.75),
          reason: 'the Dart chain must reproduce the ~0.867 Python eval '
              '(large drop = feature drift between training and serving)');
    },
    skip: present
        ? false
        : 'ml/data/klangio absent (gitignored dataset lives on the dev box)',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
