import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/domain/evaluation/confidence_calibration_profile.dart';
import 'package:strumsight/features/live/domain/evaluation/selective_prediction.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/recognition_calibration_wiring.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/engine/recognition_shadow_observer.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
// The typed predictions are read through the public barrel, the same way
// `strum_direction_abstention_test.dart` reaches them (ADR 0505 §0.0 R4).
import 'package:strumsight/features/live/public.dart'
    show
        ChordPrediction,
        RecognitionMode,
        RecognitionRuntimeInfo,
        StrumPrediction;

import '../../../support/synth.dart';

const _sr = 44100;

/// The identity `LivePipeline.debugWithClassifier` presents for the strum
/// band — an artefact must name EXACTLY this to be served.
const _strumModel = CalibrationModelIdentity(
  modelId: 'debug-fixed-classifier',
  modelSha256: '',
);

/// The identity the shipped NNLS→dictionary→Viterbi chord path presents.
const _chordModel = CalibrationModelIdentity(
  modelId: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
  modelSha256: shippedChordEngineRevision,
);

/// `calibrated = raw / 2` — a mapping no shipped artefact carries, chosen so
/// a mapped value is unmistakably the ARTEFACT's answer and not the raw
/// score leaking through.
CalibrationMapping _halfMapping() =>
    CalibrationMapping.piecewiseLinear(const <CalibrationKnot>[
      CalibrationKnot(raw: 0, calibrated: 0),
      CalibrationKnot(raw: 1, calibrated: 0.5),
    ]);

/// A TEST-ONLY artefact. It is built in Dart rather than loaded from
/// `evaluation/`, because no held-out calibration artefact exists in this
/// tree — that measurement is the round's NEEDS-MEASUREMENT item.
ConfidenceCalibrationProfile _artefact({
  required CalibrationBand band,
  required CalibrationModelIdentity model,
  CalibrationSampling sampling = CalibrationSampling.heldOut,
}) => ConfidenceCalibrationProfile(
  schemaVersion: supportedCalibrationSchemaVersion,
  artefactVersion: 'test-only-half-v1',
  band: band,
  model: model,
  provenance: CalibrationProvenance(
    corpusId: 'test-only-corpus',
    corpusSha256: 'test-only-sha',
    foldId: 'test-only-fold',
    sampling: sampling,
    observationCount: 128,
    fittedAtCommit: 'test-only-commit',
    producedBy: 'test/features/live/dsp/live_calibration_wiring_test.dart',
  ),
  defaultMapping: _halfMapping(),
  perClassMappings: const <ChordClassKey, CalibrationMapping>{},
);

/// Injects a FIXED direction verdict; the SuperFlux onset detector still runs
/// for real, exactly as in `strum_direction_abstention_test.dart`.
class _FixedClassifier implements StrumDirectionClassifier {
  _FixedClassifier(this.verdict);

  final StrumClassification verdict;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) {}

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) => verdict;
}

/// Records what the single output tap saw — the only way a test can read the
/// `StrumPrediction` the pipeline built, since the pipeline deliberately
/// does not publish it.
class _RecordingObserver implements RecognitionShadowObserver {
  final strums = <StrumPrediction>[];
  final chords = <ChordPrediction>[];

  @override
  void onRecognitionFrame({
    required RecognitionMode mode,
    required LiveFrame frame,
    required ChordPrediction? chord,
    required StrumPrediction? strum,
  }) {
    if (strum != null) strums.add(strum);
    if (chord != null) chords.add(chord);
  }
}

/// One CONFIRMED strum (margin 0.8, far above the 0.05 uncertain threshold),
/// so the calibration call site is reached with a known raw score of 0.9.
const _confirmedDown = StrumClassification(
  direction: StrumDirection.down,
  confidence: 0.9,
  pDown: 0.9,
  pUp: 0.1,
);

List<LiveFrame> _feed(LivePipeline pipeline, Float64List signal) {
  final frames = <LiveFrame>[];
  for (var i = 0; i < signal.length; i += 1024) {
    final end = (i + 1024 < signal.length) ? i + 1024 : signal.length;
    frames.addAll(pipeline.addChunk(signal.sublist(i, end)));
  }
  return frames;
}

