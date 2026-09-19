// MEASUREMENT: what does the no-strum gate cost, and what would another gate buy?
//
//   GUITARSET_DIR=/path/to/guitarset flutter test \
//     test/tooling/guitarset_threshold_sweep_test.dart
//
// Self-skipping without the variable. **The recordings are NOT committed.**
//
// ## The question, and why it is a sweep rather than a rebuild
//
// `docs/eval/guitarset-strum-baseline.md` measured the shipped path at direction
// macro-F1 0.4195 and a true-strum retention of 0.595, against a fallback heuristic
// that retains 0.954 but calls direction almost backwards (macro-F1 0.2953). That
// looked like two different detectors. It is not:
//
//   strum_analyzer.dart: final onsetSec = _onsets.processFrame(frame);   // SuperFlux
//   strum_analyzer.dart: if (c.suppressed) return null;                  // the veto
//
// **Both arms detect onsets with the same SuperFlux.** What differs is the gates that
// follow — and measuring them revealed that there are TWO, stacked:
//
//   1. `LiveCrnnStrumClassifier.noStrumThreshold` (0.43877), the learned no-strum
//      reject, applied inside the classifier;
//   2. a MARGIN gate in `live_pipeline.dart`, where `_strumSeq` advances only when
//      `_isDirectionConfirmed(event)` — which defers to `StrumPrediction.decision`,
//      and for a probability-less event (the heuristic) returns true
//      UNCONDITIONALLY.
//
// So the heuristic arm faces neither gate and the CRNN arm faces both. The baseline
// round attributed the whole retention loss to gate 1; that was incomplete, and this
// sweep separates them. The second gate was found by a zip-length assertion failing —
// 173 classifications published only 172 strums — not by reading the code.
//
// That scalar's own doc states it was fitted as the P(no-strum) quantile keeping
// **95% of true strums** on this model's held-out eval fold (n=2013), while rejecting
// 93% of false onsets. On GuitarSet it keeps **59.5%**. The gate is therefore
// corpus-dependent in a way nothing had measured, and the useful experiment is not a
// new architecture: it is to ask what the SAME model would have scored at a different
// gate.
//
// ## One pass, every threshold
//
// Suppression has no feedback into detection — the analyzer's onsets are computed
// before the classifier is consulted and do not depend on its verdict. So the sweep
// does not need one run per threshold. A wrapper records every classification's raw
// probabilities and never suppresses, which yields one pass over the corpus in which
// EVERY SuperFlux onset is present with the model's P(no-strum) attached. Each
// candidate gate is then evaluated offline over that record.
//
// This is why `classifyProbs` now exports probabilities on its suppressed branch too
// (an additive change production cannot observe): without them the suppressed onsets
// would be exactly the ones a sweep cannot see.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/core/music/onset_matching.dart';
import '../support/live_sweep_harness.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/ml/crnn_strum_net.dart';
import 'package:strumsight/features/live/engine/ml/live_crnn_classifier.dart';

const double _linkMs = 45;
const List<String> _styles = ['Rock', 'Funk'];

/// The 3-class asset under test, overridable with `STRUM_3C_ASSET`.
///
/// It has to be overridable, and the reason is a mistake worth naming. ADR 0555 D3 left
/// a SECOND 3-class asset in the tree deliberately unwired
/// (`strum_crnn_live_3c_settled.bin`), while `ml/weights_live_3c_settled.npz` — what
/// every `ml/probe_*.py` loads — is that asset's weights, NOT the shipped one's. So a
/// Python retention number and this sweep's retention number are measured on DIFFERENT
/// MODELS unless this path is pointed at the settled asset. Dividing one by the other
/// and calling the quotient a property of the production path is two experiments wearing
/// one number's clothes (E18-R43; LESSONS L682).
///
/// The default stays the shipped asset, so an unconfigured run measures production.
/// Restrict the corpus to the HELD-OUT split with `STRUM_SPLIT=heldout`.
///
/// Mandatory whenever the asset under test trained on GuitarSet. The settled asset did
/// (ADR 0554), and all 72 files include players 00-02 and the 8 training tunes, so an
/// unsplit number is CONTAMINATED — it would report the model's memory as its skill. The
/// shipped asset did not train here, so for it the unsplit run is honest; comparing the
/// two therefore has to happen on the SAME split, which is the whole reason this knob
/// exists (ADR 0567, LESSONS L682 §1).
const _testPlayers = {'03', '04', '05'};
const _testTunes = {
  'Funk3-112-C#',
  'Funk3-98-A',
  'Rock3-117-Bb',
  'Rock3-148-C',
};

