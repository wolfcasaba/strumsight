// String-arrival cue against GuitarSet's HEXAPHONIC ground truth.
//
// GuitarSet annotates every note per string (note_midi, data_source = string
// index), so a clean comping sweep gives (a) the true direction, (b) the TRUE
// arrival time of every string and (c) the exact pitch on every string. That
// lets this probe measure the one thing the Klangio probe cannot: is the
// per-string arrival time RECOVERABLE from the mono mic at all, and with what
// error — before asking whether the order reads the direction.
//
// Sweep extraction mirrors the E18 harness (link 45 ms, ≥3 strings, monotone
// string order, spread ≥ 5 ms; Rock/Funk comping takes only).
//
// Auto-skips without the corpus. Run:
//   GUITARSET_DIR=C:/Users/kcsab/Downloads/recipewis \
//   flutter test test/tools/string_arrival_guitarset_probe_test.dart
// Optional: STRING_ARRIVAL_WINDOW=<samples>, STRING_ARRIVAL_LIMIT=<files>.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/dsp/direction/string_arrival_cue.dart';

import 'klangio_real_ab_test.dart' show readWav;

const _linkMs = 45.0;
const _styles = ['Rock', 'Funk'];

typedef _Note = ({double time, int string, double midi});

final class _Sweep {
  _Sweep(this.notes);
  final List<_Note> notes;
  double get atSec => notes.first.time;
  double get spreadMs => (notes.last.time - notes.first.time) * 1000;
  StrumDirection? get direction {
    var score = 0;
    for (var i = 0; i < notes.length; i++) {
      for (var k = i + 1; k < notes.length; k++) {
        final dt = notes[k].time - notes[i].time;
        final ds = notes[k].string - notes[i].string;
        if (dt == 0 || ds == 0) continue;
        score += ds > 0 ? 1 : -1;
      }
    }
    return score > 0
        ? StrumDirection.down
        : score < 0
        ? StrumDirection.up
        : null;
  }

  bool get monotone {
    final idx = [for (final n in notes) n.string];
    final sorted = [...idx]..sort();
    bool same(List<int> a, List<int> b) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    return same(idx, sorted) || same(idx, sorted.reversed.toList());
  }

  bool get isClean =>
      direction != null && notes.length >= 3 && monotone && spreadMs >= 5;
}

List<_Sweep> _sweeps(Map<String, dynamic> jams) {
  final notes = <_Note>[];
  for (final ann
      in (jams['annotations'] as List).cast<Map<String, dynamic>>()) {
    if (ann['namespace'] != 'note_midi') continue;
    final source =
        (ann['annotation_metadata'] as Map<String, dynamic>?)?['data_source'];
    final string = int.tryParse('$source');
    if (string == null) continue;
    for (final ob in (ann['data'] as List).cast<Map<String, dynamic>>()) {
      notes.add((
        time: (ob['time'] as num).toDouble(),
        string: string,
        midi: (ob['value'] as num).toDouble(),
      ));
    }
  }
  notes.sort((a, b) => a.time.compareTo(b.time));
  final groups = <List<_Note>>[];
  for (final n in notes) {
    if (groups.isNotEmpty &&
        (n.time - groups.last.last.time) * 1000 <= _linkMs) {
      groups.last.add(n);
    } else {
      groups.add([n]);
    }
  }
  return [for (final g in groups) _Sweep(g)];
}

