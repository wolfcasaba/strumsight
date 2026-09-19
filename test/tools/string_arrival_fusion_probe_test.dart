// Does the chord-informed string-arrival cue BEAT the shipped live CRNN, and
// does fusing the two beat the CRNN alone?
//
// `string_arrival_guitarset_probe_test.dart` measured the cue against
// GuitarSet's hexaphonic truth in isolation (77 % on the 45 % of clean sweeps
// it covers, ~94 % on its high tier). That says nothing about whether it is
// worth wiring in: the thing it would have to improve on is the SHIPPED
// 3-class live CRNN, whose verdict every arrow is drawn from today. This probe
// puts both on the SAME sweeps, from the same mono-mic audio, and scores:
//
//   * the CRNN alone (argmax on P(up), the shipped rule),
//   * the cue alone (with the CRNN standing in where the cue abstains),
//   * four fusion rules that hand the cue authority under different guards.
//
// Sweep extraction, the clean-sweep filter and the EXACT per-string Hz
// derivation are reused verbatim from the hexaphonic probe, so the cue sees
// the same voicings there. The CRNN-hearing half is ported from the E18
// harness `test/tooling/guitarset_direction_boundary_test.dart`: a recorder
// wrapped round `LiveCrnnStrumClassifier` that keeps every raw verdict and
// reports a fixed one, so the analyzer's own suppression never removes a case
// from the pass, plus a ±80 ms nearest-onset pairing to the annotated sweeps.
//
// Auto-skips without the corpus. Run:
//   GUITARSET_DIR=C:/Users/kcsab/Downloads/recipewis \
//   flutter test test/tools/string_arrival_fusion_probe_test.dart
// Optional: STRING_ARRIVAL_LIMIT=<files>, STRING_ARRIVAL_STRIDE=<every n-th>.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/dsp/direction/string_arrival_cue.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/strum_analyzer.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/engine/ml/live_crnn_classifier.dart';

import 'klangio_real_ab_test.dart' show readWav;

const _linkMs = 45.0;
const _styles = ['Rock', 'Funk'];
const _liveCrnn3c = 'assets/ml/strum_crnn_live_3c.bin';

/// Pairing window between an annotated sweep's start and a heard onset.
const _matchToleranceMs = 80.0;

/// Below this |P(up) − P(down)| the CRNN is called undecided (fusion F3).
const _weakMargin = 0.3;

const _docPath = 'docs/eval/string-arrival-fusion-2026-09-15.md';

// ---------------------------------------------------------------------------
// Sweep extraction — verbatim from string_arrival_guitarset_probe_test.dart.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// The CRNN-hearing half — ported from the E18 boundary harness.
// ---------------------------------------------------------------------------

/// Records the model's RAW verdict and reports a fixed confident one, so the
/// analyzer emits exactly one event per classify call and the shipped
/// no-strum suppression removes nothing from the pass. This seam's
/// This seam delegates the settled-tier deadline to the wrapped classifier so
/// the recorded pass matches the shipped one exactly.
final class _Recorder implements StrumDirectionClassifier {
  _Recorder(this._inner);
  final LiveCrnnStrumClassifier _inner;
  final List<StrumClassification> calls = [];

  @override
  int? get settleAfterFrames => _inner.settleAfterFrames;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) =>
      _inner.observe(frame, features);

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) {
    calls.add(
      _inner.classifyAt(onsetFrame: onsetFrame, currentFrame: currentFrame),
    );
    return const StrumClassification(
      direction: StrumDirection.down,
      confidence: 1,
    );
  }
}

/// One onset the live path heard: its time and the CRNN's raw probabilities
/// (`pUp` null = the shipped no-strum gate suppressed it).
typedef _Heard = ({double atSec, double? pUp, double? pNoStrum});

List<_Heard> _heardOnsets(
  Float64List pcm,
  int sampleRate,
  LiveCrnnStrumClassifier crnn,
) {
  final recorder = _Recorder(crnn);
  final analyzer = StrumAnalyzer(sampleRate: sampleRate, classifier: recorder);
  const window = DspConfig.onsetWindow;
  const hop = DspConfig.onsetHop;
  final out = <_Heard>[];
  for (var s = 0; s + window <= pcm.length; s += hop) {
    final event = analyzer.process(Float64List.sublistView(pcm, s, s + window));
    if (event == null) continue;
    final c = recorder.calls.last;
    out.add((atSec: event.timeSec, pUp: c.pUp, pNoStrum: c.pNoStrum));
  }
  return out;
}

