// E14-R28 companion delivery for E14-R23 (ADR 0545 D6) — the shadow seam.
//
// PKG-E will hang a second (ML) recognition path off this seam in wave 2. The
// contract it has to be able to rely on, and that these cells pin, is that the
// seam is an OUTPUT TAP and nothing else:
//   1. with no observer installed, the pipeline behaves exactly as before;
//   2. with an observer installed, the emitted frames are BIT-IDENTICAL to the
//      no-observer run — an observer cannot influence recognition;
//   3. the observer sees every emitted frame, exactly once, together with the
//      production ChordPrediction, and the mode the engine was built in.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/recognition/chord_prediction.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_mode.dart';
import 'package:strumsight/features/live/domain/recognition/strum_prediction.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/recognition_shadow_observer.dart';
import 'package:strumsight/features/live/model/beat_slot.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

import '../../support/synth.dart';

const _sr = 44100;

/// Records what it is handed and returns nothing — the shape every real
/// shadow consumer has to fit into.
class _RecordingObserver implements RecognitionShadowObserver {
  final frames = <LiveFrame>[];
  final chords = <ChordPrediction?>[];
  final strums = <StrumPrediction?>[];
  final modes = <RecognitionMode>[];

  @override
  void onRecognitionFrame({
    required RecognitionMode mode,
    required LiveFrame frame,
    required ChordPrediction? chord,
    required StrumPrediction? strum,
  }) {
    modes.add(mode);
    frames.add(frame);
    chords.add(chord);
    strums.add(strum);
  }
}

List<LiveFrame> _drive(LivePipeline pipe, Float64List signal) {
  const chunk = 2048;
  final out = <LiveFrame>[];
  for (var i = 0; i < signal.length; i += chunk) {
    final end = (i + chunk < signal.length) ? i + chunk : signal.length;
    out.addAll(pipe.addChunk(signal.sublist(i, end)));
  }
  return out;
}

List<Object?> _signature(LiveFrame f) => <Object?>[
  f.current?.label,
  f.latestStrum?.direction,
  f.latestStrum?.confidence,
  f.bpm,
  f.inputLevel,
  f.strumSeq,
  f.latestStrumTime,
  f.onsetTimeSec,
  f.engineTimeSec,
  f.chordDecision,
  f.chordRejectReason,
  for (final BeatSlot s in f.bar) ...[
    s.label,
    s.isDownbeat,
    s.strum?.direction,
  ],
];

Float64List _signal() =>
    karplusStrongStrumPattern(cMajorFreqs, count: 3, sampleRate: _sr);

void main() {
  test('the default observer is the null object', () {
    // Constructing without one must not require the caller to know the seam
    // exists at all.
    expect(() => LivePipeline(sampleRate: _sr), returnsNormally);
    expect(
      const NoopRecognitionShadowObserver(),
      isA<RecognitionShadowObserver>(),
    );
  });

  test('installing an observer leaves the emitted frames bit-identical', () {
    final observed = LivePipeline(
      sampleRate: _sr,
      shadowObserver: _RecordingObserver(),
    );
    final plain = LivePipeline(sampleRate: _sr);

    final a = _drive(observed, _signal());
    final b = _drive(plain, _signal());

    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(_signature(a[i]), _signature(b[i]), reason: 'frame $i');
    }
  });

  test('the observer sees every emitted frame exactly once, with the chord '
      'prediction and the mode', () {
    final observer = _RecordingObserver();
    final pipe = LivePipeline(
      sampleRate: _sr,
      mode: RecognitionMode.guided,
      shadowObserver: observer,
    );
    final emitted = _drive(pipe, _signal());

    expect(observer.frames.length, emitted.length);
    for (var i = 0; i < emitted.length; i++) {
      expect(
        identical(observer.frames[i], emitted[i]),
        isTrue,
        reason: 'the tap must hand over the SAME frame instance, frame $i',
      );
    }
    expect(observer.chords.length, emitted.length);
    expect(
      observer.chords.every((c) => c != null),
      isTrue,
      reason: 'the dictionary path always has a typed chord verdict',
    );
    expect(
      observer.modes.every((m) => m == RecognitionMode.guided),
      isTrue,
      reason: 'a shadow measurement is only comparable within one mode',
    );
    // The strum slot may legitimately be null: the heuristic ladder has no
    // probabilities to report, and a fabricated number is worse than null.
    expect(observer.strums.length, emitted.length);
  });

  test('a NoopRecognitionShadowObserver run and a no-observer run agree', () {
    final noop = LivePipeline(
      sampleRate: _sr,
      shadowObserver: const NoopRecognitionShadowObserver(),
    );
    final plain = LivePipeline(sampleRate: _sr);
    final a = _drive(noop, _signal());
    final b = _drive(plain, _signal());
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(_signature(a[i]), _signature(b[i]), reason: 'frame $i');
    }
  });
}
