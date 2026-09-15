import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/dsp/direction/shape_informed_strum_classifier.dart';
import 'package:strumsight/features/live/engine/dsp/direction/string_arrival_cue.dart';
import 'package:strumsight/features/live/engine/dsp/strum_analyzer.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';

import '../../../support/synth.dart';

/// An inner classifier that always answers UP with CRNN-style probabilities
/// (or suppresses), so the wrapper's decision is unambiguous.
class _FixedInner implements StrumDirectionClassifier {
  _FixedInner({this.suppress = false});
  final bool suppress;
  int observed = 0;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) => observed++;

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) => StrumClassification(
    direction: suppress ? null : StrumDirection.up,
    confidence: 0.7,
    suppressed: suppress,
    pDown: 0.2,
    pUp: 0.8,
  );
}

void main() {
  const sr = 44100;
  final open = StringArrivalCue.voicingHz([0, 0, 0, 0, 0, 0]);

  StrumEvent? run(ShapeInformedStrumClassifier c) {
    final analyzer = StrumAnalyzer(sampleRate: sr, classifier: c);
    final pcm = strumSignal(lowFirst: true, staggerMs: 8, seconds: 0.6);
    StrumEvent? event;
    for (var i = 0; i + 1024 <= pcm.length; i += 256) {
      event ??= analyzer.process(Float64List.sublistView(pcm, i, i + 1024));
    }
    return event;
  }

  test('without a voicing it is a transparent pass-through', () {
    final inner = _FixedInner();
    final c = ShapeInformedStrumClassifier(inner: inner, sampleRate: sr);
    final e = run(c)!;
    expect(e.direction, StrumDirection.up);
    expect(e.pUp, 0.8);
    expect(c.lastVerdictSource, 'inner');
    expect(inner.observed, greaterThan(0));
  });

  test('with the played voicing the cue overrides a wrong inner verdict', () {
    final c = ShapeInformedStrumClassifier(inner: _FixedInner(), sampleRate: sr)
      ..setVoicing(open);
    final e = run(c)!;
    expect(e.direction, StrumDirection.down);
    expect(e.pUp, isNull, reason: 'a cue verdict carries no CRNN probability');
    expect(e.confidence, greaterThanOrEqualTo(0.65));
    expect(c.lastVerdictSource, 'cue');
  });

  test('an inner no-strum suppression is always honoured', () {
    final c = ShapeInformedStrumClassifier(
      inner: _FixedInner(suppress: true),
      sampleRate: sr,
    )..setVoicing(open);
    expect(run(c), isNull);
    expect(c.lastVerdictSource, 'inner');
  });
}