/// One run of the strum path: the pipeline (for its read-only calibration
/// getters), the output tap (for the `StrumPrediction` itself) and the
/// frames production actually emitted.
class _StrumRun {
  _StrumRun({required this.pipeline, required this.tap, required this.frames});

  final LivePipeline pipeline;
  final _RecordingObserver tap;
  final List<LiveFrame> frames;
}

_StrumRun _runStrum({RecognitionCalibration? calibration}) {
  final tap = _RecordingObserver();
  final pipeline = LivePipeline.debugWithClassifier(
    _FixedClassifier(_confirmedDown),
    sampleRate: _sr,
    shadowObserver: tap,
    calibration: calibration,
  );
  return _StrumRun(
    pipeline: pipeline,
    tap: tap,
    frames: _feed(pipeline, strumSignal(lowFirst: true)),
  );
}

/// One run of the chord path. The frames are kept so a cell can prove the
/// decoder really produced a chord, rather than asserting on a `null` match
/// that would make the calibration claim vacuous.
class _ChordRun {
  _ChordRun({required this.pipeline, required this.frames});

  final LivePipeline pipeline;
  final List<LiveFrame> frames;
}

_ChordRun _runChord({RecognitionCalibration? calibration}) {
  final pipeline = LivePipeline(sampleRate: _sr, calibration: calibration);
  return _ChordRun(
    pipeline: pipeline,
    frames: _feed(pipeline, chordSignal(cMajorFreqs, seconds: 1.5)),
  );
}

