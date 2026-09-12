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
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/core/music/onset_matching.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
import 'package:strumsight/features/live/domain/recognition/strum_prediction.dart';
import 'package:strumsight/features/live/engine/ml/live_crnn_classifier.dart';

const double _linkMs = 45;
const List<String> _styles = ['Rock', 'Funk'];
const String _liveCrnn3c = 'assets/ml/strum_crnn_live_3c.bin';
const int _sampleRate = 44100;

/// The gates to compare. The first is what ships; 1.01 never suppresses, which is the
/// composition the baseline measurement pointed at — the CRNN judging direction on
/// every SuperFlux onset instead of only the ones it keeps.
typedef _Gate = ({double suppress, bool margin});

/// Every combination worth asking about. `suppress: 1.01` never suppresses;
/// `margin: false` skips the pipeline's confirmation gate. The first row is what
/// production does today.
const List<_Gate> _gates = [
  (suppress: LiveCrnnStrumClassifier.noStrumThreshold, margin: true),
  (suppress: LiveCrnnStrumClassifier.noStrumThreshold, margin: false),
  (suppress: 0.65, margin: true),
  (suppress: 0.65, margin: false),
  (suppress: 0.85, margin: true),
  (suppress: 0.85, margin: false),
  (suppress: 1.01, margin: true),
  (suppress: 1.01, margin: false),
];

/// Delegates to the REAL classifier, records what it said, and never suppresses.
///
/// Never suppressing is not a proposed behaviour — it is how one pass can stand in for
/// every pass: the recorded `pNoStrum` lets each gate be applied afterwards.
final class _RecordingClassifier implements StrumDirectionClassifier {
  _RecordingClassifier(this._inner);

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
    // BOTH gates are lifted here, and the second by OMISSION rather than a flag:
    // `live_pipeline._isDirectionConfirmed` returns true unconditionally for an
    // event carrying no probabilities, so reporting a direction WITHOUT pDown/pUp
    // makes the pipeline publish every onset. The real probabilities are not lost —
    // they are in `calls`, which is where each candidate gate is applied offline.
    // Nothing here proposes a production behaviour; it is how one pass can carry
    // every gate.
    final up = (result.pUp ?? 0) > (result.pDown ?? 0);
    return StrumClassification(
      direction: up ? StrumDirection.up : StrumDirection.down,
      confidence: 1,
    );
  }
}

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

/// One onset the pipeline produced, with the model's raw verdict attached.
typedef _Heard = ({double atSec, double? pDown, double? pUp, double? pNoStrum});

/// Would the pipeline's margin gate confirm this onset?
///
/// Built from the SAME `StrumPrediction.decision` the pipeline defers to, so the
/// sweep cannot drift from the shipped rule by restating it.
bool _marginConfirms(_Heard h) {
  final pDown = h.pDown;
  final pUp = h.pUp;
  if (pDown == null || pUp == null) return true;
  return StrumPrediction(
        onsetTimeSec: h.atSec,
        verdictTimeSec: h.atSec,
        pDown: pDown,
        pUp: pUp,
        pNoStrum: h.pNoStrum ?? 0,
        calibratedConfidence: null,
        modelId: 'sweep',
      ).decision ==
      RecognitionDecision.confirmed;
}

