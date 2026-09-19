import '../domain/recognition/chord_prediction.dart';
import '../domain/recognition/recognition_mode.dart';
import '../domain/recognition/strum_prediction.dart';
import '../model/live_frame.dart';

/// The ONE seam a shadow/A-B consumer may hook into the live recognition path
/// (E14-R28 companion delivery for E14-R23, ADR 0545 D6).
///
/// `LivePipeline` calls [onRecognitionFrame] exactly once per EMITTED
/// [LiveFrame], handing over the frame that production is about to publish
/// plus the two typed predictions that produced it. The seam is strictly an
/// OUTPUT tap:
///
/// * the return type is `void` — an observer has no way to alter the frame,
///   the predictions, or any pipeline state;
/// * the pipeline never reads anything back from an observer;
/// * the default is the [NoopRecognitionShadowObserver] null object, so the
///   production path with no observer installed is bit-identical to the path
///   before this seam existed (pinned by a bit-identity test).
///
/// An implementation MUST NOT throw: the pipeline deliberately does not wrap
/// the call in a `try`/`catch`, because a swallowed shadow failure is exactly
/// the silent no-op AGENTS.md forbids — a broken observer must fail loudly in
/// the isolate that installed it, not quietly degrade recognition.
///
/// Arguments are passed individually rather than as one sample object so the
/// no-op path allocates nothing per frame.
abstract interface class RecognitionShadowObserver {
  void onRecognitionFrame({
    required RecognitionMode mode,
    required LiveFrame frame,
    required ChordPrediction? chord,
    required StrumPrediction? strum,
  });
}

/// The null-object default: does nothing, holds nothing, allocates nothing.
class NoopRecognitionShadowObserver implements RecognitionShadowObserver {
  const NoopRecognitionShadowObserver();

  @override
  void onRecognitionFrame({
    required RecognitionMode mode,
    required LiveFrame frame,
    required ChordPrediction? chord,
    required StrumPrediction? strum,
  }) {}
}

/// How an observer reaches a pipeline that runs in a DSP ISOLATE.
///
/// An observer instance cannot be sent to `Isolate.spawn` (it is an arbitrary
/// object graph), but a reference to a **top-level or static** function is
/// sendable. `RealStrumEngine` therefore takes a factory of this type, sends
/// it across the boundary and calls it INSIDE the DSP isolate to build the
/// observer there. Passing a closure (including a lambda that captures) will
/// fail at `Isolate.spawn` time, loudly — which is the intended behaviour.
typedef RecognitionShadowObserverFactory = RecognitionShadowObserver Function();
