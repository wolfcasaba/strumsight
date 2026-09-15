// The shape-informed ↓/↑ cue is ARMED in the pipeline only while the expected
// chord is set AND the decoder shows that same chord; otherwise the wrapper
// is a pass-through (voicing null).
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/ml/live_crnn_classifier.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';

import '../../../support/synth.dart';

void main() {
  const sr = 44100;

  LivePipeline feed(List<double> signal, {String? expected}) {
    final p = LivePipeline(sampleRate: sr)..setExpectedChord(expected);
    for (var i = 0; i < signal.length; i += 1024) {
      final end = i + 1024 < signal.length ? i + 1024 : signal.length;
      p.addChunk(signal.sublist(i, end));
    }
    return p;
  }

  test('debugStrumClassifier still exposes the INNER classifier', () {
    final p = LivePipeline(sampleRate: sr);
    expect(p.debugStrumClassifier, isNot(same(p.debugShapeClassifier)));
    expect(
      p.debugStrumClassifier,
      anyOf(isA<HeuristicStrumClassifier>(), isA<LiveCrnnStrumClassifier>()),
    );
  });

  test('no expected chord → voicing stays null', () {
    final p = feed(chordSignal(cMajorFreqs, seconds: 1.5));
    expect(p.debugShapeClassifier.voicingHz, isNull);
  });

  test('expected chord shown by the decoder → voicing armed', () {
    final p = feed(chordSignal(cMajorFreqs, seconds: 1.5), expected: 'C');
    expect(p.debugShapeClassifier.voicingHz, isNotNull);
    expect(p.debugShapeClassifier.voicingHz!.where((h) => h != null).length, 5);
  });

  test('expected chord NOT shown (silence) → voicing stays null', () {
    final p = feed(List<double>.filled(sr, 0.0), expected: 'C');
    expect(p.debugShapeClassifier.voicingHz, isNull);
  });

  test('unknown shape label → voicing stays null', () {
    final p = feed(chordSignal(cMajorFreqs, seconds: 1.5), expected: 'Xyz');
    expect(p.debugShapeClassifier.voicingHz, isNull);
  });
}
