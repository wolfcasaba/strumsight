// MEASUREMENT: the down/up decision boundary, split by PLAYER so it cannot be a
// corpus fit.
//
//   GUITARSET_DIR=/path/to/guitarset flutter test \
//     test/tooling/guitarset_direction_boundary_test.dart
//
// Self-skipping without the variable. **The recordings are NOT committed.**
//
// ## The defect this is about
//
// After ADR 0549 the shipped path measures direction like this on GuitarSet's
// Rock/Funk comping (`docs/eval/guitarset-strum-baseline.md`):
//
//   down: TP 696  FP 135  FN 919   -> truth 1615 down, predicted  831 down
//   up  : TP 219  FP 919  FN 135   -> truth  354 up,   predicted 1138 up
//
// The ground truth is 82% downstrokes and the model answers "up" 58% of the time. 919
// genuine downstrokes are called upstrokes — one systematic bias that dwarfs every
// other error in the direction score. And the decision making it is a bare argmax:
//
//   live_crnn_classifier.dart:239   final up = pUp > pDown;
//
// i.e. a boundary pinned at 0.5 on a renormalised two-class probability. Nothing fitted
// it; it is what argmax means.
//
// ## Why this file splits by player, and why that is the whole point
//
// ADR 0549 has just recorded the cost of fitting a decision to one corpus and using it
// on another: the no-strum gate kept 95% of true strums on its own eval fold and 59.6%
// here. Moving the direction boundary because THIS corpus is 82% down would be the same
// mistake in a new place — an improvement that is really just prior-matching, and that
// would make the app worse for a learner practising upstroke-heavy patterns (reggae
// skank, the app's own `reggae-skank` lesson, is nearly all upstrokes).
//
// So the corpus is split by PLAYER — tune on 00/01/02, evaluate on 03/04/05, no overlap
// in performer or take. A boundary that only exploits the class prior will not survive
// that, and the per-split priors are printed alongside so the reader can see whether it
// did or whether the two halves simply look alike.
//
// The shipped no-strum gate is applied, so the numbers describe what production sees
// rather than an idealised stream.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/core/music/onset_matching.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/engine/ml/live_crnn_classifier.dart';

const double _linkMs = 45;
const List<String> _styles = ['Rock', 'Funk'];
const String _liveCrnn3c = 'assets/ml/strum_crnn_live_3c.bin';
const int _sampleRate = 44100;

/// Players whose takes fit the boundary, and players it is then judged on. Disjoint by
/// construction — the point of the file.
const Set<String> _tunePlayers = {'00', '01', '02'};
const Set<String> _testPlayers = {'03', '04', '05'};

/// Candidate boundaries on P(up). 0.5 is today's argmax.
const List<double> _boundaries = [0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90];

/// Strums lost to frame coalescing (see `guitarset_threshold_sweep_test.dart`).
int coalesced = 0;

final class _Sweep {
  _Sweep({
    required this.atSec,
    required this.direction,
    required this.noteCount,
    required this.spreadMs,
    required this.monotone,
  });
  final double atSec;
  final StrumDirection? direction;
  final int noteCount;
  final double spreadMs;
  final bool monotone;
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

typedef _Heard = ({double atSec, double pUp, double pNoStrum});

/// Records the model's raw verdict and suppresses nothing, so one pass can be rescored
/// at any boundary. The pipeline's own margin gate is bypassed by reporting a direction
/// with no probabilities (see `guitarset_threshold_sweep_test.dart` for why).
final class _Recorder implements StrumDirectionClassifier {
  _Recorder(this._inner);
  final LiveCrnnStrumClassifier _inner;
  final List<StrumClassification> calls = [];

  @override
  void observe(Float64List frame, StrumFrameFeatures features) =>
      _inner.observe(frame, features);

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) {
    final result = _inner.classifyAt(
      onsetFrame: onsetFrame,
      currentFrame: currentFrame,
    );
    calls.add(result);
    return const StrumClassification(
      direction: StrumDirection.down,
      confidence: 1,
    );
  }
}