/// True when [name] (a `*_comp_mic.wav` basename) is in the requested split.
bool _inSplit(String name) {
  if ((Platform.environment['STRUM_SPLIT'] ?? '') != 'heldout') return true;
  final player = name.substring(0, 2);
  final tune = name.substring(3).replaceAll('_comp_mic.wav', '');
  return _testPlayers.contains(player) && _testTunes.contains(tune);
}

String get _liveCrnn3c =>
    Platform.environment['STRUM_3C_ASSET'] ??
    'assets/ml/strum_crnn_live_3c.bin';

/// One definition, shared with the Klangio sweep through the harness.
const int _sampleRate = kSweepSampleRate;

/// The gates to compare. The first is what ships; 1.01 never suppresses, which is the
/// composition the baseline measurement pointed at — the CRNN judging direction on
/// every SuperFlux onset instead of only the ones it keeps.
typedef _Gate = Gate;

/// The canonical ladder lives in the harness so the Klangio sweep prints the same
/// rows. The duplicate guard below is what makes the value-equal collision the
/// harness documents impossible here.
const List<_Gate> _gates = kSweepGates;

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

/// Strums lost to frame coalescing across the whole run — reported, never hidden.
int coalesced = 0;

// The streaming pass, the settled window, the margin gate and the onset matcher all live
// in `test/support/live_sweep_harness.dart`, so the Klangio sweep drives the pipeline with
// the SAME instrument. A cross-corpus delta means nothing otherwise (L269, L682).

/// Tallies for one candidate gate.
final class _GateScore {
  int kept = 0;
  int onsetTp = 0;
  int onsetFp = 0;
  int onsetFn = 0;
  int strumFound = 0;
  int strumTotal = 0;

  /// False positives split by distance to the NEAREST annotated event, because the
  /// rhythm grader treats the three distances completely differently (ADR 0566).
  ///
  /// A phantom inside [onsetToleranceMsPrimary] of an annotated event is a DOUBLE
  /// TRIGGER: `gradeRhythm` matches with maximum cardinality, so it competes with the
  /// learner's real stroke for that slot and can WIN it, putting its own direction on a
  /// stroke the learner played correctly. A phantom farther out can only land in a slot
  /// the learner MISSED, or in none at all — where it becomes `extraConfirmedStrokes`,
  /// which subtracts nothing.
  ///
  /// Counted rather than assumed because the mined-negative corpus cannot answer it:
  /// `ml/negatives.py` excludes every candidate within its 120 ms margin of an annotated
  /// onset, so the double-trigger population is absent there BY CONSTRUCTION.
  int fpWithinTolerance = 0;
  int fpWithinMargin = 0;
  int fpBeyondMargin = 0;

  /// Signed `detected - annotated` milliseconds for every matched onset. Positive
  /// means the pipeline reported the stroke LATE.
  ///
  /// This decides between the two surviving explanations for the 30-point gap
  /// between the gate's retention on Python-built windows at annotated onsets
  /// (0.944 at gate 0.439) and its retention in situ (0.633): either the detector
  /// lands late often enough that the concave retention-vs-offset curve
  /// (`ml/probe_gate_window_jitter.py`) accounts for it, or the production feature
  /// chain differs from the Python one in a way the parity fixtures do not cover.
  /// The +-50 ms match tolerance admits a detection 45 ms late as "found" while its
  /// classification window is far past the attack, so the mean says little and the
  /// TAIL is the quantity that matters.
  final List<double> lagsMs = [];

