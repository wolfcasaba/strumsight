// String-arrival direction cue on the REAL Klangio corpus (phone mic, 82
// takes, 11 767 labelled strums with the chord label per strum).
//
// Protocol: verdict at the LABELLED onset time, voicing = the open-position
// shape of the labelled chord. Reports accuracy / coverage overall, per
// player (id prefix), per chord and per confidence tier — the numbers that
// decide whether this cue earns a place behind the classifier seam.
//
// Auto-skips when ml/data/klangio is absent. Run:
//   flutter test test/tools/string_arrival_probe_test.dart
// Optional: STRING_ARRIVAL_LIMIT=<n recordings> for a quick pass.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/dsp/direction/string_arrival_cue.dart';
import 'package:strumsight/features/live/engine/dsp/superflux_onset_detector.dart';

import 'klangio_real_ab_test.dart' show dataDir, evalIds, readWav;

/// Klangio chord labels → open-position frets (low E → high E, -1 = muted).
const klangioVoicings = <String, List<int>>{
  'C-major': [-1, 3, 2, 0, 1, 0],
  'G-major': [3, 2, 0, 0, 0, 3],
  'D-major': [-1, -1, 0, 2, 3, 2],
  'A-major': [-1, 0, 2, 2, 2, 0],
  'E-major': [0, 2, 2, 1, 0, 0],
  'F-major': [1, 3, 3, 2, 1, 1],
  'B-major': [-1, 2, 4, 4, 4, 2],
  'F#-major': [2, 4, 4, 3, 2, 2],
  'Bb-major': [-1, 1, 3, 3, 3, 1],
  'C#-major': [-1, 4, 6, 6, 6, 4],
  'B-minor': [-1, 2, 4, 4, 3, 2],
  'A-minor': [-1, 0, 2, 2, 1, 0],
};

class _Tally {
  int total = 0, covered = 0, correct = 0;
  double get coverage => total == 0 ? 0 : covered / total;
  double get accuracy => covered == 0 ? 0 : correct / covered;
  double get accAll => total == 0 ? 0 : correct / total;
  String get row =>
      'n=${total.toString().padLeft(5)}  cov=${(coverage * 100).toStringAsFixed(1).padLeft(5)}%  '
      'acc|cov=${(accuracy * 100).toStringAsFixed(1).padLeft(5)}%  acc/all=${(accAll * 100).toStringAsFixed(1).padLeft(5)}%';
}

void main() {
  final present = Directory(dataDir).existsSync();

  test(
    'string-arrival cue: accuracy on Klangio at labelled onsets',
    () {
      final limit = int.tryParse(
        Platform.environment['STRING_ARRIVAL_LIMIT'] ?? '',
      );
      final shiftMs =
          double.tryParse(
            Platform.environment['STRING_ARRIVAL_SHIFT_MS'] ?? '',
          ) ??
          0.0;
      // 'detected': analyse at the SuperFlux-detected attack nearest the label
      // (±80 ms), exactly as the live pipeline would; default: labelled time.
      final detected =
          Platform.environment['STRING_ARRIVAL_ONSETS'] == 'detected';
      var unmatched = 0;
      final files =
          Directory(dataDir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.strums'))
              .map((f) => f.path)
              .toList()
            ..sort();
      final takes = limit == null ? files : files.take(limit).toList();

      final all = _Tally();
      final eval = _Tally();
      final byPlayer = <String, _Tally>{};
      final byChord = <String, _Tally>{};
      final byTier = <String, _Tally>{};
      final byDir = <StrumDirection, _Tally>{
        StrumDirection.down: _Tally(),
        StrumDirection.up: _Tally(),
      };
      var unknownChord = 0;
      final sw = Stopwatch()..start();

      for (final strumsPath in takes) {
        final id = RegExp(
          r'recording_(\d+)\.strums$',
        ).firstMatch(strumsPath)!.group(1)!;
        final (pcm, sr) = readWav('$dataDir/recording_${id}_phone.wav');
        final cue = StringArrivalCue(sampleRate: sr);
        final player = id.substring(0, 1);
        final detections = <double>[];
        if (detected) {
          final det = SuperFluxOnsetDetector(sampleRate: sr);
          final w = det.window, h = det.hop;
          for (var i = 0; i + w <= pcm.length; i += h) {
            final onset = det.processFrame(
              Float64List.sublistView(pcm, i, i + w),
            );
            if (onset != null) detections.add(onset + 2.5 * h / sr);
          }
        }
        for (final line in File(strumsPath).readAsLinesSync()) {
          if (line.trim().isEmpty) continue;
          final parts = line.split('\t');
          final t = double.parse(parts[0]);
          final label = parts[1] == 'D'
              ? StrumDirection.down
              : StrumDirection.up;
          final frets = klangioVoicings[parts[2]];
          if (frets == null) {
            unknownChord++;
            continue;
          }
          var at = t + shiftMs / 1000;
          if (detected) {
            double? best;
            for (final d in detections) {
              if ((d - t).abs() <= 0.08 &&
                  (best == null || (d - t).abs() < (best - t).abs())) {
                best = d;
              }
            }
            if (best == null) {
              unmatched++;
              continue;
            }
            at = best;
          }
          final r = cue.analyze(
            pcm,
            (at * sr).round(),
            StringArrivalCue.voicingHz(frets),
          );
          final tier = r.direction == null
              ? 'none'
              : r.confidence >= 0.8
              ? 'high'
              : r.confidence >= 0.6
              ? 'mid'
              : 'low';
          for (final tally in [
            all,
            if (evalIds.contains(id)) eval,
            byPlayer.putIfAbsent(player, _Tally.new),
            byChord.putIfAbsent(parts[2], _Tally.new),
            byTier.putIfAbsent(tier, _Tally.new),
            byDir[label]!,
          ]) {
            tally.total++;
            if (r.direction != null) {
              tally.covered++;
              if (r.direction == label) tally.correct++;
            }
          }
        }
      }

      final out = StringBuffer()
        ..writeln(
          'string-arrival cue @ labelled onsets, ${takes.length} takes, '
          '${sw.elapsed.inSeconds}s, shift=${shiftMs}ms, onsets=${detected ? 'detected (unmatched $unmatched)' : 'labelled'}, unknown-chord strums skipped: $unknownChord',
        )
        ..writeln('ALL        ${all.row}')
        ..writeln('EVAL fold  ${eval.row}');
      for (final e
          in byPlayer.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))) {
        out.writeln('player ${e.key}   ${e.value.row}');
      }
      for (final e in byDir.entries) {
        out.writeln('label ${e.key.name.padRight(5)} ${e.value.row}');
      }
      for (final e in byTier.entries) {
        out.writeln('tier ${e.key.padRight(5)}  ${e.value.row}');
      }
      for (final e
          in byChord.entries.toList()
            ..sort((a, b) => b.value.total.compareTo(a.value.total))) {
        out.writeln('chord ${e.key.padRight(9)} ${e.value.row}');
      }
      // ignore: avoid_print
      print(out);
      expect(all.total, greaterThan(100));
    },
    skip: present ? false : 'ml/data/klangio absent',
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
