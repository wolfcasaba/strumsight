import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/dsp_config.dart';
import 'package:music_theory/features/live/engine/dsp/strum_analyzer.dart';
import 'package:music_theory/features/live/engine/dsp/tempo_tracker.dart';
import 'package:music_theory/features/live/model/strum.dart';

import '../../../support/synth.dart';

const sr = DspConfig.defaultSampleRate;
const win = DspConfig.onsetWindow;
const hop = DspConfig.onsetHop;

List<StrumEvent> analyze(Float64List signal) {
  final analyzer = StrumAnalyzer(sampleRate: sr);
  final events = <StrumEvent>[];
  for (final frame in frames(signal, win, hop)) {
    final e = analyzer.process(frame);
    if (e != null) events.add(e);
  }
  return events;
}

void main() {
  test('a single staggered strum produces exactly one onset', () {
    final events = analyze(strumSignal(lowFirst: true));
    expect(events.length, 1,
        reason: '6 string hits over ~40 ms must merge into ONE strum');
  });

  test('silence produces no events', () {
    expect(analyze(Float64List(sr)), isEmpty);
  });

  test('down-strum (low strings first) classified as down', () {
    final events = analyze(strumSignal(lowFirst: true));
    expect(events.single.direction, StrumDirection.down);
    expect(events.single.confidence, greaterThan(0.45));
  });

  test('up-strum (high strings first) classified as up', () {
    final events = analyze(strumSignal(lowFirst: false));
    expect(events.single.direction, StrumDirection.up);
    expect(events.single.confidence, greaterThan(0.45));
  });

  test('fast overlapping strums keep correct direction (ring-out isolation)',
      () {
    // 8th notes at 120 BPM (250 ms apart) each ringing 0.5 s → every strum
    // lands while the previous is still sounding. Before round 59 the absolute
    // sub-band cue read the ring-out and the direction call collapsed; the
    // onset-relative baseline must isolate each strum's own attack.
    final dirs = [true, false, true, false, true, false];
    final events = analyze(overlappingStrums(
      lowFirstPerStrum: dirs,
      gapSeconds: 0.25,
      ringSeconds: 0.5,
    ));
    expect(events.length, greaterThanOrEqualTo(6),
        reason: 'all six overlapping strums must still register as onsets');
    var correct = 0;
    for (var i = 0; i < dirs.length && i < events.length; i++) {
      final want = dirs[i] ? StrumDirection.down : StrumDirection.up;
      if (events[i].direction == want) correct++;
    }
    expect(correct, greaterThanOrEqualTo(5),
        reason: 'baseline subtraction must isolate each strum from ring-out');
  });

  test('alternating pattern detects all four strums in order', () {
    final events = analyze(strumPattern(
      lowFirstPerStrum: [true, false, true, false],
      gapSeconds: 0.5,
    ));
    expect(events.length, 4);
    expect(events[0].direction, StrumDirection.down);
    expect(events[1].direction, StrumDirection.up);
    expect(events[2].direction, StrumDirection.down);
    expect(events[3].direction, StrumDirection.up);
    // Onset spacing ≈ 0.5 s.
    for (var i = 1; i < 4; i++) {
      expect(events[i].timeSec - events[i - 1].timeSec, closeTo(0.5, 0.08));
    }
  });

  test('TempoTracker: 0.5 s spacing → 120 BPM', () {
    final tracker = TempoTracker();
    for (var i = 0; i < 6; i++) {
      tracker.addOnset(i * 0.5);
    }
    expect(tracker.bpm, closeTo(120, 5));
  });

  test('TempoTracker folds eighth-note spacing into 60–200 range', () {
    final tracker = TempoTracker();
    for (var i = 0; i < 8; i++) {
      tracker.addOnset(i * 0.25); // 240 BPM raw → folded to 120
    }
    expect(tracker.bpm, closeTo(120, 5));
  });

  test('TempoTracker resets after a long silence gap', () {
    final tracker = TempoTracker();
    for (var i = 0; i < 6; i++) {
      tracker.addOnset(i * 0.5);
    }
    tracker.addOnset(10.0); // >2 s gap
    expect(tracker.bpm, 0);
  });
}