  /// P(no-strum) as PRODUCTION computed it, for onsets matched to a CLEAN sweep.
  ///
  /// The direct counterpart of the Python number over the same sweeps: 0.0063 median,
  /// 0.944 retention at gate 0.439 (`ml/probe_gate_window_jitter.py`, offset 0). In situ
  /// the same gate keeps 0.633 of the sweeps the detector finds. Three candidate causes
  /// were eliminated (population, window centring, resampler kind), so this column is
  /// what localises the rest: if the median here is ~0.006 the gap is about WHICH onsets
  /// get matched, and if it is far higher the production window itself differs from the
  /// one the gate was calibrated on.
  ///
  /// Read the `none` row: with no gate every onset is present, so this is the honest
  /// production distribution over real strums, and 1 - share(>g) IS the retention a
  /// candidate gate `g` would deliver on production windows.
  final List<double> matchedStrumPNoStrum = [];
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

  /// The same direction tallies, but with the SETTLED (untruncated) call deciding the
  /// direction while the FAST call still decides EXISTENCE — the arrangement ADR 0559 D2
  /// fixes (the gate is the live deadline's decision and the settled tier never revises
  /// it). ADR 0570 measured +0.1919 macro for this on ORACLE windows; these are the
  /// in-situ counterpart.
  final Map<StrumDirection, int> stp = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };
  final Map<StrumDirection, int> sfp = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };
  final Map<StrumDirection, int> sfn = {
    StrumDirection.down: 0,
    StrumDirection.up: 0,
  };

  /// Strums whose settled window could not be built (end of take) — excluded from the
  /// settled columns and REPORTED, because a silent exclusion is a quieter error.
  int settledMissing = 0;

  double sDirF1(StrumDirection d) => f1(stp[d]!, sfp[d]!, sfn[d]!);
  double get sDirMacroF1 =>
      (sDirF1(StrumDirection.down) + sDirF1(StrumDirection.up)) / 2;

  double get onsetF1 => f1(onsetTp, onsetFp, onsetFn);
  double get precision => onsetTp == 0 ? 0 : onsetTp / (onsetTp + onsetFp);
  double get strumRecall => strumTotal == 0 ? 0 : strumFound / strumTotal;
  double dirF1(StrumDirection d) => f1(tp[d]!, fp[d]!, fn[d]!);
  double get dirMacroF1 =>
      (dirF1(StrumDirection.down) + dirF1(StrumDirection.up)) / 2;
}

