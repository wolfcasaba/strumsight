// MEASUREMENT: what the SHIPPED pipeline hears in GuitarSet's strummed comping.
//
//   GUITARSET_DIR=/path/to/guitarset flutter test \
//     test/tooling/guitarset_strum_probe_test.dart
//
// The directory must contain `audio_mono-mic/` and `annotation/` as downloaded from
// https://zenodo.org/records/3371780 (GuitarSet, CC-BY 4.0). Self-skipping without
// the variable, so CI is untouched. **The recordings are NOT committed** — only the
// measurement is ever written down (AGENTS.md).
//
// ## Why this exists: we ship direction detection and had never measured it
//
// `docs/rounds/e14-r18-joint-streaming-prototype.md` states the gap plainly: the
// evaluation corpus's `.strums` files carry **no direction ground truth**, so the
// shipped classifier's end-to-end direction accuracy was `not-measured`, with only an
// upper bound (0.6739, its own onset F1 — a correct direction call needs a
// time-matched onset first, so TP_direction ⊆ TP_onset; ADR 0312/0517).
//
// GuitarSet closes that gap with nobody labelling anything by hand. It was recorded
// through a **hexaphonic pickup**, so its annotations carry note onsets PER STRING
// (`note_midi`, `data_source` 0..5). The order in which the strings were met IS the
// sweep direction — low strings first is a downstroke. That is the physical definition
// of the thing, not a proxy for it.
//
// ## The label is DERIVED, so its own quality is measured first
//
// Verified before trusting it (scratch exploration over all 180 comping files):
//
//   - `data_source` 0 really is the low E: its annotated pitches run from MIDI 40
//     (E2) and rise monotonically to source 5 at MIDI 64 (e4). The mapping is read
//     off the pitches, not assumed from documentation.
//   - the shipped classifier uses the SAME convention — `strum_direction_classifier`
//     computes `gap = highRise - lowRise`, positive meaning low-first meaning down —
//     so label and prediction agree about what "down" names.
//   - sweep spread: median 16-20 ms, p90 34-41 ms, so the 45 ms link distance below
//     sits above the p90 and far below a beat at any tempo here.
//   - direction counts are STABLE across link distances of 25-60 ms (Rock 2360/845 at
//     25 ms vs 2406/866 at 45 ms), so the label is not an artefact of that threshold.
//   - 67% (Rock) / 74% (Funk) of 3-or-more-note events are perfectly monotone in
//     string order. The remaining third is why direction is read from a pairwise
//     CONCORDANCE score rather than strict monotonicity: one out-of-order string
//     (annotation jitter, or a string that did not sound) must not flip a sweep.
//
// ## Only Rock and Funk comping, and that is also a measurement
//
// Bossa Nova comping reported MORE up than down (646 vs 1073) and Singer-Songwriter
// produced 3028 single-note events out of 5467. Both are fingerstyle accompaniment,
// where "strum direction" is not a property the playing has. Scoring a direction
// classifier against them would grade it on a question the audio does not answer.
//
// ## BOTH classifiers, because the first run measured the wrong one
//
// `LivePipeline(sampleRate:)` with no `crnnWeights` does not fail — it falls back to
// `HeuristicStrumClassifier` and records why (ADR 0355). Production does not take that
// path: `real_strum_engine.dart` loads `assets/ml/strum_crnn_live_3c.bin` and passes it
// in, preferring the 3-class model (down/up plus a learned no-strum reject) precisely
// so the live path can SUPPRESS false onsets.
//
// The first version of this file passed no weights. It would have reported the
// fallback heuristic's score as "ours" — the defect class `docs/LESSONS.md` L652 and
// L659 already record twice. It now runs BOTH arms through identical scoring code and
// prints them side by side, which makes the production path the headline and makes the
// mistake impossible to repeat quietly.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/core/music/onset_matching.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';

/// Single-link distance for grouping per-string onsets into one sweep.
const double _linkMs = 45;

/// Pick-strummed accompaniment styles. See the header for why the other three are out.
const List<String> _styles = ['Rock', 'Funk'];