void main() {
  group('E14-R31 strum band (ADR 0552 D7)', () {
    test('no artefact: the confidence stays null and says WHY', () {
      final run = _runStrum();

      expect(
        run.tap.strums,
        isNotEmpty,
        reason: 'the fixed classifier must reach the calibration call site',
      );
      expect(
        run.tap.strums.every((s) => s.calibratedConfidence == null),
        isTrue,
      );
      expect(
        run.pipeline.strumCalibration.unavailableReason,
        CalibrationUnavailableReason.noArtefact,
        reason: 'the null is a resolver VERDICT now, not a literal',
      );
      expect(run.pipeline.strumCalibration.isAvailable, isFalse);
    });

    test('a held-out, model-matched artefact produces the mapped value', () {
      final run = _runStrum(
        calibration: RecognitionCalibration(
          strumProfile: _artefact(
            band: CalibrationBand.strum,
            model: _strumModel,
          ),
        ),
      );

      expect(run.tap.strums, isNotEmpty);
      // raw = max(pDown, pUp) = 0.9, mapped through raw/2.
      expect(run.tap.strums.last.calibratedConfidence, closeTo(0.45, 1e-12));
      expect(
        run.pipeline.strumCalibration.calibratedConfidence,
        closeTo(0.45, 1e-12),
      );
    });

    test('an artefact for OTHER weights is refused, with a reason', () {
      final run = _runStrum(
        calibration: RecognitionCalibration(
          strumProfile: _artefact(
            band: CalibrationBand.strum,
            model: const CalibrationModelIdentity(
              modelId: 'debug-fixed-classifier',
              modelSha256: 'some-other-weights',
            ),
          ),
        ),
      );

      expect(
        run.tap.strums.every((s) => s.calibratedConfidence == null),
        isTrue,
      );
      expect(
        run.pipeline.strumCalibration.unavailableReason,
        CalibrationUnavailableReason.modelMismatch,
      );
    });

    test('an IN-SAMPLE artefact is representable but never served', () {
      final run = _runStrum(
        calibration: RecognitionCalibration(
          strumProfile: _artefact(
            band: CalibrationBand.strum,
            model: _strumModel,
            sampling: CalibrationSampling.inSample,
          ),
        ),
      );

      expect(
        run.tap.strums.every((s) => s.calibratedConfidence == null),
        isTrue,
      );
      expect(
        run.pipeline.strumCalibration.unavailableReason,
        CalibrationUnavailableReason.inSampleArtefact,
      );
    });
  });

  group('E14-R31 chord band (ADR 0552 D7)', () {
    test('no artefact: calibratedConfidence stays null with a reason', () {
      final run = _runChord();

      expect(
        run.frames.any((f) => f.current?.label == 'C'),
        isTrue,
        reason: 'the decoder must really have produced a chord here',
      );
      expect(run.pipeline.chordPrediction?.calibratedConfidence, isNull);
      expect(
        run.pipeline.chordCalibration.unavailableReason,
        CalibrationUnavailableReason.noArtefact,
      );
    });

    test('a chord artefact bound to the shipped engine revision maps', () {
      final run = _runChord(
        calibration: RecognitionCalibration(
          chordProfile: _artefact(
            band: CalibrationBand.chord,
            model: _chordModel,
          ),
        ),
      );

      expect(run.frames.any((f) => f.current?.label == 'C'), isTrue);
      expect(
        run.pipeline.chordCalibration.isAvailable,
        isTrue,
        reason: 'a held-out, model-matched chord artefact must be served',
      );
      // The artefact's mapping is raw/2 — the value can only be the
      // ARTEFACT's answer, never the raw match score leaking through.
      expect(
        run.pipeline.chordPrediction?.calibratedConfidence,
        closeTo(run.pipeline.chordConfidence.clamp(0.0, 1.0) / 2, 1e-12),
      );
    });

    test('a chord artefact bound to OTHER chord weights is refused', () {
      final run = _runChord(
        calibration: RecognitionCalibration(
          chordProfile: _artefact(
            band: CalibrationBand.chord,
            model: const CalibrationModelIdentity(
              modelId: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
              modelSha256: 'a-future-chord-crnn',
            ),
          ),
        ),
      );

      expect(run.pipeline.chordPrediction?.calibratedConfidence, isNull);
      expect(
        run.pipeline.chordCalibration.unavailableReason,
        CalibrationUnavailableReason.modelMismatch,
      );
    });
  });

  group('E14-R31 selective prediction is REPORTED, never applied (D8)', () {
    test('the shipped policy accepts everything, uncalibrated included', () {
      final run = _runStrum();

      expect(
        run.pipeline.selectivePredictionPolicy,
        const SelectivePredictionPolicy.acceptAll(),
      );
      expect(
        run.pipeline.strumSelectiveOutcome,
        const SelectiveOutcome.accept(),
      );
      expect(
        run.pipeline.chordSelectiveOutcome,
        const SelectiveOutcome.accept(),
      );
    });

    test('a strict policy abstains in the REPORT and nowhere else', () {
      final shipped = _runStrum();
      final strict = _runStrum(
        calibration: RecognitionCalibration(
          strumProfile: _artefact(
            band: CalibrationBand.strum,
            model: _strumModel,
          ),
          // 0.45 (the mapped value) is below 0.9, so the policy abstains.
          policy: SelectivePredictionPolicy.abstainBelow(0.9),
        ),
      );

      expect(
        strict.pipeline.strumSelectiveOutcome,
        const SelectiveOutcome.abstain(SelectiveAbstainReason.belowThreshold),
      );
      expect(
        strict.frames.map((f) => f.latestStrum?.direction.name).toList(),
        shipped.frames.map((f) => f.latestStrum?.direction.name).toList(),
        reason:
            'installing a stricter policy changes what is REPORTED, never '
            'what the pipeline emits (ADR 0552 D8)',
      );
      expect(
        strict.frames.map((f) => f.strumSeq).toList(),
        shipped.frames.map((f) => f.strumSeq).toList(),
      );
    });

    test('a policy that needs calibration abstains when there is none', () {
      final run = _runStrum(
        calibration: RecognitionCalibration(
          policy: SelectivePredictionPolicy.abstainBelow(0.1),
        ),
      );

      expect(
        run.pipeline.strumSelectiveOutcome,
        const SelectiveOutcome.abstain(
          SelectiveAbstainReason.noCalibratedConfidence,
        ),
        reason: 'an uncalibrated score is not a risk statement',
      );
    });
  });
}