void main() {
  final root = Platform.environment['GUITARSET_DIR'];
  if (root == null || root.isEmpty) {
    test('skipped: GUITARSET_DIR not set', () {});
    return;
  }

  test(
    'MEASURE: the no-strum gate, swept',
    () {
      final audioDir = Directory('$root/audio_mono-mic');
      final annDir = Directory('$root/annotation');
      expect(audioDir.existsSync(), isTrue);
      expect(annDir.existsSync(), isTrue);

      // The classifier is constructed PER FILE below, never hoisted.
      // `LiveCrnnStrumClassifier` owns a `LiveCrnnFrontend` that buffers audio and
      // indexes frames, while each file starts a fresh pipeline whose frame counter
      // restarts at zero — so one shared instance has the model reading windows out of
      // the PREVIOUS file's audio. Measured: a hoisted instance kept 15 of 10286
      // onsets at the shipped gate, against 3784 in the real run. The onset columns
      // were unaffected, because they do not come from the model — which is exactly
      // what pointed at the frontend rather than at the gate.
      expect(
        File(_liveCrnn3c).existsSync(),
        isTrue,
        reason:
            '$_liveCrnn3c must exist — a silent fallback here is the trap this '
            'corpus already caught once (LESSONS L662)',
      );

      final scores = {for (final gate in _gates) gate: _GateScore()};
      // Two value-equal gates would share one tally and print doubled counts. This
      // already happened once (see [_gates]); a table that silently double-counts is
      // worse than a missing row, because nothing in it looks wrong.
      expect(
        scores.length,
        _gates.length,
        reason:
            'the gate list has value-equal duplicates, so their tallies merge and '
            'every COUNT for that row is multiplied by how many times it appears',
      );
      var files = 0;
      var totalOnsets = 0;
      var withProbs = 0;

      // One parse for the whole run: the offline settled pass needs the net directly,
      // and re-parsing a 1.4 MB blob per file would be the measurement's own bottleneck.
      final settledNet = CrnnStrumNet.parse(
        ByteData.sublistView(File(_liveCrnn3c).readAsBytesSync()),
      );
      final wavs =
          audioDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('_comp_mic.wav'))
              .where(
                (f) => _styles.any((s) => f.uri.pathSegments.last.contains(s)),
              )
              .where((f) => _inSplit(f.uri.pathSegments.last))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(wavs, isNotEmpty);

      for (final wav in wavs) {
        final name = wav.uri.pathSegments.last.replaceAll('_mic.wav', '');
        final jamsFile = File('${annDir.path}/$name.jams');
        if (!jamsFile.existsSync()) continue;
        final decoded = WavDecoder.decode(
          Uint8List.fromList(wav.readAsBytesSync()),
        );
        if (decoded == null) continue;

        final sweeps = _sweeps(
          jsonDecode(jamsFile.readAsStringSync()) as Map<String, dynamic>,
        );
        final expectedTimes = [for (final s in sweeps) s.atSec];
        final crnn = LiveCrnnStrumClassifier.tryLoad(
          _liveCrnn3c,
          sampleRate: _sampleRate,
        );
        expect(crnn, isNotNull, reason: 'the weights must parse');
        final pass = heardWithProbs(decoded.$1, crnn!, settledNet);
        final heard = pass.heard;
        coalesced += pass.coalesced;
        totalOnsets += heard.length;
        withProbs += heard.where((h) => h.pNoStrum != null).length;

        for (final gate in _gates) {
          final score = scores[gate]!;
          // Apply the candidate gate to the SAME recorded onsets.
          final keptHeard = [
            for (final h in heard)
              if ((h.pNoStrum ?? 0) <= gate.suppress &&
                  (!gate.margin || marginConfirms(h)))
                h,
          ];
          score.kept += keptHeard.length;
          final pairs = matchOnsets(
            expectedTimes,
            [for (final h in keptHeard) h.atSec],
            // Explicit now. `_match` defaulted it, which hid the coupling between the
            // sweep's onset tolerance and `onset_matching.dart`'s constant.
            toleranceMs: onsetToleranceMsPrimary * 1.0,
          );
          score.onsetTp += pairs.length;
          score.onsetFp += keptHeard.length - pairs.length;
          score.onsetFn += expectedTimes.length - pairs.length;
          // Where did the phantoms fall? See [_GateScore.fpWithinTolerance].
          final matchedDetections = {for (final pair in pairs) pair.detected};
          for (var d = 0; d < keptHeard.length; d++) {
            if (matchedDetections.contains(d)) continue;
            var nearestMs = double.infinity;
            for (final e in expectedTimes) {
              final gap = (keptHeard[d].atSec - e).abs() * 1000;
              if (gap < nearestMs) nearestMs = gap;
            }
            if (nearestMs <= onsetToleranceMsPrimary) {
              score.fpWithinTolerance++;
            } else if (nearestMs <= 120) {
              score.fpWithinMargin++;
            } else {
              score.fpBeyondMargin++;
            }
          }
          score.strumTotal += sweeps.where((s) => s.isClean).length;
          for (final pair in pairs) {
            score.lagsMs.add(
              (keptHeard[pair.detected].atSec - expectedTimes[pair.expected]) *
                  1000,
            );
            final sweep = sweeps[pair.expected];
            if (!sweep.isClean) continue;
            score.strumFound++;
            final pns = keptHeard[pair.detected].pNoStrum;
            if (pns != null) score.matchedStrumPNoStrum.add(pns);
            final truth = sweep.direction!;
            final h = keptHeard[pair.detected];
            final pDown = h.pDown;
            final pUp = h.pUp;
            if (pDown == null || pUp == null) continue;
            final called = pUp > pDown
                ? StrumDirection.up
                : StrumDirection.down;
            if (called == truth) {
              score.tp[truth] = score.tp[truth]! + 1;
            } else {
              score.fn[truth] = score.fn[truth]! + 1;
              score.fp[called] = score.fp[called]! + 1;
            }
            // The settled direction on the SAME retained stroke. Existence is still the
            // fast tier's call, so this isolates what the second forward buys.
            final sDown = h.sDown;
            final sUp = h.sUp;
            if (sDown == null || sUp == null) {
              score.settledMissing++;
            } else {
              final sCalled = sUp > sDown
                  ? StrumDirection.up
                  : StrumDirection.down;
              if (sCalled == truth) {
                score.stp[truth] = score.stp[truth]! + 1;
              } else {
                score.sfn[truth] = score.sfn[truth]! + 1;
                score.sfp[sCalled] = score.sfp[sCalled]! + 1;
              }
            }
          }
        }
        files++;
      }

      final out = StringBuffer();
      out.writeln();
      out.writeln(
        'GuitarSet comping ${_styles.join('+')} — $files files, '
        '$totalOnsets SuperFlux onsets ($withProbs carrying probabilities, '
        '$coalesced excluded as frame-coalesced)',
      );
      // Provenance, not decoration: every retention number below belongs to THIS asset,
      // and the tree holds two 3-class assets that differ (see [_liveCrnn3c]).
      out.writeln('  asset: $_liveCrnn3c');
      out.writeln(
        '  split: ${Platform.environment['STRUM_SPLIT'] ?? 'all 72 files'}',
      );
      out.writeln();
      out.writeln(
        '  suppress  margin  kept   onsetP  onsetF1  strumRecall  dirDown  '
        'dirUp  dirMacro',
      );
      for (final gate in _gates) {
        final s = scores[gate]!;
        final shipped =
            gate.suppress == LiveCrnnStrumClassifier.noStrumThreshold &&
            gate.margin;
        final label =
            (gate.suppress > 1 ? 'none' : gate.suppress.toStringAsFixed(3)) +
            (shipped ? '*' : '');
        out.writeln(
          '  ${label.padRight(9)} '
          '${(gate.margin ? 'on' : 'off').padRight(6)} '
          '${s.kept.toString().padLeft(5)}  '
          '${s.precision.toStringAsFixed(3).padLeft(6)}  '
          '${s.onsetF1.toStringAsFixed(4).padLeft(7)}  '
          '${s.strumRecall.toStringAsFixed(3).padLeft(11)}  '
          '${s.dirF1(StrumDirection.down).toStringAsFixed(4).padLeft(7)}  '
          '${s.dirF1(StrumDirection.up).toStringAsFixed(4).padLeft(5)}  '
          '${s.dirMacroF1.toStringAsFixed(4).padLeft(8)}',
        );
      }
      out.writeln('  (* = what production does today)');
      out.writeln();
      out.writeln(
        '  IN-SITU SETTLED TIER (ADR 0570): the same retained strokes, direction decided',
      );
      out.writeln(
        '  by the UNTRUNCATED window while the FAST call still decides existence.',
      );
      out.writeln();
      out.writeln(
        '  suppress  margin   dirMacro(fast)  dirMacro(settled)   delta   '
        'down     up      missing',
      );
      for (final gate in _gates) {
        final s = scores[gate]!;
        final label = gate.suppress > 1
            ? 'none'
            : gate.suppress.toStringAsFixed(3);
        out.writeln(
          '  ${label.padRight(9)} '
          '${(gate.margin ? 'on' : 'off').padRight(6)} '
          '${s.dirMacroF1.toStringAsFixed(4).padLeft(14)}  '
          '${s.sDirMacroF1.toStringAsFixed(4).padLeft(17)}  '
          '${(s.sDirMacroF1 - s.dirMacroF1).toStringAsFixed(4).padLeft(7)}  '
          '${s.sDirF1(StrumDirection.down).toStringAsFixed(4)}  '
          '${s.sDirF1(StrumDirection.up).toStringAsFixed(4)}  '
          '${s.settledMissing.toString().padLeft(7)}',
        );
      }
      out.writeln();
      out.writeln(
        '  WHERE THE PHANTOMS FALL (ADR 0566): a false positive within '
        '${onsetToleranceMsPrimary}ms of an annotated',
      );
      out.writeln(
        '  event is a DOUBLE TRIGGER and can take a slot away from the stroke the '
        'learner really',
      );
      out.writeln(
        '  played; one beyond it can only fill a slot they MISSED, or none at all.',
      );
      out.writeln();
      out.writeln(
        '  suppress  margin   phantoms   <=${onsetToleranceMsPrimary}ms   '
        '<=120ms   >120ms   displacing share',
      );
      for (final gate in _gates) {
        final s = scores[gate]!;
        final label = gate.suppress > 1
            ? 'none'
            : gate.suppress.toStringAsFixed(3);
        final share = s.onsetFp == 0 ? 0.0 : s.fpWithinTolerance / s.onsetFp;
        out.writeln(
          '  ${label.padRight(9)} '
          '${(gate.margin ? 'on' : 'off').padRight(6)} '
          '${s.onsetFp.toString().padLeft(9)}  '
          '${s.fpWithinTolerance.toString().padLeft(7)}  '
          '${s.fpWithinMargin.toString().padLeft(7)}  '
          '${s.fpBeyondMargin.toString().padLeft(7)}  '
          '${share.toStringAsFixed(4).padLeft(16)}',
        );
      }
      out.writeln();
      out.writeln(
        '  SIGNED DETECTOR LAG (detected - annotated, ms): positive = reported LATE.',
      );
      out.writeln(
        '  The classification window is built at this instant, and retention collapses',
      );
      out.writeln(
        '  for late windows while early ones cost nothing, so the LATE TAIL is what',
      );
      out.writeln('  decides whether centring explains the in-situ retention.');
      out.writeln();
      out.writeln(
        '  suppress  margin       n      p10     p50     p90   share>+20ms  '
        'share>+30ms',
      );
      for (final gate in _gates) {
        final s = scores[gate]!;
        if (s.lagsMs.isEmpty) continue;
        final sorted = [...s.lagsMs]..sort();
        double q(double f) => sorted[((sorted.length - 1) * f).round()];
        final late20 = s.lagsMs.where((v) => v > 20).length / s.lagsMs.length;
        final late30 = s.lagsMs.where((v) => v > 30).length / s.lagsMs.length;
        final label = gate.suppress > 1
            ? 'none'
            : gate.suppress.toStringAsFixed(3);
        out.writeln(
          '  ${label.padRight(9)} '
          '${(gate.margin ? 'on' : 'off').padRight(6)} '
          '${sorted.length.toString().padLeft(6)}  '
          '${q(0.10).toStringAsFixed(1).padLeft(7)} '
          '${q(0.50).toStringAsFixed(1).padLeft(7)} '
          '${q(0.90).toStringAsFixed(1).padLeft(7)}  '
          '${late20.toStringAsFixed(4).padLeft(11)}  '
          '${late30.toStringAsFixed(4).padLeft(11)}',
        );
      }
      out.writeln();
      out.writeln(
        '  PRODUCTION P(no-strum) ON REAL STRUMS (onsets matched to a clean sweep).',
      );
      out.writeln(
        '  Python over the SAME sweeps, windowed at the annotated onset: median 0.0063,',
      );
      out.writeln(
        '  retention 0.944 / 0.963 / 0.976 at gates 0.439 / 0.650 / 0.850.',
      );
      out.writeln('  Read the `none` row: every onset is present there.');
      out.writeln();
      out.writeln(
        '  suppress  margin       n      p50      p90   retention at .439  .650  .850',
      );
      for (final gate in _gates) {
        final s = scores[gate]!;
        if (s.matchedStrumPNoStrum.isEmpty) continue;
        final sorted = [...s.matchedStrumPNoStrum]..sort();
        double q(double f) => sorted[((sorted.length - 1) * f).round()];
        String keep(double g) =>
            (sorted.where((v) => v <= g).length / sorted.length)
                .toStringAsFixed(3);
        final label = gate.suppress > 1
            ? 'none'
            : gate.suppress.toStringAsFixed(3);
        out.writeln(
          '  ${label.padRight(9)} '
          '${(gate.margin ? 'on' : 'off').padRight(6)} '
          '${sorted.length.toString().padLeft(6)}  '
          '${q(0.50).toStringAsFixed(4).padLeft(7)}  '
          '${q(0.90).toStringAsFixed(4).padLeft(7)}  '
          '${keep(0.439).padLeft(13)} ${keep(0.650)} ${keep(0.850)}',
        );
      }
      // ignore: avoid_print — the table IS this file's deliverable.
      print(out);

      expect(files, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
