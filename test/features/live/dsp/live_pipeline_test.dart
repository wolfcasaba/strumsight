import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/core/music/strum.dart';

import '../../../support/synth.dart';

const sr = 44100;

/// A [StrumDirectionClassifier] returning a FIXED verdict — E14-R10's
/// regression cell for "confirmed keeps today's behaviour" needs a
/// controlled, above-threshold probability pair, which no shipped model
/// asset can guarantee deterministically.
class _FixedVerdictClassifier implements StrumDirectionClassifier {
  _FixedVerdictClassifier(this.verdict);
  final StrumClassification verdict;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) {}

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) => verdict;
}

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

  test(
    'end-to-end: alternating strums produce directions, tempo and a bar',
    () {
      final frames = run(
        strumPattern(
          lowFirstPerStrum: [true, false, true, false, true, false],
          gapSeconds: 0.5,
        ),
      );
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
    },
  );

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
    expect(
      frames.any((f) => f.latestStrum != null),
      isTrue,
      reason: 'the strum was visible right after the onset',
    );
    expect(
      frames.last.latestStrum,
      isNull,
      reason: 'the arrow must fade after 2 s of silence',
    );
  });

  // E14-R10 (ADR 0512 acceptance §6/4): a confirmed CRNN margin must produce
  // EXACTLY the direction/confidence/strumSeq stepping the pre-R10 path
  // produced unconditionally — the decision only ever WITHHOLDS an
  // uncertain arrow, it never changes a confirmed one.
  test(
    'E14-R10: a confirmed direction margin keeps today\'s arrow behaviour',
    () {
      final pipeline = LivePipeline.debugWithClassifier(
        _FixedVerdictClassifier(
          const StrumClassification(
            direction: StrumDirection.up,
            confidence: 0.83,
            pDown: 0.4745,
            pUp: 0.5255, // margin 0.05099999999999999 > 0.05 -> confirmed
          ),
        ),
        sampleRate: sr,
      );
      final frames = <LiveFrame>[];
      final signal = strumSignal(lowFirst: true);
      for (var i = 0; i < signal.length; i += 1024) {
        final end = (i + 1024 < signal.length) ? i + 1024 : signal.length;
        frames.addAll(pipeline.addChunk(signal.sublist(i, end)));
      }
      final withArrow = frames.where((f) => f.latestStrum != null).toList();
      expect(withArrow, isNotEmpty);
      expect(withArrow.first.latestStrum!.direction, StrumDirection.up);
      expect(withArrow.first.latestStrum!.confidence, 0.83);
      expect(frames.last.strumSeq, 1);
    },
  );
}