double _median(List<double> xs) {
  if (xs.isEmpty) return double.nan;
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

void main() {
  final root =
      Platform.environment['GUITARSET_DIR'] ??
      'C:/Users/kcsab/Downloads/recipewis';
  final audioDir = Directory('$root/audio_mono-mic');
  final annDir = Directory('$root/annotation');
  final present = audioDir.existsSync() && annDir.existsSync();

  test(
    'string-arrival cue vs GuitarSet hexaphonic truth',
    () {
      final window =
          int.tryParse(Platform.environment['STRING_ARRIVAL_WINDOW'] ?? '') ??
          2048;
      final limit = int.tryParse(
        Platform.environment['STRING_ARRIVAL_LIMIT'] ?? '',
      );
      final env = Platform.environment;
      final hop = int.tryParse(env['STRING_ARRIVAL_HOP'] ?? '') ?? 64;
      final rise = double.tryParse(env['STRING_ARRIVAL_RISE'] ?? '') ?? 0.5;
      final minHz = double.tryParse(env['STRING_ARRIVAL_MINHZ'] ?? '') ?? 150;
      final maxHz = double.tryParse(env['STRING_ARRIVAL_MAXHZ'] ?? '') ?? 4000;
      final tiers = <String, List<int>>{}; // [total, correct]

      var wavs =
          audioDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('_comp_mic.wav'))
              .where(
                (f) => _styles.any((s) => f.uri.pathSegments.last.contains(s)),
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (limit != null) wavs = wavs.take(limit).toList();

      var sweeps = 0, covered = 0, correct = 0;
      final byPlayer = <String, List<int>>{}; // [total, covered, correct]
      final byDir = <StrumDirection, List<int>>{
        StrumDirection.down: [0, 0, 0],
        StrumDirection.up: [0, 0, 0],
      };
      final arrivalErrors = <double>[]; // per string, ms, mean-removed
      final spreadTrue = <double>[], spreadMeasured = <double>[];
      final slopeAgree = <bool>[];
      final trueSpreads = <double>[];
      final sw = Stopwatch()..start();

      for (final wav in wavs) {
        final name = wav.uri.pathSegments.last;
        final player = name.split('_').first;
        final stem = name.substring(0, name.length - '_mic.wav'.length);
        final jamsFile = File('${annDir.path}/$stem.jams');
        if (!jamsFile.existsSync()) continue;
        final jams =
            jsonDecode(jamsFile.readAsStringSync()) as Map<String, dynamic>;
        final (pcm, sr) = readWav(wav.path);
        final cue = StringArrivalCue(
          sampleRate: sr,
          windowSamples: window,
          hop: hop,
          riseFraction: rise,
          minPartialHz: minHz,
          maxPartialHz: maxHz,
        );

        for (final s in _sweeps(jams)) {
          if (!s.isClean) continue;
          sweeps++;
          trueSpreads.add(s.spreadMs);
          final truth = s.direction!;
          final hz = List<double?>.filled(6, null);
          final truthMs = List<double?>.filled(6, null);
          for (final n in s.notes) {
            hz[n.string] = 440 * math.pow(2, (n.midi - 69) / 12).toDouble();
            truthMs[n.string] = (n.time - s.atSec) * 1000;
          }
          final r = cue.analyze(pcm, (s.atSec * sr).round(), hz);
          final tally = byPlayer.putIfAbsent(player, () => [0, 0, 0]);
          tally[0]++;
          byDir[truth]![0]++;
          if (r.direction != null) {
            final tier = r.confidence >= 0.8
                ? 'high'
                : r.confidence >= 0.65
                ? 'mid'
                : 'low';
            final tt = tiers.putIfAbsent(tier, () => [0, 0]);
            tt[0]++;
            if (r.direction == truth) tt[1]++;
            covered++;
            tally[1]++;
            byDir[truth]![1]++;
            if (r.direction == truth) {
              correct++;
              tally[2]++;
              byDir[truth]![2]++;
            }
          }
          // Arrival error: measured vs true, per string, after removing the
          // sweep's mean offset (only the ORDER/spacing matters).
          final pairs = <(double, double)>[];
          for (var i = 0; i < 6; i++) {
            final m = r.arrivalMs[i], t = truthMs[i];
            if (m != null && t != null) pairs.add((m, t));
          }
          if (pairs.length >= 2) {
            final meanM =
                pairs.map((p) => p.$1).reduce((a, b) => a + b) / pairs.length;
            final meanT =
                pairs.map((p) => p.$2).reduce((a, b) => a + b) / pairs.length;
            for (final (m, t) in pairs) {
              arrivalErrors.add((m - meanM) - (t - meanT));
            }
            spreadTrue.add(s.spreadMs);
            var lo = double.infinity, hi = -double.infinity;
            for (final (m, _) in pairs) {
              lo = math.min(lo, m);
              hi = math.max(hi, m);
            }
            spreadMeasured.add(hi - lo);
            slopeAgree.add(
              (r.slopeMsPerString > 0) == (truth == StrumDirection.down),
            );
          }
        }
      }

      String pct(int a, int b) =>
          b == 0 ? '  n/a' : '${(100 * a / b).toStringAsFixed(1).padLeft(5)}%';
      final absErr = [for (final e in arrivalErrors) e.abs()];
      final out = StringBuffer()
        ..writeln(
          'GuitarSet ${_styles.join('+')} comping, ${wavs.length} files, window=$window hop=$hop rise=$rise minHz=$minHz maxHz=$maxHz, ${sw.elapsed.inSeconds}s',
        )
        ..writeln(
          'clean sweeps $sweeps  coverage ${pct(covered, sweeps)}  acc|cov ${pct(correct, covered)}  acc/all ${pct(correct, sweeps)}',
        )
        ..writeln(
          'true spread ms: median ${_median(trueSpreads).toStringAsFixed(1)}   per-string arrival |error| ms: median ${_median(absErr).toStringAsFixed(1)}  p75 ${(absErr..sort()).isEmpty ? 'n/a' : absErr[(absErr.length * 3) ~/ 4].toStringAsFixed(1)}',
        )
        ..writeln(
          'measured spread median ${_median(spreadMeasured).toStringAsFixed(1)} ms vs true ${_median(spreadTrue).toStringAsFixed(1)} ms; slope sign agrees ${pct(slopeAgree.where((b) => b).length, slopeAgree.length)} (n=${slopeAgree.length})',
        );
      for (final e in tiers.entries) {
        out.writeln(
          'tier ${e.key.padRight(4)} n=${e.value[0]} acc ${pct(e.value[1], e.value[0])}',
        );
      }
      for (final e in byDir.entries) {
        out.writeln(
          'truth ${e.key.name.padRight(4)} n=${e.value[0]} cov ${pct(e.value[1], e.value[0])} acc|cov ${pct(e.value[2], e.value[1])}',
        );
      }
      for (final e
          in byPlayer.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key))) {
        out.writeln(
          'player ${e.key} n=${e.value[0]} cov ${pct(e.value[1], e.value[0])} acc|cov ${pct(e.value[2], e.value[1])}',
        );
      }
      // ignore: avoid_print
      print(out);
      expect(sweeps, greaterThan(50));
    },
    skip: present ? false : 'GuitarSet absent (set GUITARSET_DIR)',
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