List<_Heard> _heard(List<double> pcm, LiveCrnnStrumClassifier crnn) {
  const chunk = 1024;
  final recorder = _Recorder(crnn);
  final pipeline = LivePipeline.debugWithClassifier(
    recorder,
    sampleRate: _sampleRate,
  );
  final padded = [...pcm, ...List<double>.filled(_sampleRate, 0)];
  final times = <double?>[];
  var lastSeq = 0;
  for (var i = 0; i < padded.length; i += chunk) {
    final end = math.min(i + chunk, padded.length);
    for (final frame in pipeline.addChunk(padded.sublist(i, end))) {
      if (frame.strumSeq > lastSeq) {
        final jumped = frame.strumSeq - lastSeq;
        lastSeq = frame.strumSeq;
        for (var k = 1; k < jumped; k++) {
          times.add(null);
        }
        times.add(frame.latestStrumTime);
      }
    }
  }
  expect(times.length, recorder.calls.length);
  coalesced += times.where((t) => t == null).length;
  return [
    for (var i = 0; i < times.length; i++)
      if (times[i] != null &&
          recorder.calls[i].pUp != null &&
          recorder.calls[i].pNoStrum != null)
        (
          atSec: times[i]!,
          pUp: recorder.calls[i].pUp!,
          pNoStrum: recorder.calls[i].pNoStrum!,
        ),
  ];
}

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
  final p = tp / (tp + fp);
  final r = tp / (tp + fn);
  return 2 * p * r / (p + r);
}

/// One matched, clean sweep: the truth and the model's P(up) for it.
typedef _Case = ({StrumDirection truth, double pUp});

final class _DirScore {
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

  void add(StrumDirection truth, StrumDirection called) {
    if (called == truth) {
      tp[truth] = tp[truth]! + 1;
    } else {
      fn[truth] = fn[truth]! + 1;
      fp[called] = fp[called]! + 1;
    }
  }

  double f1(StrumDirection d) => _f1(tp[d]!, fp[d]!, fn[d]!);
  double get macroF1 => (f1(StrumDirection.down) + f1(StrumDirection.up)) / 2;
  int get n =>
      tp.values.reduce((a, b) => a + b) + fn.values.reduce((a, b) => a + b);
}

_DirScore _scoreAt(List<_Case> cases, double boundary) {
  final score = _DirScore();
  for (final c in cases) {
    score.add(
      c.truth,
      c.pUp > boundary ? StrumDirection.up : StrumDirection.down,
    );
  }
  return score;
}

String _prior(List<_Case> cases) {
  if (cases.isEmpty) return 'n/a';
  final down = cases.where((c) => c.truth == StrumDirection.down).length;
  return '${(100 * down / cases.length).toStringAsFixed(0)}% down '
      '(${cases.length} cases)';
}

