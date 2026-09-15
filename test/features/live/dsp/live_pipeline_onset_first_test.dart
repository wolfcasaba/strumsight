// Onset-first feedback: the pipeline publishes an onset the frame it is
// confirmed (onsetSeq + latestOnsetTime), ~70 ms BEFORE the direction verdict
// (strumSeq), and emits a frame IMMEDIATELY on both — never waiting out the
// 66 ms cadence.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

import '../../../support/synth.dart';

void main() {
  const sr = 44100;

  /// Feed [signal] in [chunk]-sample pieces; returns (frame, feed position in
  /// seconds when it was emitted) pairs.
  List<(LiveFrame, double)> run(List<double> signal, {int chunk = 512}) {
    final pipeline = LivePipeline(sampleRate: sr);
    final out = <(LiveFrame, double)>[];
    for (var i = 0; i < signal.length; i += chunk) {
      final end = i + chunk < signal.length ? i + chunk : signal.length;
      for (final f in pipeline.addChunk(signal.sublist(i, end))) {
        out.add((f, end / sr));
      }
    }
    return out;
  }

  test('onsetSeq bumps before strumSeq, and the frame is emitted at once', () {
    final frames = run(
      strumSignal(lowFirst: true, seconds: 0.8, leadSilenceSeconds: 0.3),
    );
    final onsetIdx = frames.indexWhere((p) => p.$1.onsetSeq == 1);
    final strumIdx = frames.indexWhere((p) => p.$1.strumSeq == 1);
    expect(onsetIdx, greaterThanOrEqualTo(0), reason: 'onset never published');
    expect(strumIdx, greaterThan(onsetIdx), reason: 'direction must follow');
    final (onsetFrame, fedAt) = frames[onsetIdx];
    expect(onsetFrame.strumSeq, 0);
    expect(onsetFrame.latestStrumTime, -1);
    // The attack estimate lands near the true attack (0.3 s lead silence).
    expect(onsetFrame.latestOnsetTime, closeTo(0.3, 0.03));
    // Immediate emission: the frame leaves with the chunk that confirmed the
    // onset — within one chunk + the detector's 2-hop lag of the attack.
    expect(fedAt - onsetFrame.latestOnsetTime, lessThan(0.06));
    // The direction verdict arrives ~70 ms of audio later, not a cadence tick
    // later than that.
    final (strumFrame, strumFedAt) = frames[strumIdx];
    expect(
      strumFrame.latestOnsetTime,
      closeTo(onsetFrame.latestOnsetTime, 1e-9),
    );
    expect(strumFedAt - onsetFrame.latestOnsetTime, lessThan(0.13));
    expect(
      strumFrame.latestStrumTime,
      closeTo(strumFrame.latestOnsetTime, 1e-9),
    );
  });

  test('silence publishes no onset and keeps the idle cadence', () {
    final frames = run(List<double>.filled(sr, 0.0));
    expect(frames.every((p) => p.$1.onsetSeq == 0), true);
    // ~15 Hz cadence over 1 s of audio.
    expect(frames.length, inInclusiveRange(13, 17));
  });
}