/// The weights production prefers (`real_strum_engine.dart`). Read as a plain file
/// here — a test has no asset bundle, but these are the same bytes.
const String _liveCrnn3c = 'assets/ml/strum_crnn_live_3c.bin';

/// One annotated strum, derived from the per-string note onsets.
final class _Sweep {
  _Sweep({
    required this.atSec,
    required this.direction,
    required this.noteCount,
    required this.spreadMs,
    required this.monotone,
  });

  final double atSec;

  /// Null when the event carries no readable direction: a single note, or a tie.
  final StrumDirection? direction;
  final int noteCount;
  final double spreadMs;
  final bool monotone;

  /// The subset treated as high-confidence ground truth: a real sweep across at least
  /// three strings, in order, wide enough that the order is not timing noise.
  bool get isClean =>
      direction != null && noteCount >= 3 && monotone && spreadMs >= 5;
}

List<({double time, int string})> _perStringOnsets(Map<String, dynamic> jams) {
  final out = <({double time, int string})>[];
  for (final ann
      in (jams['annotations'] as List).cast<Map<String, dynamic>>()) {
    if (ann['namespace'] != 'note_midi') continue;
    final source =
        (ann['annotation_metadata'] as Map<String, dynamic>?)?['data_source'];
    final string = int.tryParse('$source');
    if (string == null) continue;
    for (final ob in (ann['data'] as List).cast<Map<String, dynamic>>()) {
      out.add((time: (ob['time'] as num).toDouble(), string: string));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// Direction from the ORDER the strings were met, by pairwise concordance.
///
/// Positive score = string index rises with time = the pick met the low strings first
/// = a downstroke. Concordance rather than strict monotonicity so one out-of-order
/// string cannot flip a sweep.
StrumDirection? _directionOf(List<({double time, int string})> sweep) {
  var score = 0;
  for (var i = 0; i < sweep.length; i++) {
    for (var k = i + 1; k < sweep.length; k++) {
      final dt = sweep[k].time - sweep[i].time;
      final ds = sweep[k].string - sweep[i].string;
      if (dt == 0 || ds == 0) continue;
      score += ds > 0 ? 1 : -1;
    }
  }
  if (score > 0) return StrumDirection.down;
  if (score < 0) return StrumDirection.up;
  return null;
}

List<_Sweep> _sweeps(Map<String, dynamic> jams) {
  final onsets = _perStringOnsets(jams);
  final groups = <List<({double time, int string})>>[];
  for (final onset in onsets) {
    if (groups.isNotEmpty &&
        (onset.time - groups.last.last.time) * 1000 <= _linkMs) {
      groups.last.add(onset);
    } else {
      groups.add([onset]);
    }
  }
  return [
    for (final group in groups)
      _Sweep(
        atSec: group.first.time,
        direction: group.length < 2 ? null : _directionOf(group),
        noteCount: group.length,
        spreadMs: (group.last.time - group.first.time) * 1000,
        monotone: _isMonotone([for (final o in group) o.string]),
      ),
  ];
}

bool _isMonotone(List<int> indices) {
  final sorted = [...indices]..sort();
  return _same(indices, sorted) || _same(indices, sorted.reversed.toList());
}

bool _same(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What the pipeline reports: every strum, with the direction it called.
List<({double atSec, StrumDirection? direction})> _heard(
  List<double> pcm,
  int sampleRate, {
  Uint8List? crnnWeights,
  int chunk = 1024,
}) {
  final pipeline = LivePipeline(
    sampleRate: sampleRate,
    crnnWeights: crnnWeights,
  );
  final out = <({double atSec, StrumDirection? direction})>[];
  var lastSeq = 0;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = math.min(i + chunk, pcm.length);
    for (final frame in pipeline.addChunk(pcm.sublist(i, end))) {
      if (frame.strumSeq > lastSeq) {
        lastSeq = frame.strumSeq;
        out.add((
          atSec: frame.latestStrumTime,
          direction: frame.latestStrum?.direction,
        ));
      }
    }
  }
  return out;
}

/// Greedy nearest-available one-to-one matching, the same shape
/// `recognition_metrics.dart` uses, so these numbers are comparable to the project's.
List<({int expected, int detected})> _match(
  List<double> expected,
  List<double> detected, {
  double toleranceMs = onsetToleranceMsPrimary * 1.0,
}) {
  final pairs = <({int expected, int detected})>[];
  final taken = <int>{};
  for (var e = 0; e < expected.length; e++) {
    var best = -1;
    var bestGap = double.infinity;
    for (var d = 0; d < detected.length; d++) {
      if (taken.contains(d)) continue;
      final gap = (detected[d] - expected[e]).abs() * 1000;
      if (gap <= toleranceMs && gap < bestGap) {
        bestGap = gap;
        best = d;
      }
    }
    if (best >= 0) {
      taken.add(best);
      pairs.add((expected: e, detected: best));
    }
  }
  return pairs;
}

double _f1(int tp, int fp, int fn) {
  if (tp == 0) return 0;
  final precision = tp / (tp + fp);
  final recall = tp / (tp + fn);
  return 2 * precision * recall / (precision + recall);
}

/// One arm's tallies. Both classifiers are scored by this same code, so the two
/// numbers differ only by the model behind them.
final class _Score {
  int onsetTp = 0;
  int onsetFp = 0;
  int onsetFn = 0;

  /// Real STRUMS found, over real strums present. Reported separately because the
  /// annotated event list also contains single plucked notes, and the shipped
  /// 3-class model has a learned no-strum reject whose JOB is to drop those —
  /// counting them as misses would penalise it for working.
  int strumFound = 0;
  int strumTotal = 0;
  int abstained = 0;
  final Map<StrumDirection, int> tp = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };
  final Map<StrumDirection, int> fp = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };
  final Map<StrumDirection, int> fn = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };

  void add(
    List<_Sweep> sweeps,
    List<double> expectedTimes,
    List<({double atSec, StrumDirection? direction})> heard,
  ) {
    final detectedTimes = [for (final h in heard) h.atSec];
    final pairs = _match(expectedTimes, detectedTimes);
    onsetTp += pairs.length;
    onsetFp += detectedTimes.length - pairs.length;
    onsetFn += expectedTimes.length - pairs.length;

    strumTotal += sweeps.where((s) => s.isClean).length;
    for (final pair in pairs) {
      final sweep = sweeps[pair.expected];
      if (!sweep.isClean) continue;
      strumFound++;
      final truth = sweep.direction!;
      final called = heard[pair.detected].direction;
      if (called == null) {
        // An abstention is not a wrong answer and is not scored as one: the
        // classifier returns null when the cue is genuinely ambiguous. It IS a
        // missed detection for the true class.
        abstained++;
        fn[truth] = fn[truth]! + 1;
        continue;
      }
      if (called == truth) {
        tp[truth] = tp[truth]! + 1;
      } else {
        fn[truth] = fn[truth]! + 1;
        fp[called] = fp[called]! + 1;
      }
    }
  }

  double get onsetF1 => _f1(onsetTp, onsetFp, onsetFn);
  double get precision => onsetTp == 0 ? 0 : onsetTp / (onsetTp + onsetFp);
  double get recall => onsetTp == 0 ? 0 : onsetTp / (onsetTp + onsetFn);

  /// Recall over real strums only — the fair denominator for a strum detector.
  double get strumRecall => strumTotal == 0 ? 0 : strumFound / strumTotal;
  double dirF1(StrumDirection d) => _f1(tp[d]!, fp[d]!, fn[d]!);
  double get dirMacroF1 =>
      (dirF1(StrumDirection.down) + dirF1(StrumDirection.up)) / 2;

  void writeTo(StringBuffer out, String label) {
    out.writeln(label);
    out.writeln(
      '    ONSET @${onsetToleranceMsPrimary}ms  '
      'TP $onsetTp FP $onsetFp FN $onsetFn  '
      'P=${precision.toStringAsFixed(3)} R=${recall.toStringAsFixed(3)} '
      'F1=${onsetF1.toStringAsFixed(4)}',
    );
    out.writeln(
      '    STRUMS ONLY  found $strumFound of $strumTotal  '
      'recall=${strumRecall.toStringAsFixed(3)}',
    );
    out.writeln('    DIRECTION (matched clean sweeps)');
    for (final d in StrumDirection.values) {
      out.writeln(
        '      ${d.name.padRight(4)} TP ${tp[d]} FP ${fp[d]} FN ${fn[d]}  '
        'F1=${dirF1(d).toStringAsFixed(4)}',
      );
    }
    out.writeln(
      '      macro-F1 = ${dirMacroF1.toStringAsFixed(4)}   '
      'abstentions $abstained',
    );
  }
}

