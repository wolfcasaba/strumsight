// A/B scoreboard: heuristic vs CRNN strum-direction on the adversarial synth
// suite (ml-track P1.4). NOT a which-is-better gate — the CRNN is trained on
// REAL phone-mic guitar and the synth suite is out of its domain. MEASURED
// 2026-07-13 (seed 42): heuristic 24/24 on synth, CRNN 9/24 — the model is
// systematically wrong on the synthetic stagger cue while scoring 0.867 on
// real phone-mic eval (the r163 fixture gate). Conclusion recorded in chunk
// 018: the synth suite CANNOT arbitrate heuristic-vs-model; the real-domain
// accuracy gate lives in crnn_strum_net_test.dart, and deployment decisions
// need the real-recording A/B (r164). This test therefore gates only that
// (a) the whole Dart inference chain runs end-to-end on raw audio and
// (b) the heuristic keeps its own r59 floor; accuracies are PRINTED every
// run so drift stays visible. Randomized per the HORIZON property pattern.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/engine/ml/strum_crnn.dart';
import 'package:music_theory/features/live/model/strum.dart';

import '../support/synth.dart';

const sr = DspConfig.defaultSampleRate;

Iterable<Float64List> _frames(Float64List signal, int window, int hop) sync* {
  for (var start = 0; start + window <= signal.length; start += hop) {
    yield Float64List.sublistView(signal, start, start + window);
  }
}

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final rng = math.Random(seed);

  test('A/B: heuristic vs CRNN direction on randomized synth strums (24)',
      () {
    final crnn = StrumCrnn.tryLoad('assets/ml/strum_crnn.bin');
    expect(crnn, isNotNull,
        reason: 'assets/ml/strum_crnn.bin must ship with the repo');

    var heurChecked = 0, heurCorrect = 0;
    var crnnChecked = 0, crnnCorrect = 0;
    const onsetSec = 0.15; // strum start inside each trial clip
    for (var t = 0; t < 24; t++) {
      final lowFirst = rng.nextBool();
      final stagger = 6 + rng.nextDouble() * 8; // 6–14 ms per string
      final clip = Float64List((sr * (0.6 + rng.nextDouble() * 0.3)).round());
      final strum = strumSignal(
        lowFirst: lowFirst,
        staggerMs: stagger,
        seconds: clip.length / sr - onsetSec,
      );
      final at = (onsetSec * sr).round();
      for (var i = 0; i < strum.length && at + i < clip.length; i++) {
        clip[at + i] = strum[i];
      }
      final want = lowFirst ? StrumDirection.down : StrumDirection.up;

      // Heuristic side: the full analyzer (onset detection included).
      final analyzer = StrumAnalyzer(sampleRate: sr);
      StrumEvent? event;
      for (final frame
          in _frames(clip, DspConfig.onsetWindow, DspConfig.onsetHop)) {
        event ??= analyzer.process(frame);
      }
      if (event?.direction != null) {
        heurChecked++;
        if (event!.direction == want) heurCorrect++;
      }

      // CRNN side: the exact deployment chain — resample → log-mel →
      // window at the onset → forward.
      final c = crnn!.classifyClip(clip, sr, const [onsetSec]).single;
      if (c.direction != null) {
        crnnChecked++;
        if (c.direction == want) crnnCorrect++;
      }
    }

    final heurAcc = heurCorrect / math.max(1, heurChecked);
    final crnnAcc = crnnCorrect / math.max(1, crnnChecked);
    // The scoreboard — printed every run so drift is visible in CI logs.
    // ignore: avoid_print
    print('A/B seed=$seed heuristic=$heurCorrect/$heurChecked '
        '(${(heurAcc * 100).toStringAsFixed(0)}%) '
        'crnn=$crnnCorrect/$crnnChecked '
        '(${(crnnAcc * 100).toStringAsFixed(0)}%)');

    expect(heurChecked, greaterThanOrEqualTo(18),
        reason: 'seed=$seed: synth strums should rarely be ambiguous');
    expect(crnnChecked, 24, reason: 'the CRNN always answers');
    expect(heurAcc, greaterThanOrEqualTo(0.85),
        reason: 'seed=$seed: heuristic floor (r59 property)');
    // No CRNN accuracy gate here — synth is off-domain for the model
    // (see header); crnnAcc is scoreboard-only. The unused variable would
    // otherwise lint:
    expect(crnnAcc, inInclusiveRange(0.0, 1.0));
  });

  test('tryLoad returns null when the weights asset is missing (fallback)',
      () {
    expect(StrumCrnn.tryLoad('assets/ml/nope.bin'), isNull);
  });
}