List<_Heard> _heardWithProbs(
  List<double> pcm,
  LiveCrnnStrumClassifier crnn, {
  int chunk = 1024,
}) {
  final recorder = _RecordingClassifier(crnn);
  final pipeline = LivePipeline.debugWithClassifier(
    recorder,
    sampleRate: _sampleRate,
  );
  // `LiveFrame` carries direction and confidence but NOT the raw probabilities, so
  // the times come from the frames and the probabilities from the recorder, zipped by
  // order. That zip is an assumption — one classification, one published strum — and
  // it is CHECKED rather than trusted: a pipeline-side guard that dropped an event
  // would silently shift every probability onto the wrong onset, which is exactly the
  // class of error this corpus has already caught twice.
  // A SILENT TAIL, and it is load-bearing rather than tidy. Without it the run
  // reported 172 published strums for 173 classifications: the analyzer classifies an
  // onset only after `_classifyAfterFrames` of post-onset evidence, so the final
  // onset's verdict arrives after the audio has run out and never reaches a published
  // frame. One second of zeros lets it through, which turns the zip below from an
  // assumption into an identity — and the strict check stays, so if the discrepancy
  // ever becomes something OTHER than an end effect the measurement stops instead of
  // silently pairing probabilities with the wrong onsets.
  final padded = [...pcm, ...List<double>.filled(_sampleRate, 0)];
  // FRAME COALESCING, measured the hard way. `LiveFrame` is emitted on a sample clock
  // at about 15 Hz and carries only the LATEST strum, while `strumSeq` counts them all.
  // Two strums inside one ~66 ms emission window therefore advance the sequence by two
  // and surface ONE time — the earlier one is unobservable from the frame stream. This
  // showed up as 173 classifications against 172 published strums, and it survived both
  // lifting the suppression gate and padding with silence, which is what ruled out
  // every other explanation.
  //
  // So a jump of k is handled honestly rather than papered over: the frame's time
  // belongs to the LAST of the k, and the preceding k-1 have no recoverable time and
  // are excluded from scoring. The count is reported, because an exclusion nobody sees
  // is just a quieter error. (`test/support/modelled_guitar.dart`'s `strumOnsets` has
  // the same loop and the same blind spot — harmless where its strums are hundreds of
  // ms apart, but it is the same shape.)
  final times = <double?>[];
  var lastSeq = 0;
  for (var i = 0; i < padded.length; i += chunk) {
    final end = math.min(i + chunk, padded.length);
    for (final frame in pipeline.addChunk(padded.sublist(i, end))) {
      if (frame.strumSeq > lastSeq) {
        final jumped = frame.strumSeq - lastSeq;
        lastSeq = frame.strumSeq;
        for (var k = 1; k < jumped; k++) {
          times.add(null); // coalesced away: no recoverable time
        }
        times.add(frame.latestStrumTime);
      }
    }
  }
  expect(
    times.length,
    recorder.calls.length,
    reason:
        'the pipeline accounted for ${times.length} strums against '
        '${recorder.calls.length} classifications. With coalescing handled, these '
        'must agree — a remaining gap means something ELSE drops events and the '
        'probabilities can no longer be zipped onto the onsets by order',
  );
  coalesced += times.where((t) => t == null).length;
  return [
    for (var i = 0; i < times.length; i++)
      if (times[i] != null)
        (
          atSec: times[i]!,
          pDown: recorder.calls[i].pDown,
          pUp: recorder.calls[i].pUp,
          pNoStrum: recorder.calls[i].pNoStrum,
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

/// Tallies for one candidate gate.
final class _GateScore {
  int kept = 0;
  int onsetTp = 0;
  int onsetFp = 0;
  int onsetFn = 0;
  int strumFound = 0;
  int strumTotal = 0;
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

  double get onsetF1 => _f1(onsetTp, onsetFp, onsetFn);
  double get precision => onsetTp == 0 ? 0 : onsetTp / (onsetTp + onsetFp);
  double get strumRecall => strumTotal == 0 ? 0 : strumFound / strumTotal;
  double dirF1(StrumDirection d) => _f1(tp[d]!, fp[d]!, fn[d]!);
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
      var files = 0;
      var totalOnsets = 0;
      var withProbs = 0;

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
        final heard = _heardWithProbs(decoded.$1, crnn!);
        totalOnsets += heard.length;
        withProbs += heard.where((h) => h.pNoStrum != null).length;

        for (final gate in _gates) {
          final score = scores[gate]!;
          // Apply the candidate gate to the SAME recorded onsets.
          final keptHeard = [
            for (final h in heard)
              if ((h.pNoStrum ?? 0) <= gate.suppress &&
                  (!gate.margin || _marginConfirms(h)))
                h,
          ];
          score.kept += keptHeard.length;
          final pairs = _match(expectedTimes, [
            for (final h in keptHeard) h.atSec,
          ]);
          score.onsetTp += pairs.length;
          score.onsetFp += keptHeard.length - pairs.length;
          score.onsetFn += expectedTimes.length - pairs.length;
          score.strumTotal += sweeps.where((s) => s.isClean).length;
          for (final pair in pairs) {
            final sweep = sweeps[pair.expected];
            if (!sweep.isClean) continue;
            score.strumFound++;
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
      // ignore: avoid_print — the table IS this file's deliverable.
      print(out);

      expect(files, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
