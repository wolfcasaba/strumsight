// E14-R22 (shadow half) — the per-chunk cost of the shadow path is BOUNDED.
//
// SDD Ch14 Kör 22 asks a device question (p50/p95, peak memory, thermal
// throttling) that cannot be answered on this box: no phone, no profiler.
// What CAN be answered here, and is answered, is the structural half of it —
// does the shadow path's retained state grow with the length of the session?
//
// The measure is OBJECT COUNT and ALLOCATED SLOT COUNT, never wall-clock:
// a timing assertion on a CI runner is a flake, while "the recorder holds
// exactly the same number of objects after 10× more audio" is a fact.
//
// RED before this round: the recorder and its rings did not exist.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/recognition_rollout_stage.dart';
import 'package:strumsight/features/live/data/shadow/chord_shadow_candidate.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_gate.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_observers.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_recorder.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_session.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_mode.dart';
import 'package:strumsight/features/live/domain/recognition/strum_prediction.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

class _FixedCandidate implements ChordShadowCandidateSource {
  const _FixedCandidate();

  @override
  ChordShadowVerdict? verdictAtSeconds(double timeSec) =>
      ChordShadowVerdict(timeSec: timeSec, label: 'G', posterior: 0.8);
}

LiveFrame _frame(int seq, double t) => LiveFrame(
  current: null,
  next: null,
  latestStrum: null,
  bar: const [],
  bpm: 100,
  inputLevel: 0.3,
  tuningHz: 440,
  listening: true,
  strumSeq: seq,
  engineTimeSec: t,
);

StrumPrediction _prediction(int i) => StrumPrediction(
  onsetTimeSec: i.toDouble(),
  verdictTimeSec: i + 0.03,
  pDown: 0.9,
  pUp: 0.1,
  pNoStrum: 0.0,
  calibratedConfidence: null,
  modelId: 'bounded',
);

/// Drives the two observers over [chunks] synthetic frames.
RecognitionShadowRecorder _run(int chunks, {int ringCapacity = 16}) {
  final recorder = RecognitionShadowRecorder(ringCapacity: ringCapacity);
  final observer = CompositeRecognitionShadowObserver([
    StrumShadowObserver(recorder),
    ChordShadowObserver(recorder: recorder, candidate: const _FixedCandidate()),
  ]);
  for (var i = 0; i < chunks; i++) {
    observer.onRecognitionFrame(
      mode: RecognitionMode.free,
      frame: _frame(i, i * 0.066),
      chord: null,
      strum: _prediction(i),
    );
  }
  return recorder;
}

void main() {
  test('retained sample objects stop growing once the rings are full', () {
    final short = _run(200);
    final long = _run(2000);

    expect(short.debugRetainedSampleCount, long.debugRetainedSampleCount);
    expect(short.debugRetainedSampleCount, 32); // 16 strum + 16 chord
  });

  test('allocated storage is identical for 200 and 20 000 frames', () {
    final short = _run(200);
    final long = _run(20000);

    expect(short.debugAllocatedSlotCount, long.debugAllocatedSlotCount);
  });

  test('the aggregate COUNTS still grow — only the buffers are bounded', () {
    final short = _run(200);
    final long = _run(2000);

    expect(short.strumAggregate.observedFrames, 200);
    expect(long.strumAggregate.observedFrames, 2000);
    expect(long.chordAggregate.observedFrames, 2000);
    // The ring says how much of the tail it kept, so a reader can never
    // mistake the window for the whole session.
    final snapshot = long.snapshot(
      mode: RecognitionMode.free,
      strumShadowEnabled: true,
      chordShadowEnabled: true,
      strumStage: RecognitionRolloutStage.shadow,
      chordStage: RecognitionRolloutStage.shadow,
    );
    expect(snapshot.droppedStrumSamples, 2000 - 16);
    expect(snapshot.droppedChordSamples, 2000 - 16);
  });

  test('a disabled run allocates no ring at all', () {
    final snapshot = runRecognitionShadow(
      const RecognitionShadowRequest(
        pcm: <double>[],
        sampleRate: 44100,
        gate: RecognitionShadowGate.closed,
      ),
    );
    expect(snapshot.ringCapacity, 0);
    expect(snapshot.strumSamples, isEmpty);
    expect(snapshot.chordSamples, isEmpty);
  });
}
