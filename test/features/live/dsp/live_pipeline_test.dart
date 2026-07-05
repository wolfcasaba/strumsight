import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/live_pipeline.dart';
import 'package:music_theory/features/live/model/live_frame.dart';
import 'package:music_theory/features/live/model/strum.dart';

import '../../../support/synth.dart';

const sr = 44100;

/// Feed a signal in mic-like chunks (~23 ms) and collect every emitted frame.
List<LiveFrame> run(Float64List signal, {int chunkSize = 1024}) {
  final pipeline = LivePipeline(sampleRate: sr);
  final frames = <LiveFrame>[];
  for (var i = 0; i < signal.length; i += chunkSize) {
    final end = (i + chunkSize < signal.length) ? i + chunkSize : signal.length;
    frames.addAll(pipeline.addChunk(signal.sublist(i, end)));
  }
  return frames;
}

void main() {
  test('end-to-end: sustained C major chord is recognised from chunks', () {
    final frames = run(chordSignal(cMajorFreqs, seconds: 1.5));
    expect(frames, isNotEmpty);
    expect(frames.last.current?.label, 'C');
    expect(frames.last.listening, isTrue);
  });

  test('end-to-end: alternating strums produce directions, tempo and a bar',
      () {
    final frames = run(strumPattern(
      lowFirstPerStrum: [true, false, true, false, true, false],
      gapSeconds: 0.5,
    ));
    expect(frames, isNotEmpty);

    // Direction: both downs and ups must appear as latestStrum over time.
    final dirs = frames
        .map((f) => f.latestStrum?.direction)
        .whereType<StrumDirection>()
        .toSet();
    expect(dirs, containsAll({StrumDirection.down, StrumDirection.up}));

    // Tempo: 0.5 s spacing → ~120 BPM once enough onsets accumulated.
    expect(frames.last.bpm, closeTo(120, 10));

    // The bar shows at least two strum marks.
    final marked = frames.last.bar.where((s) => s.strum != null).length;
    expect(marked, greaterThanOrEqualTo(2));
  });

  test('end-to-end: silence yields no chord and near-zero level', () {
    final frames = run(Float64List(sr)); // 1 s of silence
    expect(frames, isNotEmpty);
    expect(frames.last.current, isNull);
    expect(frames.last.inputLevel, lessThan(0.05));
  });

  test('hero strum fades after 2 s without a new onset', () {
    final pipeline = LivePipeline(sampleRate: sr);
    final frames = <LiveFrame>[];
    final strum = strumSignal(lowFirst: true, seconds: 0.4);
    for (var i = 0; i < strum.length; i += 1024) {
      final end = (i + 1024 < strum.length) ? i + 1024 : strum.length;
      frames.addAll(pipeline.addChunk(strum.sublist(i, end)));
    }
    // 3 s of silence after the strum.
    final silence = Float64List(1024);
    for (var fed = 0; fed < sr * 3; fed += 1024) {
      frames.addAll(pipeline.addChunk(silence));
    }
    expect(frames.any((f) => f.latestStrum != null), isTrue,
        reason: 'the strum was visible right after the onset');
    expect(frames.last.latestStrum, isNull,
        reason: 'the arrow must fade after 2 s of silence');
  });
}
