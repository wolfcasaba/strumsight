import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:music_theory/features/live/model/strum.dart';

import '../../../support/synth.dart';

/// r175 — a suppressed classification (the learned no-strum reject fired) must
/// stop the strum reaching ANY consumer: no [StrumEvent] is emitted, so the
/// Live arrow, Learn scoring and the streak all see nothing. The seam is still
/// consulted on every onset — suppression is a decision, not a bypass.
class _SuppressingClassifier implements StrumDirectionClassifier {
  int classifyCalls = 0;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) {}

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) {
    classifyCalls++;
    return const StrumClassification(
        direction: null, confidence: 0, suppressed: true);
  }
}

class _DownClassifier implements StrumDirectionClassifier {
  @override
  void observe(Float64List frame, StrumFrameFeatures features) {}

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) =>
      const StrumClassification(
          direction: StrumDirection.down, confidence: 0.9);
}

void main() {
  const sr = DspConfig.defaultSampleRate;

  test('a suppressed classification emits NO StrumEvent (no arrow/Learn hit)',
      () {
    final fake = _SuppressingClassifier();
    final analyzer = StrumAnalyzer(sampleRate: sr, classifier: fake);
    final signal = strumSignal(lowFirst: true);
    final events = <StrumEvent>[];
    for (final frame in frames(signal, analyzer.window, analyzer.hop)) {
      final e = analyzer.process(frame);
      if (e != null) events.add(e);
    }
    expect(fake.classifyCalls, 1,
        reason: 'the onset was detected and the seam consulted');
    expect(events, isEmpty,
        reason: 'suppression stops the strum reaching every consumer');
  });

  test('a non-suppressed classification still emits the strum', () {
    final analyzer =
        StrumAnalyzer(sampleRate: sr, classifier: _DownClassifier());
    final signal = strumSignal(lowFirst: true);
    final events = <StrumEvent>[];
    for (final frame in frames(signal, analyzer.window, analyzer.hop)) {
      final e = analyzer.process(frame);
      if (e != null) events.add(e);
    }
    expect(events, hasLength(1));
    expect(events.single.direction, StrumDirection.down);
    expect(events.single.confidence, 0.9);
  });
}