void main() {
  final root = Platform.environment['GUITARSET_DIR'];
  if (root == null || root.isEmpty) {
    test('skipped: GUITARSET_DIR not set', () {});
    return;
  }

  test(
    'MEASURE: the down/up boundary, tuned and tested on DIFFERENT players',
    () {
      final audioDir = Directory('$root/audio_mono-mic');
      final annDir = Directory('$root/annotation');
      expect(audioDir.existsSync(), isTrue);
      expect(annDir.existsSync(), isTrue);
      expect(File(_liveCrnn3c).existsSync(), isTrue);

      final tune = <_Case>[];
      final test_ = <_Case>[];
      var files = 0;

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
      expect(wavs, isNotEmpty);

      for (final wav in wavs) {
        final fileName = wav.uri.pathSegments.last;
        final player = fileName.split('_').first;
        final into = _tunePlayers.contains(player)
            ? tune
            : (_testPlayers.contains(player) ? test_ : null);
        if (into == null) continue;

        final name = fileName.replaceAll('_mic.wav', '');
        final jamsFile = File('${annDir.path}/$name.jams');
        if (!jamsFile.existsSync()) continue;
        final decoded = WavDecoder.decode(
          Uint8List.fromList(wav.readAsBytesSync()),
        );
        if (decoded == null) continue;

        final sweeps = _sweeps(
          jsonDecode(jamsFile.readAsStringSync()) as Map<String, dynamic>,
        );
        // The classifier is built PER FILE: its frontend is stateful and each file
        // starts a pipeline whose frame counter restarts (LESSONS L663).
        final crnn = LiveCrnnStrumClassifier.tryLoad(
          _liveCrnn3c,
          sampleRate: _sampleRate,
        );
        expect(crnn, isNotNull);
        // The SHIPPED gate is applied, so these cases are the ones production would
        // actually have judged.
        final heard = [
          for (final h in _heard(decoded.$1, crnn!))
            if (h.pNoStrum <= LiveCrnnStrumClassifier.noStrumThreshold) h,
        ];
        final pairs = _match(
          [for (final s in sweeps) s.atSec],
          [for (final h in heard) h.atSec],
        );
        for (final pair in pairs) {
          final sweep = sweeps[pair.expected];
          if (!sweep.isClean) continue;
          into.add((truth: sweep.direction!, pUp: heard[pair.detected].pUp));
        }
        files++;
      }

      expect(tune, isNotEmpty);
      expect(test_, isNotEmpty);

      final out = StringBuffer();
      out.writeln();
      out.writeln(
        'GuitarSet comping ${_styles.join('+')} — $files files, '
        '$coalesced excluded as frame-coalesced',
      );
      out.writeln('  tune players ${_tunePlayers.join('/')}: ${_prior(tune)}');
      out.writeln('  test players ${_testPlayers.join('/')}: ${_prior(test_)}');
      out.writeln();
      out.writeln(
        '  P(up)>   tuneDown  tuneUp  tuneMacro | testDown  testUp  testMacro',
      );
      for (final boundary in _boundaries) {
        final a = _scoreAt(tune, boundary);
        final b = _scoreAt(test_, boundary);
        final mark = boundary == 0.5 ? '*' : ' ';
        out.writeln(
          '  ${boundary.toStringAsFixed(2)}$mark    '
          '${a.f1(StrumDirection.down).toStringAsFixed(4).padLeft(8)}  '
          '${a.f1(StrumDirection.up).toStringAsFixed(4).padLeft(6)}  '
          '${a.macroF1.toStringAsFixed(4).padLeft(9)} | '
          '${b.f1(StrumDirection.down).toStringAsFixed(4).padLeft(8)}  '
          '${b.f1(StrumDirection.up).toStringAsFixed(4).padLeft(6)}  '
          '${b.macroF1.toStringAsFixed(4).padLeft(9)}',
        );
      }
      out.writeln('  (* = today\'s argmax)');

      // The honest summary: pick the boundary on TUNE, then report what it scores on
      // TEST. Choosing by the test column would be the corpus fit this file exists to
      // avoid.
      var bestBoundary = 0.5;
      var bestTuneMacro = -1.0;
      for (final boundary in _boundaries) {
        final macro = _scoreAt(tune, boundary).macroF1;
        if (macro > bestTuneMacro) {
          bestTuneMacro = macro;
          bestBoundary = boundary;
        }
      }
      final heldOut = _scoreAt(test_, bestBoundary);
      final todayHeldOut = _scoreAt(test_, 0.5);
      out.writeln();
      out.writeln(
        '  chosen on TUNE: P(up) > ${bestBoundary.toStringAsFixed(2)} '
        '(tune macro ${bestTuneMacro.toStringAsFixed(4)})',
      );
      out.writeln(
        '  held-out TEST at that boundary: macro '
        '${heldOut.macroF1.toStringAsFixed(4)} '
        'vs ${todayHeldOut.macroF1.toStringAsFixed(4)} at today\'s 0.50 '
        '(n=${heldOut.n})',
      );
      // ignore: avoid_print — the table IS this file's deliverable.
      print(out);

      expect(files, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