/// For every sweep, the index of the nearest untaken heard onset within
/// [_matchToleranceMs] (null = the live path did not hear this sweep).
List<int?> _match(List<double> sweepSec, List<double> heardSec) {
  final taken = <int>{};
  final out = List<int?>.filled(sweepSec.length, null);
  for (var e = 0; e < sweepSec.length; e++) {
    var best = -1;
    var bestGap = double.infinity;
    for (var d = 0; d < heardSec.length; d++) {
      if (taken.contains(d)) continue;
      final gap = (heardSec[d] - sweepSec[e]).abs() * 1000;
      if (gap <= _matchToleranceMs && gap < bestGap) {
        bestGap = gap;
        best = d;
      }
    }
    if (best >= 0) {
      taken.add(best);
      out[e] = best;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Scoring.
// ---------------------------------------------------------------------------

final class _Tally {
  int n = 0;
  int correct = 0;
  void add(bool ok) {
    n++;
    if (ok) correct++;
  }

  String get pct =>
      n == 0 ? 'n/a' : '${(100 * correct / n).toStringAsFixed(1)}%';
  String get cell => n == 0 ? 'n/a' : '$pct ($correct/$n)';
}

final class _Variant {
  _Variant(this.name, this.decide);
  final String name;

  /// (cue verdict, CRNN direction, CRNN margin) → the fused direction.
  final StrumDirection Function(
    StringArrivalResult cue,
    StrumDirection crnn,
    double margin,
  )
  decide;

  final overall = _Tally();
  final byDir = {StrumDirection.down: _Tally(), StrumDirection.up: _Tally()};
  final byGroup = {'00-02': _Tally(), '03-05': _Tally()};
  final highTier = _Tally();
}

void main() {
  final root =
      Platform.environment['GUITARSET_DIR'] ??
      'C:/Users/kcsab/Downloads/recipewis';
  final audioDir = Directory('$root/audio_mono-mic');
  final annDir = Directory('$root/annotation');
  final present = audioDir.existsSync() && annDir.existsSync();

  test(
    'string-arrival cue vs the shipped live CRNN, and their fusion',
    () {
      expect(File(_liveCrnn3c).existsSync(), isTrue);
      final env = Platform.environment;
      final limit = int.tryParse(env['STRING_ARRIVAL_LIMIT'] ?? '');
      final stride = int.tryParse(env['STRING_ARRIVAL_STRIDE'] ?? '') ?? 1;

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
      if (stride > 1) {
        wavs = [for (var i = 0; i < wavs.length; i += stride) wavs[i]];
      }
      if (limit != null) wavs = wavs.take(limit).toList();
      expect(wavs, isNotEmpty);

      final variants = <_Variant>[
        // The shipped rule, as the baseline every other row must beat.
        _Variant('CRNN alone (shipped)', (cue, crnn, margin) => crnn),
        // The cue wherever it has any opinion at all — identical to F4, kept
        // as its own row because "the cue, with the CRNN as its fallback" is
        // the question, and F4 is its answer.
        _Variant(
          'cue alone (CRNN on abstain)',
          (cue, crnn, margin) => cue.direction ?? crnn,
        ),
        _Variant(
          'F1  cue if conf >= 0.80',
          (cue, crnn, margin) =>
              (cue.direction != null && cue.confidence >= 0.8)
              ? cue.direction!
              : crnn,
        ),
        _Variant(
          'F2  cue if conf >= 0.65',
          (cue, crnn, margin) =>
              (cue.direction != null && cue.confidence >= 0.65)
              ? cue.direction!
              : crnn,
        ),
        _Variant(
          'F3  conf >= 0.80, or any cue when CRNN margin < 0.30',
          (cue, crnn, margin) =>
              (cue.direction != null &&
                  (cue.confidence >= 0.8 || margin < _weakMargin))
              ? cue.direction!
              : crnn,
        ),
        _Variant(
          'F4  cue whenever it is not ambiguous',
          (cue, crnn, margin) => cue.direction ?? crnn,
        ),
      ];

      var cleanSweeps = 0, crnnMissed = 0, crnnSuppressed = 0, scored = 0;
      var cueCovered = 0, cueCorrectOnCovered = 0;
      final tierN = <String, int>{}, tierCorrect = <String, int>{};
      final truthDown = <StrumDirection, int>{
        StrumDirection.down: 0,
        StrumDirection.up: 0,
      };
      final sw = Stopwatch()..start();

      for (final wav in wavs) {
        final name = wav.uri.pathSegments.last;
        final player = name.split('_').first;
        final group = int.parse(player) <= 2 ? '00-02' : '03-05';
        final stem = name.substring(0, name.length - '_mic.wav'.length);
        final jamsFile = File('${annDir.path}/$stem.jams');
        if (!jamsFile.existsSync()) continue;
        final jams =
            jsonDecode(jamsFile.readAsStringSync()) as Map<String, dynamic>;
        final (raw, sr) = readWav(wav.path);
        // One second of tail silence so the analyzer's pending onsets all
        // reach their evidence window (E18 harness does the same).
        final pcm = Float64List(raw.length + sr)..setRange(0, raw.length, raw);

        // The classifier is built PER FILE: its frontend is stateful and each
        // file restarts the analyzer's frame counter (LESSONS L663).
        final crnn = LiveCrnnStrumClassifier.tryLoad(
          _liveCrnn3c,
          sampleRate: sr,
        );
        expect(crnn, isNotNull);
        final heard = _heardOnsets(pcm, sr, crnn!);
        final cue = StringArrivalCue(sampleRate: sr);

        final sweeps = _sweeps(jams);
        final pairs = _match(
          [for (final s in sweeps) s.atSec],
          [for (final h in heard) h.atSec],
        );

        for (var i = 0; i < sweeps.length; i++) {
          final s = sweeps[i];
          if (!s.isClean) continue;
          cleanSweeps++;
          final truth = s.direction!;
          truthDown[truth] = truthDown[truth]! + 1;

          final m = pairs[i];
          if (m == null) {
            crnnMissed++;
            continue;
          }
          final pUp = heard[m].pUp;
          if (pUp == null) {
            // Onset detected but the shipped no-strum gate suppressed it: the
            // live path draws no arrow, so there is no CRNN verdict to score.
            crnnSuppressed++;
            crnnMissed++;
            continue;
          }
          scored++;

          final crnnDir = pUp > 0.5 ? StrumDirection.up : StrumDirection.down;
          final margin = (pUp - (1 - pUp)).abs();

          final hz = List<double?>.filled(6, null);
          for (final n in s.notes) {
            hz[n.string] = 440 * math.pow(2, (n.midi - 69) / 12).toDouble();
          }
          final r = cue.analyze(pcm, (s.atSec * sr).round(), hz);

          final tier = r.direction == null
              ? 'abstain'
              : r.confidence >= 0.8
              ? 'high'
              : r.confidence >= 0.65
              ? 'mid'
              : 'low';
          tierN[tier] = (tierN[tier] ?? 0) + 1;
          if (r.direction == truth) {
            tierCorrect[tier] = (tierCorrect[tier] ?? 0) + 1;
          }
          if (r.direction != null) {
            cueCovered++;
            if (r.direction == truth) cueCorrectOnCovered++;
          }

          final isHigh = r.direction != null && r.confidence >= 0.8;
          for (final v in variants) {
            final called = v.decide(r, crnnDir, margin);
            final ok = called == truth;
            v.overall.add(ok);
            v.byDir[truth]!.add(ok);
            v.byGroup[group]!.add(ok);
            if (isHigh) v.highTier.add(ok);
          }
        }
      }

      sw.stop();
      expect(scored, greaterThan(0));

      final cmd =
          'GUITARSET_DIR=$root'
          '${limit != null ? ' STRING_ARRIVAL_LIMIT=$limit' : ''}'
          '${stride > 1 ? ' STRING_ARRIVAL_STRIDE=$stride' : ''}'
          ' flutter test test/tools/string_arrival_fusion_probe_test.dart';

      String pc(int a, int b) =>
          b == 0 ? 'n/a' : '${(100 * a / b).toStringAsFixed(1)}%';

      final md = StringBuffer()
        ..writeln('# String-arrival cue vs the shipped live CRNN — 2026-09-15')
        ..writeln()
        ..writeln('Command:')
        ..writeln()
        ..writeln('```')
        ..writeln(cmd)
        ..writeln('```')
        ..writeln()
        ..writeln(
          '- corpus: GuitarSet ${_styles.join('+')} comping, `_comp_mic.wav`, '
          '**${wavs.length} files**'
          '${stride > 1 ? ' (deterministic every ${stride}th file)' : ''}',
        )
        ..writeln('- clean sweeps (hexaphonic truth): **$cleanSweeps**')
        ..writeln(
          '- of those, the live path did NOT hear: **$crnnMissed** '
          '(${pc(crnnMissed, cleanSweeps)}) — '
          '$crnnSuppressed of them heard as an onset but suppressed by the '
          'shipped no-strum gate (P(no-strum) > '
          '${LiveCrnnStrumClassifier.noStrumThreshold}), '
          '${crnnMissed - crnnSuppressed} with no onset within '
          '±${_matchToleranceMs.toStringAsFixed(0)} ms at all',
        )
        ..writeln(
          '- **scored sweeps (CRNN heard): $scored** — every table below is '
          'over exactly these',
        )
        ..writeln(
          '- truth prior — all clean sweeps: '
          '${pc(truthDown[StrumDirection.down]!, cleanSweeps)} down '
          '(down ${truthDown[StrumDirection.down]}, '
          'up ${truthDown[StrumDirection.up]}); scored sweeps: '
          '${pc(variants.first.byDir[StrumDirection.down]!.n, scored)} down '
          '(down ${variants.first.byDir[StrumDirection.down]!.n}, '
          'up ${variants.first.byDir[StrumDirection.up]!.n}) — the shipped '
          'no-strum gate drops UP-strokes far harder than down-strokes',
        )
        ..writeln('- runtime: ${sw.elapsed.inSeconds}s')
        ..writeln()
        ..writeln('## Accuracy over the $scored sweeps the CRNN heard')
        ..writeln()
        ..writeln(
          '| rule | accuracy | down | up | players 00-02 | players 03-05 | '
          'on cue high tier |',
        )
        ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
      for (final v in variants) {
        md.writeln(
          '| ${v.name} | ${v.overall.cell} | '
          '${v.byDir[StrumDirection.down]!.cell} | '
          '${v.byDir[StrumDirection.up]!.cell} | '
          '${v.byGroup['00-02']!.cell} | ${v.byGroup['03-05']!.cell} | '
          '${v.highTier.cell} |',
        );
      }
      md
        ..writeln()
        ..writeln('## The cue on its own, over the same $scored sweeps')
        ..writeln()
        ..writeln(
          '- coverage (cue not ambiguous): $cueCovered / $scored = '
          '${pc(cueCovered, scored)}',
        )
        ..writeln(
          '- accuracy on covered: '
          '${pc(cueCorrectOnCovered, cueCovered)} '
          '($cueCorrectOnCovered/$cueCovered)',
        )
        ..writeln()
        ..writeln('| cue tier | n | cue accuracy | CRNN accuracy on the same |')
        ..writeln('| --- | --- | --- | --- |');
      final crnnVariant = variants.first;
      for (final tier in ['high', 'mid', 'low', 'abstain']) {
        final n = tierN[tier] ?? 0;
        if (n == 0) continue;
        final c = tierCorrect[tier] ?? 0;
        md.writeln(
          '| $tier | $n | ${tier == 'abstain' ? 'n/a' : pc(c, n)} | '
          '${tier == 'high' ? crnnVariant.highTier.cell : '—'} |',
        );
      }
      md
        ..writeln()
        ..writeln(
          'The `on cue high tier` column of the first table is the CRNN\'s own '
          'accuracy on exactly the sweeps where the cue is confident — the '
          'comparison that decides whether handing those sweeps to the cue is '
          'an improvement or a regression.',
        );

      // ignore: avoid_print — the table IS this file's deliverable.
      print('\n$md');
      File(_docPath).writeAsStringSync(md.toString());
    },
    skip: present ? false : 'GuitarSet absent (set GUITARSET_DIR)',
    timeout: const Timeout(Duration(minutes: 60)),
  );
}
