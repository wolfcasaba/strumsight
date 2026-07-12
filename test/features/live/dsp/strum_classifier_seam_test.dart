import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:music_theory/features/live/model/strum.dart';

import '../../../support/synth.dart';

/// Round 139 (ml-track P1.1): the ↓/↑ decision sits behind the
/// [StrumDirectionClassifier] seam, so the TFLite CRNN can drop in without
/// touching the analyzer. This pins the seam's calling contract.
class _RecordingClassifier implements StrumDirectionClassifier {
  int observeCalls = 0;
  final List<(int onset, int current)> classifyCalls = [];

  @override
  void observe(Float64List frame, StrumFrameFeatures features) {
    observeCalls++;
  }

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) {
    classifyCalls.add((onsetFrame, currentFrame));
    return const StrumClassification(
        direction: StrumDirection.up, confidence: 0.9);
  }
}

void main() {
  const sr = DspConfig.defaultSampleRate;

  test('the analyzer observes every hop and classifies 12 frames post-onset',
      () {
    final fake = _RecordingClassifier();
    final analyzer = StrumAnalyzer(sampleRate: sr, classifier: fake);
    final signal = strumSignal(lowFirst: true);
    final events = <StrumEvent>[];
    var fed = 0;
    for (final frame in frames(signal, analyzer.window, analyzer.hop)) {
      final e = analyzer.process(frame);
      if (e != null) events.add(e);
      fed++;
    }

    expect(fake.observeCalls, fed,
        reason: 'every hop must reach the classifier (streaming CRNN state)');
    expect(fake.classifyCalls, hasLength(1));
    final (onset, current) = fake.classifyCalls.single;
    expect(current - onset, 12,
        reason: 'the evidence-window policy stays in the analyzer');

    // The injected verdict flows through to the event verbatim; the reported
    // time is the peak frame + the r144 attack offset (+2.5 hops).
    expect(events.single.direction, StrumDirection.up);
    expect(events.single.confidence, 0.9);
    expect(events.single.timeSec,
        closeTo((onset + 2.5) * analyzer.hop / sr, 1e-9));
  });
}