void main() {
  final root = Platform.environment['GUITARSET_DIR'];
  if (root == null || root.isEmpty) {
    test('skipped: GUITARSET_DIR not set', () {
      // Nothing to measure without the corpus; CI must stay green.
    });
    return;
  }

  test(
    'PROBE: onset and DIRECTION against GuitarSet comping',
    () {
      final audioDir = Directory('$root/audio_mono-mic');
      final annDir = Directory('$root/annotation');
      expect(
        audioDir.existsSync(),
        isTrue,
        reason: 'audio_mono-mic/ must exist',
      );
      expect(annDir.existsSync(), isTrue, reason: 'annotation/ must exist');

      // The shipped weights, read once. A missing asset fails hard rather than falling
      // back quietly: falling back is exactly the mistake this file was rewritten to
      // stop making.
      final weightsFile = File(_liveCrnn3c);
      expect(
        weightsFile.existsSync(),
        isTrue,
        reason:
            '$_liveCrnn3c must exist — without it this probe would measure the '
            'heuristic fallback and report it as the production path',
      );
      final weights = Uint8List.fromList(weightsFile.readAsBytesSync());

      final shipped = _Score();
      final fallback = _Score();
      var files = 0;
      var allSweeps = 0;
      var cleanSweeps = 0;
      var unreadable = 0;

      final wavs =
          audioDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('_comp_mic.wav'))
              .where(
                (f) => _styles.any((s) => f.uri.pathSegments.last.contains(s)),
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(wavs, isNotEmpty, reason: 'no Rock/Funk comping files found');

      for (final wav in wavs) {
        final name = wav.uri.pathSegments.last.replaceAll('_mic.wav', '');
        final jamsFile = File('${annDir.path}/$name.jams');
        if (!jamsFile.existsSync()) continue;

        final decoded = WavDecoder.decode(
          Uint8List.fromList(wav.readAsBytesSync()),
        );
        if (decoded == null) continue;
        final (pcm, sampleRate) = decoded;

        final jams =
            jsonDecode(jamsFile.readAsStringSync()) as Map<String, dynamic>;
        final sweeps = _sweeps(jams);
        allSweeps += sweeps.length;
        cleanSweeps += sweeps.where((s) => s.isClean).length;
        unreadable += sweeps.where((s) => s.direction == null).length;

        final expectedTimes = [for (final s in sweeps) s.atSec];
        shipped.add(
          sweeps,
          expectedTimes,
          _heard(pcm, sampleRate, crnnWeights: weights),
        );
        fallback.add(sweeps, expectedTimes, _heard(pcm, sampleRate));
        files++;
      }

      final out = StringBuffer();
      out.writeln();
      out.writeln(
        'GuitarSet comping, styles ${_styles.join('+')} — $files files',
      );
      out.writeln('  annotated sweeps : $allSweeps');
      out.writeln(
        '    no readable direction : $unreadable (single note or tie)',
      );
      out.writeln(
        '    clean (>=3 strings, in order, spread >=5 ms) : $cleanSweeps',
      );
      out.writeln();
      shipped.writeTo(out, '  SHIPPED: CRNN 3-class (what production loads)');
      out.writeln();
      fallback.writeTo(out, '  FALLBACK: heuristic (no weights passed)');
      // ignore: avoid_print — the printed numbers ARE this file's deliverable.
      print(out);

      // Reported, not gated. This is a probe: the numbers are the deliverable, and a
      // threshold here would turn a corpus the project has never measured against into
      // a pass/fail on someone else's recordings. The Alpha gates live in Chapter 14
      // §7.2 and are applied by the rollout decision, not here.
      expect(files, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
