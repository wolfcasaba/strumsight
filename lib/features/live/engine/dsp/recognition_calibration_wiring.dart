/// The ONE place the live path turns a raw score into a calibrated
/// confidence and a selective accept/abstain verdict (E14-R31, ADR 0552).
///
/// It owns no mathematics. The mapping, its model binding, the in-sample
/// refusal and the abstention policy all live in PKG-B's
/// `domain/evaluation/` types (ADR 0536/0540); this file is the WIRING that
/// lets `live_pipeline.dart` call them without reaching for a resolver
/// itself, so there is exactly one call site per band.
///
/// The shipped state is [RecognitionCalibration.none]: no artefact exists in
/// this tree, so `StrumPrediction.calibratedConfidence` and
/// `ChordPrediction.calibratedConfidence` stay `null` and the policy is
/// `SelectivePredictionPolicy.acceptAll` — the identity on today's
/// behaviour. Nothing here can turn a raw score into a confidence by
/// itself: [CalibrationOutcome.calibratedConfidence] is `null` unless a
/// HELD-OUT, model-matched artefact was injected (ADR 0536 D2's
/// `inSampleArtefact` refusal is the resolver's, and this file never
/// bypasses it).
library;

import '../../domain/evaluation/confidence_calibration_profile.dart';
import '../../domain/evaluation/selective_prediction.dart';
import '../../model/recognition_runtime_info.dart';

/// The identity the SHIPPED chord path presents to the resolver.
///
/// The live chord verdict comes from NNLS → dictionary → Viterbi, which has
/// no weight file and therefore no content hash to bind an artefact to. The
/// binding is this revision tag instead — a NAMED constant, not an inline
/// empty string, precisely so a future weights-backed chord engine is
/// forced to present its real `chordModelSha256` here rather than silently
/// inheriting a mapping fitted for the dictionary decoder.
const String shippedChordEngineRevision = 'nnls-viterbi-dictionary-r176';

/// The strum and chord calibration artefacts a pipeline was constructed
/// with, plus the abstention policy applied to their output.
///
/// Immutable and Flutter-independent, so it copies across the DSP isolate
/// boundary the same way `RecognitionMode` does.
final class RecognitionCalibration {
  RecognitionCalibration({
    ConfidenceCalibrationProfile? strumProfile,
    ConfidenceCalibrationProfile? chordProfile,
    this.policy = const SelectivePredictionPolicy.acceptAll(),
  }) : strumResolver = ConfidenceCalibrationResolver(
         band: CalibrationBand.strum,
         profile: strumProfile,
       ),
       chordResolver = ConfidenceCalibrationResolver(
         band: CalibrationBand.chord,
         profile: chordProfile,
       );

  /// The SHIPPED state: no artefact in either band, accept everything.
  RecognitionCalibration.none() : this();

  final ConfidenceCalibrationResolver strumResolver;
  final ConfidenceCalibrationResolver chordResolver;

  /// `SelectivePredictionPolicy.acceptAll` by default — the identity on
  /// today's behaviour (ADR 0536 D1). A stricter policy only ever changes
  /// the REPORTED [SelectiveOutcome]; the pipeline's shipped decision logic
  /// does not read it (ADR 0552 D8).
  final SelectivePredictionPolicy policy;

  /// `true` when neither band can produce a calibrated confidence — the
  /// shipped state, and the reason both `calibratedConfidence` fields stay
  /// `null`.
  bool get isAbsent =>
      strumResolver.profile == null && chordResolver.profile == null;

  /// The strum band's model binding, taken from the runtime info of the
  /// weights that ACTUALLY produced the verdict. Re-read per call rather
  /// than cached, so a fallback activation can never be calibrated with the
  /// real model's mapping.
  static CalibrationModelIdentity strumModelIdentity(
    RecognitionRuntimeInfo info,
  ) => CalibrationModelIdentity(
    modelId: info.strumModelId,
    modelSha256: info.strumModelSha256,
  );

  /// The chord band's model binding — see [shippedChordEngineRevision].
  static CalibrationModelIdentity chordModelIdentity(
    RecognitionRuntimeInfo info,
  ) => CalibrationModelIdentity(
    modelId: info.chordEngineId,
    modelSha256: shippedChordEngineRevision,
  );

  /// Maps a raw strum-direction score, or explains why it cannot.
  CalibrationOutcome calibrateStrum({
    required double rawConfidence,
    required RecognitionRuntimeInfo info,
  }) => strumResolver.calibrate(
    rawConfidence: rawConfidence,
    loadedModel: strumModelIdentity(info),
  );

  /// Maps a raw chord-match score for the chord [label], or explains why it
  /// cannot. `'N.C.'` and the two reserved evaluation labels carry no chord
  /// class, so they fall through to the artefact's default mapping
  /// (`ChordClassKey.tryParseLabel` returns `null` for them).
  CalibrationOutcome calibrateChord({
    required double rawConfidence,
    required String label,
    required RecognitionRuntimeInfo info,
  }) => chordResolver.calibrate(
    rawConfidence: rawConfidence,
    loadedModel: chordModelIdentity(info),
    chordClass: ChordClassKey.tryParseLabel(label),
  );

  /// Applies [policy] to an already-calibrated (or absent) confidence.
  SelectiveOutcome select(double? calibratedConfidence) =>
      applySelectivePolicy(
        calibratedConfidence: calibratedConfidence,
        policy: policy,
      );
}
