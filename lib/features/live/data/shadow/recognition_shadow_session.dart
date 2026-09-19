import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../domain/recognition/recognition_mode.dart';
import '../../engine/dsp/live_pipeline.dart';
import '../../engine/ml/chord_crnn_shadow_runner.dart';
import '../../engine/recognition_shadow_observer.dart';
import 'recognition_shadow_gate.dart';
import 'recognition_shadow_observers.dart';
import 'recognition_shadow_recorder.dart';
import 'shadow_metrics.dart';

/// Everything one shadow comparison run needs, in a shape that survives an
/// isolate hop (`compute`): primitives, enums and byte buffers only.
@immutable
class RecognitionShadowRequest {
  const RecognitionShadowRequest({
    required this.pcm,
    required this.sampleRate,
    required this.gate,
    this.mode = RecognitionMode.free,
    this.strumWeights,
    this.chordWeights,
    this.chordSha256,
    this.ringCapacity = ShadowRingBuffer.defaultCapacity,
    this.chunkSamples = 2048,
  });

  /// The recorded mono buffer to compare over. The shadow run NEVER touches
  /// the live microphone: it re-analyses audio the Lab already captured, so
  /// it cannot compete with production for the mic or the DSP isolate.
  final List<double> pcm;
  final int sampleRate;
  final RecognitionShadowGate gate;
  final RecognitionMode mode;

  /// Strum weights for the shadow pipeline — the same bytes production
  /// loads, so the run reproduces production's own model path.
  final Uint8List? strumWeights;

  /// Chord CRNN weights (`assets/ml/chord_crnn.bin`).
  final Uint8List? chordWeights;

  /// The manifest's declared hash. When present the chord model refuses to
  /// activate unless the bytes in hand hash to it (fail-closed).
  final String? chordSha256;

  final int ringCapacity;
  final int chunkSamples;
}

/// Runs one shadow comparison over a recorded buffer (E14-R23 + E14-R26).
///
/// Top-level rather than a method so it can be handed to `compute` unchanged
/// — the whole comparison then happens off the UI isolate, which is why the
/// Lab can afford to run a second full pipeline plus a CRNN pass.
///
/// **Why a SEPARATE pipeline instance.** The live pipeline lives in the DSP
/// isolate and its seam is an output tap with a `void` return; a shadow
/// observer installed there has no channel back to the UI (the isolate
/// protocol carries `LiveFrame`s only). Rather than widen another package's
/// isolate protocol, the comparison is driven over the SAME PCM by a second,
/// short-lived pipeline. Production is then untouchable by construction —
/// there is no shared object at all — and the observers are still exercised
/// through the real seam. The one thing this shape cannot show is drift
/// between the two pipelines' internal state over a long live session; the
/// in-isolate wiring that would show it needs the protocol patch recorded in
/// the round report.
RecognitionShadowSnapshot runRecognitionShadow(
  RecognitionShadowRequest request,
) {
  final gate = request.gate;
  if (!gate.runsAnything) {
    // ZERO extra work: no pipeline, no model parse, no CQT frame. This early
    // return is the machine-checked half of "flag OFF ⇒ no inference".
    return RecognitionShadowSnapshot.disabled(mode: request.mode);
  }

  final recorder = RecognitionShadowRecorder(
    ringCapacity: request.ringCapacity,
  );

  final chordActivation = gate.chordEnabled
      ? ChordShadowActivation.activate(
          request.chordWeights,
          expectedSha256: request.chordSha256,
        )
      : null;
  final chordRunner = chordActivation?.runner;
  // Decode the whole captured buffer once, so the per-frame lookup below is
  // a grid index rather than a fresh inference.
  chordRunner?.runClip(request.pcm, request.sampleRate);

  final observers = <RecognitionShadowObserver>[
    if (gate.strumEnabled) StrumShadowObserver(recorder),
    if (chordRunner != null)
      ChordShadowObserver(recorder: recorder, candidate: chordRunner),
  ];

  if (observers.isNotEmpty) {
    final pipeline = LivePipeline(
      sampleRate: request.sampleRate,
      crnnWeights: request.strumWeights,
      mode: request.mode,
      shadowObserver: CompositeRecognitionShadowObserver(observers),
    );
    final pcm = request.pcm;
    final chunk = request.chunkSamples;
    for (var i = 0; i < pcm.length; i += chunk) {
      final end = i + chunk < pcm.length ? i + chunk : pcm.length;
      // The emitted frames are DISCARDED: this pipeline exists only to drive
      // the seam, and nothing it produces may reach the UI.
      pipeline.addChunk(pcm.sublist(i, end));
    }
  }

  return recorder.snapshot(
    mode: request.mode,
    strumShadowEnabled: gate.strumEnabled,
    chordShadowEnabled: gate.chordEnabled,
    strumStage: gate.strumStage,
    chordStage: gate.chordStage,
    chordFallbackReason: chordActivation?.reason,
  );
}
