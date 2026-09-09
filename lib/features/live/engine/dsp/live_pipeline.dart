import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../../core/music/chord.dart';
import '../../domain/evaluation/confidence_calibration_profile.dart';
import '../../domain/evaluation/selective_prediction.dart';
import '../../domain/recognition/chord_latch_diagnostics.dart';
import '../../domain/recognition/chord_prediction.dart';
import '../../domain/recognition/device_audio_profile.dart';
import '../../domain/recognition/recognition_decision.dart';
import '../../domain/recognition/recognition_mode.dart';
import '../../domain/recognition/signal_quality_snapshot.dart';
import '../../domain/recognition/strum_prediction.dart';
import '../../model/live_frame.dart';
import '../../model/recognition_runtime_info.dart';
import '../../../../core/music/strum.dart';
import '../../model/beat_slot.dart';
import '../ml/live_crnn_classifier.dart';
import '../ml/model_activation.dart';
import '../ml/strum_crnn.dart';
import '../quality/live_signal_quality_analyzer.dart';
import '../recognition_shadow_observer.dart';
import 'chord_dictionary.dart';
import 'chord_matcher.dart';
import 'dsp_config.dart';
import 'nnls_chroma.dart';
import 'quality_aware_preprocessor.dart';
import 'recognition_calibration_wiring.dart';
import '../../../../core/audio/dsp/sliding_framer.dart';
import 'strum_analyzer.dart';
import 'strum_direction_classifier.dart';
import 'tempo_tracker.dart';
import 'viterbi_chord_decoder.dart';

/// Typed activation of the live CRNN from isolate-crossed weight [weights]
/// (ADR 0355): the caller's BEHAVIOUR is unchanged — a null `model` on the
/// returned [ModelActivation] still means "use the heuristic" — this only
/// makes the outcome observable via its `info`. `modelId` stays the neutral
/// [RecognitionRuntimeInfo.isolateLiveModelId] / `'none'` placeholders: the
/// isolate boundary doesn't carry the real asset filename yet (E14-R04 wires
/// it, ADR 0355 R3).
ModelActivation<StrumDirectionClassifier> _activateLiveCrnn(
  Uint8List? weights,
  int sampleRate,
) {
  if (weights == null) {
    return ModelActivation.fallback(
      RecognitionRuntimeInfo.fallback(
        FallbackReason.assetMissing,
        sampleRate: sampleRate,
      ),
    );
  }
  final netActivation = StrumCrnn.activateBytes(
    weights,
    modelId: RecognitionRuntimeInfo.isolateLiveModelId,
    sampleRate: sampleRate,
  );
  final net = netActivation.model;
  if (net == null) {
    return ModelActivation.fallback(netActivation.info);
  }
  return ModelActivation.activated(
    LiveCrnnStrumClassifier(net, sampleRate: sampleRate),
    netActivation.info,
  );
}

/// The REAL detection pipeline: PCM chunks in → [LiveFrame]s out (~15 Hz).
///
/// Pure Dart, deterministic (sample-count clock, no wall time), platform-free
/// — the isolate and mic are plumbing around this class, and tests drive it
/// directly with synthesized PCM (RAG chunk 010).
class LivePipeline {
  /// Activates the live CRNN (or records why it fell back, ADR 0355) ONCE,
  /// before delegating to the real constructor — [_activateLiveCrnn] must
  /// run a single time per pipeline, never per frame.
  factory LivePipeline({
    required int sampleRate,
    Uint8List? crnnWeights,
    double? chordConfRise,
    double? chordConfRelease,
    int? chordReleaseHoldFrames,
    RecognitionMode mode = RecognitionMode.free,
    RecognitionShadowObserver shadowObserver =
        const NoopRecognitionShadowObserver(),
    LivePreprocessingConfig preprocessing =
        const LivePreprocessingConfig.disabled(),
    DeviceAudioProfile deviceProfile = const DeviceAudioProfile.identity(),
    RecognitionCalibration? calibration,
  }) {
    return LivePipeline._(
      sampleRate: sampleRate,
      crnnActivation: _activateLiveCrnn(crnnWeights, sampleRate),
      chordConfRise: chordConfRise,
      chordConfRelease: chordConfRelease,
      chordReleaseHoldFrames: chordReleaseHoldFrames,
      mode: mode,
      shadowObserver: shadowObserver,
      preprocessing: preprocessing,
      deviceProfile: deviceProfile,
      calibration: calibration,
    );
  }

  /// Test-only seam (the [debugStrumClassifier] getter's counterpart): lets a
  /// test inject a [StrumDirectionClassifier] with FIXED probabilities in
  /// place of a real model activation, so the margin-threshold decision
  /// (ADR 0512 D6) can be exercised end-to-end without a trained asset.
  @visibleForTesting
  factory LivePipeline.debugWithClassifier(
    StrumDirectionClassifier classifier, {
    required int sampleRate,
    RecognitionMode mode = RecognitionMode.free,
    RecognitionShadowObserver shadowObserver =
        const NoopRecognitionShadowObserver(),
    LivePreprocessingConfig preprocessing =
        const LivePreprocessingConfig.disabled(),
    DeviceAudioProfile deviceProfile = const DeviceAudioProfile.identity(),
    RecognitionCalibration? calibration,
  }) {
    return LivePipeline._(
      sampleRate: sampleRate,
      mode: mode,
      shadowObserver: shadowObserver,
      preprocessing: preprocessing,
      deviceProfile: deviceProfile,
      calibration: calibration,
      crnnActivation: ModelActivation<StrumDirectionClassifier>.activated(
        classifier,
        RecognitionRuntimeInfo(
          strumModelId: 'debug-fixed-classifier',
          strumModelVersion: 0,
          strumModelSha256: '',
          chordEngineId: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
          sampleRate: sampleRate,
          frontendVersion: RecognitionRuntimeInfo.frontendCrnnV1,
        ),
      ),
    );
  }

  LivePipeline._({
    required this.sampleRate,
    required ModelActivation<StrumDirectionClassifier> crnnActivation,
    required this.mode,
    required RecognitionShadowObserver shadowObserver,
    required LivePreprocessingConfig preprocessing,
    required DeviceAudioProfile deviceProfile,
    required RecognitionCalibration? calibration,
    double? chordConfRise,
    double? chordConfRelease,
    int? chordReleaseHoldFrames,
  }) : _crnnActivation = crnnActivation,
       _shadowObserver = shadowObserver,
       _preprocessor = QualityAwarePreprocessor(
         config: preprocessing,
         deviceProfile: deviceProfile,
       ),
       _calibration = calibration ?? RecognitionCalibration.none(),
       _chordConfRise = chordConfRise ?? DspConfig.chordConfRise,
       _chordConfRelease = chordConfRelease ?? DspConfig.chordConfRelease,
       _chordReleaseHoldFrames =
           chordReleaseHoldFrames ?? DspConfig.chordReleaseHoldFrames,
       _chroma = NnlsChroma(
         sampleRate: sampleRate,
         window: DspConfig.nnlsWindow,
       ),
       _strums = StrumAnalyzer(
         sampleRate: sampleRate,
         // The live 70 ms model behind the r139 seam (r169): the engine
         // hands the weights-asset BYTES across the isolate boundary
         // (rootBundle is main-isolate-only, same pattern as the r165
         // Analyze wiring); null/unparseable keeps the heuristic — the
         // model is an upgrade, never a dependency. Typed observably via
         // [_crnnActivation] (ADR 0355), computed ONCE by the factory above.
         classifier: crnnActivation.model,
       ),
       _chordFramer = SlidingFramer(
         window: DspConfig.nnlsWindow,
         hop: DspConfig.nnlsHop,
       ),
       _onsetFramer = SlidingFramer(
         window: DspConfig.onsetWindow,
         hop: DspConfig.onsetHop,
       ),
       _emitEverySamples = (sampleRate * DspConfig.frameEmitSeconds).round();

  final int sampleRate;

  /// Which recognition regime this pipeline was CONSTRUCTED in (E14-R30,
  /// ADR 0544 D1). In [RecognitionMode.free] the expected-chord hint cannot
  /// exist, so [setExpectedChord] cannot reach the decoder with a value —
  /// see [ExpectedChordHint.forMode].
  final RecognitionMode mode;

  final ModelActivation<StrumDirectionClassifier> _crnnActivation;

  /// The output tap (ADR 0545 D6). Defaults to the null object, so the
  /// production path is bit-identical to the pre-seam pipeline.
  final RecognitionShadowObserver _shadowObserver;

  /// Quality-aware input preprocessing (E14-R31, ADR 0552). Disabled in the
  /// shipped build, where [QualityAwarePreprocessor.process] hands back the
  /// caller's own chunk instance — the DSP path below is then bit-identical
  /// to the pre-R31 pipeline, which
  /// `test/features/live/preprocessing/live_preprocessing_test.dart` pins.
  final QualityAwarePreprocessor _preprocessor;

  /// The calibration artefacts + abstention policy this pipeline was built
  /// with (E14-R31, ADR 0552 D7). [RecognitionCalibration.none] — the
  /// shipped state — keeps both `calibratedConfidence` fields `null` and
  /// the policy at `acceptAll`.
  final RecognitionCalibration _calibration;

  /// The musical-presence gate (round 176): a Schmitt trigger on the
  /// EMA-smoothed chord-match confidence. A chord is surfaced to the UI once
  /// the smoothed confidence rises past [_chordConfRise] and held until it
  /// falls below [_chordConfRelease] — so voiced speech (weak, ambiguous, spiky
  /// chord matches) never latches and the screen shows nothing instead of
  /// jumping between phantom chords, while a real guitar chord latches on the
  /// strum and rings out. Injectable so the offline probe can sweep it.
  final double _chordConfRise;
  final double _chordConfRelease;
  final int _chordReleaseHoldFrames;
  double _chordConfEma = 0;
  bool _chordLatched = false;
  int _belowReleaseFrames = 0;

  final NnlsChroma _chroma;
  final ViterbiChordDecoder _chordDecoder = ViterbiChordDecoder(
    selfBonus: DspConfig.chordSelfTransitionBonus,
    dictionary: ChordDictionary(
      bassWeight: DspConfig.chordBassWeight,
      trebleWeight: DspConfig.chordTrebleWeight,
      noChordScore: DspConfig.chordNoChordScore,
    ),
  );
  final StrumAnalyzer _strums;

  /// The Live-side signal-quality analyzer (E14-R05, ADR 0507) — fed the raw
  /// chunk alongside the DSP pipeline, exposed read-only via [signalQuality].
  /// Does not touch [LiveFrame] or [_buildFrame] (brief §0.0 R7).
  final LiveSignalQualityAnalyzer _signalQuality = LiveSignalQualityAnalyzer();

  static final Float64List _silentChroma = Float64List(12);
  final TempoTracker _tempo = TempoTracker();
  final SlidingFramer _chordFramer;
  final SlidingFramer _onsetFramer;

  final int _emitEverySamples;
  int _samplesSeen = 0;
  int _lastEmitAt = 0;

  /// Hint the currently expected chord (or clear with null).
  ///
  /// E14-R30 (ADR 0544 D2): the label is funnelled through
  /// [ExpectedChordHint.forMode], which yields `null` in
  /// [RecognitionMode.free]. A free-mode pipeline therefore CLEARS the
  /// decoder's hint no matter what a caller pushes in — the isolation is a
  /// machine-checked contract, not the Live screen's `setExpectedChord(null)`
  /// convention it replaces. In [RecognitionMode.guided] the hint reaches the
  /// decoder, where it is a pure tie-breaker
  /// ([ViterbiChordDecoder.expectedTieBreakBand]).
  void setExpectedChord(String? label) =>
      _chordDecoder.setExpected(ExpectedChordHint.forMode(mode, label));

  /// The outcome every band reports in the SHIPPED tree: there is no
  /// calibration artefact, so there is no calibrated confidence — and the
  /// reason travels with the absence instead of being lost (ADR 0552 D7).
  static const CalibrationOutcome _noCalibrationArtefact =
      CalibrationOutcome.unavailable(CalibrationUnavailableReason.noArtefact);

  ChordMatch? _lastChord;
  StrumPrediction? _lastStrumPrediction;
  CalibrationOutcome _lastStrumCalibration = _noCalibrationArtefact;
  SelectiveOutcome _lastStrumSelectiveOutcome = const SelectiveOutcome.accept();
  int _chordFrameIndex = 0;
  double _lastChordFrameTimeSec = 0;
  bool _lastTonalGatePassed = false;
  Strum? _latestStrum;
  double _latestStrumTime = -1;
  double _lastOnsetTimeSec = -1;
  int _strumSeq = 0;
  final List<BeatSlot> _bar = _emptyBar();
  int _lastSlot = -1;
  double _barStartSec = -1;

  static const _labels = ['1', '&', '2', '&', '3', '&', '4', '&'];

  static List<BeatSlot> _emptyBar() => [
    for (var i = 0; i < 8; i++)
      BeatSlot(label: _labels[i], isDownbeat: i.isEven),
  ];

  /// Feed a PCM chunk (any length, -1..1). Returns the frames due for
  /// emission (usually 0 or 1).
  List<LiveFrame> addChunk(List<double> chunk) {
    final out = <LiveFrame>[];
    _samplesSeen += chunk.length;
    // The quality analyzer always measures the RAW input: it is the sensor
    // the preprocessing stage reads, so feeding it the already-corrected
    // signal would close a loop and make the correction chase itself
    // (ADR 0552 D5).
    _signalQuality.addChunk(chunk);
    // E14-R31: identity (the SAME list instance) unless the round's flag is
    // on AND the snapshot asks for a level correction — the sample count is
    // never changed, so [_samplesSeen] above stays correct either way.
    final input = _preprocessor.process(chunk, _signalQuality.snapshot);

    // Fast path: onsets + direction.
    for (final frame in _onsetFramer.add(input)) {
      final event = _strums.process(frame);
      // Onset-aligned chord updates (chunk 016, round 138): a fresh onset
      // relaxes the Viterbi switch penalty for the next couple of chord
      // frames — the chord changes ON the strum, stays stable between.
      if (_strums.onsetJustFired) {
        _chordDecoder.noteOnset();
        // E14-R28 (ADR 0545 D2): recorded BEFORE classification, so an onset
        // whose direction is later rejected still opens the chord-transition
        // gate. `_latestStrumTime` cannot serve this role — it only advances
        // for a CONFIRMED direction.
        _lastOnsetTimeSec = _strums.lastOnsetSec;
      }
      if (event == null) continue;
      _tempo.addOnset(event.timeSec);
      if (event.direction != null && _isDirectionConfirmed(event)) {
        _latestStrum = Strum(
          direction: event.direction!,
          confidence: event.confidence,
        );
        _latestStrumTime = event.timeSec;
        _strumSeq++; // a discrete new strum (for the play-along scorer)
        _placeInBar(event);
      }
    }

    // Slow path: chroma → chord. The NNLS transcription yields a bass+treble
    // (24-dim) chroma; the Viterbi decoder scores it against the chord-profile
    // dictionary and smooths the path (RAG chunk 012). Gate on tonalness so a
    // diffuse frame (speech, noise) is fed as silence and resolves to no-chord
    // rather than faking one (RAG chunk 003).
    for (final frame in _chordFramer.add(input)) {
      final chroma = _chroma.process(frame);
      final tonal =
          chroma != null &&
          _chroma.lastTonalness >= DspConfig.chordMinTonalness;
      _lastChord = tonal
          ? _chordDecoder.process(
              _chroma.lastBassChroma,
              _chroma.lastTrebleChroma,
            )
          : _chordDecoder.process(_silentChroma, _silentChroma, gated: true);
      // Musical-presence gate (round 176 probe): EMA-smooth the match
      // confidence so a sustained guitar chord builds up over the gate while a
      // brief speech spike cannot. A gated/no-chord frame feeds 0, decaying the
      // EMA back down so a phantom chord fades out.
      final conf = _lastChord?.confidence ?? 0.0;
      _applyChordConfEma(
        _chordConfEma + DspConfig.chordConfEmaAlpha * (conf - _chordConfEma),
      );
      _recordChordLatchDiagnostics(tonal);
    }

    // Sample-clock emission (~15 Hz).
    if (_samplesSeen - _lastEmitAt >= _emitEverySamples) {
      _lastEmitAt = _samplesSeen;
      final chord = chordPrediction;
      final frame = _buildFrame(chord);
      out.add(frame);
      // ADR 0545 D6 — the single shadow tap: production has already decided
      // everything this frame carries, and the observer's return type is
      // `void`, so nothing it does can reach [out].
      _shadowObserver.onRecognitionFrame(
        mode: mode,
        frame: frame,
        chord: chord,
        strum: _lastStrumPrediction,
      );
    }
    return out;
  }

  /// ADR 0512 D2/D3 — the ONLY place this round decides whether a direction
  /// surfaces: a probability-less [event] (the heuristic ladder, which has
  /// no probability to report) keeps today's behaviour unconditionally; a
  /// probability-bearing [event] (the CRNN) builds the ALREADY-MERGED
  /// [StrumPrediction] and defers to its [StrumPrediction.decision] getter —
  /// this pipeline never reimplements the margin threshold itself.
  bool _isDirectionConfirmed(StrumEvent event) {
    final pDown = event.pDown;
    final pUp = event.pUp;
    if (pDown == null || pUp == null) return true;
    // E14-R31 (ADR 0552 D7): the ONE strum-band calibration call site. The
    // raw score is the winning DIRECTION probability — `pNoStrum` belongs
    // to the abstain head, not to "how sure are we it was a downstroke".
    // With no artefact (the shipped state) the outcome is `unavailable` and
    // the field stays `null`; a mapped value can only come from a HELD-OUT,
    // model-matched artefact (the resolver's rule, ADR 0536 D2).
    final outcome = _calibration.calibrateStrum(
      rawConfidence: math.max(pDown, pUp),
      info: _crnnActivation.info,
    );
    _lastStrumCalibration = outcome;
    _lastStrumSelectiveOutcome = _calibration.select(
      outcome.calibratedConfidence,
    );
    final prediction = StrumPrediction(
      onsetTimeSec: event.timeSec,
      verdictTimeSec: event.timeSec,
      pDown: pDown,
      pUp: pUp,
      pNoStrum: event.pNoStrum ?? 0.0,
      calibratedConfidence: outcome.calibratedConfidence,
      modelId: _crnnActivation.info.strumModelId,
    );
    // Kept for the shadow tap only (ADR 0545 D6) — the decision below is
    // unchanged. Note it retains REJECTED verdicts too: a shadow consumer
    // measuring abstention needs the frames production threw away, and the
    // heuristic (probability-less) path leaves it `null`, because there is no
    // prediction to report rather than a fabricated one.
    _lastStrumPrediction = prediction;
    return prediction.decision == RecognitionDecision.confirmed;
  }

  /// The musical-presence Schmitt trigger (round 176), factored out of the
  /// per-frame loop above so a test can drive the EXACT rise/release compare
  /// with a controlled [ema] value — ADR 0516 §6 pt.4 needs the rise
  /// boundary (`chordConfRise = 0.54`, inclusive) measured without audio.
  /// The comparison itself is UNCHANGED: this is a behaviour-preserving
  /// extraction, not a new threshold (D3).
  void _applyChordConfEma(double ema) {
    _chordConfEma = ema;
    if (_chordConfEma >= _chordConfRise) {
      _chordLatched = true;
      _belowReleaseFrames = 0;
    } else if (_chordConfEma < _chordConfRelease) {
      // Debounced release: blank only after the confidence has stayed low for
      // a few frames, so a mid-strum dip doesn't flicker a sustained chord.
      if (++_belowReleaseFrames >= _chordReleaseHoldFrames) {
        _chordLatched = false;
      }
    } else {
      _belowReleaseFrames = 0; // between release and rise: still supported
    }
  }

  /// ADR 0516 D1/D3/D4 — the ONLY place the chord verdict is typed, mirroring
  /// [_isDirectionConfirmed]'s pattern for direction: derives the ALREADY-
  /// MERGED [RecognitionDecision] + [RecognitionRejectReason] from the
  /// ALREADY-SHIPPED [chordLatched] gate, the tonalness-gated [hasMatch] and
  /// [signalQualityState] — no new threshold, no second enum. `confirmed`
  /// is checked FIRST and is EXACTLY [_buildFrame]'s `showChord` condition
  /// (`chordLatched && hasMatch`), so it can never diverge from it (§6 pt.2);
  /// among the remaining cases the jel-minőség reason takes priority over
  /// `noChord`/`lowConfidence` (D4: a bad mic reading is never blamed on the
  /// player's fingers). ADR 0535 D2: the signal reason is derived by an
  /// EXHAUSTIVE `switch` over [SignalQualityState] with NO `default` arm —
  /// each non-`good` state maps to its OWN `signal*` reason, so a future
  /// state cannot silently fall into a collector bucket; `good`/`unknown`
  /// yield no signal reason (unchanged behaviour, no new threshold). Public
  /// + static so a test can drive it directly, without a full pipeline
  /// (§6 pt.3/4).
  @visibleForTesting
  static (RecognitionDecision, RecognitionRejectReason?)
  debugDeriveChordDecision({
    required bool chordLatched,
    required bool hasMatch,
    required SignalQualityState signalQualityState,
  }) {
    if (chordLatched && hasMatch) {
      return (RecognitionDecision.confirmed, null);
    }
    final signalReason = switch (signalQualityState) {
      SignalQualityState.tooQuiet => RecognitionRejectReason.signalTooQuiet,
      SignalQualityState.tooLoud => RecognitionRejectReason.signalTooLoud,
      SignalQualityState.clipping => RecognitionRejectReason.signalClipping,
      SignalQualityState.tooNoisy => RecognitionRejectReason.signalTooNoisy,
      SignalQualityState.speechLike => RecognitionRejectReason.signalSpeechLike,
      SignalQualityState.unstable => RecognitionRejectReason.signalUnstable,
      SignalQualityState.good || SignalQualityState.unknown => null,
    };
    if (signalReason != null) {
      return (RecognitionDecision.rejected, signalReason);
    }
    if (!hasMatch) {
      return (RecognitionDecision.rejected, RecognitionRejectReason.noChord);
    }
    return (
      RecognitionDecision.uncertain,
      RecognitionRejectReason.lowConfidence,
    );
  }

  void _placeInBar(StrumEvent event) {
    final bpm = _tempo.bpm;
    int slot;
    if (bpm > 0) {
      final eighth = 60 / bpm / 2;
      if (_barStartSec < 0 || event.timeSec - _barStartSec >= 8 * eighth) {
        _barStartSec = event.timeSec;
        _clearBar();
      }
      slot = ((event.timeSec - _barStartSec) / eighth).round().clamp(0, 7);
    } else {
      slot = (_lastSlot + 1) % 8;
      if (slot == 0) _clearBar();
    }
    _lastSlot = slot;
    _bar[slot] = BeatSlot(
      label: _labels[slot],
      isDownbeat: slot.isEven,
      strum: _latestStrum,
    );
  }

  void _clearBar() {
    for (var i = 0; i < 8; i++) {
      _bar[i] = BeatSlot(label: _labels[i], isDownbeat: i.isEven);
    }
  }

  LiveFrame _buildFrame(ChordPrediction? chord) {
    final nowSec = _samplesSeen / sampleRate;
    // The hero arrow fades out: drop the strum after 2 s without a new one.
    if (_latestStrum != null && nowSec - _latestStrumTime > 2.0) {
      _latestStrum = null;
    }
    final level = (_strums.lastRms * 8).clamp(0.0, 1.0).toDouble();
    // Only surface the chord once the smoothed match confidence clears the
    // musical-presence gate: below it we're almost certainly hearing speech /
    // noise, not a guitar, so show nothing rather than a phantom chord.
    final showChord = _lastChord != null && _chordLatched;
    // ADR 0516 D5: additive only — [current] keeps deriving from the SAME
    // `showChord` bit (bit-identical, §5.6), [chord] is a second, typed view
    // of the SAME state, never a second decision. It is passed IN (rather
    // than read from [chordPrediction] here) only so the caller can hand the
    // very same instance to the shadow tap instead of allocating a second
    // one — the value is identical either way.
    return LiveFrame(
      current: showChord ? Chord(_lastChord!.chord.label) : null,
      next: null, // the real engine cannot know the future
      latestStrum: _latestStrum,
      bar: List.unmodifiable(_bar),
      bpm: _tempo.bpm,
      inputLevel: level,
      tuningHz: 440,
      listening: true,
      strumSeq: _strumSeq,
      latestStrumTime: _latestStrumTime,
      onsetTimeSec: _lastOnsetTimeSec,
      engineTimeSec: nowSec,
      chordDecision: chord?.decision,
      chordRejectReason: chord?.rejectReason,
    );
  }

  /// Which strum model is behind this pipeline, or why it fell back to the
  /// heuristic (ADR 0355) — computed ONCE at construction by the factory
  /// constructor; nothing on the per-frame path reads or recomputes this.
  /// The Lab surfaces it via `LiveLabController.reportRuntimeInfo`; the
  /// actual isolate → Lab wiring lands in E14-R04 (R3).
  RecognitionRuntimeInfo get runtimeInfo => _crnnActivation.info;

  /// The latest confirmed Live audio-quality snapshot (E14-R05, ADR 0507
  /// D10) — a read-only getter in the same shape as [runtimeInfo]; the
  /// `LiveFrame` contract and `inputLevel` are untouched by this round.
  SignalQualitySnapshot get signalQuality => _signalQuality.snapshot;

  /// Raw, UNCALIBRATED chord-match confidence (separate from the strum
  /// confidence the pill shows) — NOT the same shape as
  /// [ChordPrediction.calibratedConfidence], which stays `null` until a
  /// MEASURED calibration exists (ADR 0505 D2, ADR 0516 D2). Available for
  /// future UI use.
  double get chordConfidence => _lastChord?.confidence ?? 0;

  /// The pipeline's typed chord verdict (ADR 0516 D1) — derived from the
  /// SAME latch/tonalness/signal-quality gates [_buildFrame] uses for
  /// [LiveFrame.current], never a second derivation (D3).
  /// [ChordPrediction.calibratedConfidence] is produced through PKG-B's
  /// resolver (E14-R31, ADR 0552 D7) and stays `null` in the shipped tree,
  /// where no chord artefact exists — the `null` is now a RESOLVER verdict
  /// carrying a reason ([chordCalibration]), not a hard-coded literal.
  /// `pNoChord`/`pUnknown` reflect this decoder's actual (hard,
  /// deterministic) match/no-match state, not a fabricated probability —
  /// the dictionary path never reports an "unknown chord" state, so
  /// `pUnknown` is always 0.
  ChordPrediction? get chordPrediction {
    final match = _lastChord;
    final (decision, rejectReason) = debugDeriveChordDecision(
      chordLatched: _chordLatched,
      hasMatch: match != null,
      signalQualityState: signalQuality.state,
    );
    final label = match?.chord.label ?? 'N.C.';
    final (root, quality) = _splitChordLabel(label);
    return ChordPrediction(
      label: label,
      root: root,
      quality: quality,
      pNoChord: match == null ? 1.0 : 0.0,
      pUnknown: 0.0,
      calibratedConfidence: chordCalibration.calibratedConfidence,
      stabilityFrames: 0,
      sourceEngine: RecognitionRuntimeInfo.chordEngineNnlsViterbi,
      decision: decision,
      rejectReason: rejectReason,
    );
  }

  /// The chord band's calibration verdict for the CURRENT frame — the
  /// mapped value, or the typed reason there is none (E14-R31, ADR 0552
  /// D7). Side-effect-free: it reads the same three scalars
  /// [chordPrediction] does, so the two can never disagree.
  ///
  /// A frame with no chord match goes through the SAME call (raw score 0,
  /// label `N.C.`) rather than short-circuiting to a hand-picked reason:
  /// `N.C.` carries no chord class, so an artefact would answer with its
  /// default mapping at 0 — a defined value, not an invented one.
  CalibrationOutcome get chordCalibration {
    final match = _lastChord;
    return _calibration.calibrateChord(
      rawConfidence: match?.confidence ?? 0,
      label: match?.chord.label ?? 'N.C.',
      info: _crnnActivation.info,
    );
  }

  /// The strum band's calibration verdict for the most recent
  /// probability-bearing verdict (ADR 0552 D7). Stays at "no artefact"
  /// while the heuristic ladder is in charge — that path has no
  /// probability, so there is nothing to calibrate.
  CalibrationOutcome get strumCalibration => _lastStrumCalibration;

  /// The selective-prediction verdict for the most recent strum
  /// (E14-R31, ADR 0552 D8) — READ-ONLY. The shipped policy is
  /// `SelectivePredictionPolicy.acceptAll`, so this is
  /// `SelectiveDecision.accept` in every shipped build. **Nothing on the
  /// pipeline's decision path reads it**: [_isDirectionConfirmed] still
  /// defers to [StrumPrediction.decision] exactly as before, so installing
  /// a stricter policy changes what is REPORTED, never what is emitted.
  SelectiveOutcome get strumSelectiveOutcome => _lastStrumSelectiveOutcome;

  /// The selective-prediction verdict for the current chord frame — the
  /// same read-only contract as [strumSelectiveOutcome].
  SelectiveOutcome get chordSelectiveOutcome =>
      _calibration.select(chordCalibration.calibratedConfidence);

  /// The abstention policy this pipeline was constructed with (ADR 0552
  /// D8). `SelectivePredictionPolicy.acceptAll` in every shipped build.
  SelectivePredictionPolicy get selectivePredictionPolicy =>
      _calibration.policy;

  /// The input gain the quality-aware preprocessing stage is currently
  /// applying, in dB (E14-R31, ADR 0552). Exactly `0` in every shipped
  /// build, where the stage is disabled by flag.
  double get preprocessingGainDb => _preprocessor.appliedGainDb;

  /// What the preprocessing stage did to the most recent chunk —
  /// `LivePreprocessingAdaptation.disabled` in every shipped build.
  LivePreprocessingAdaptation get preprocessingAdaptation =>
      _preprocessor.lastAdaptation;

  /// How many samples the preprocessing stage's ±1.0 safety clamp touched.
  /// A non-zero value is a fact someone must see, not a swallowed detail.
  int get preprocessingClampedSampleCount => _preprocessor.clampedSampleCount;

  /// The most recent chroma tonalness (top-3 pitch-class energy) — the value
  /// the non-guitar gate tests. Exposed for the offline real-audio probe
  /// harness (`test/tools/real_audio_probe_test.dart`).
  @visibleForTesting
  double get debugTonalness => _chroma.lastTonalness;

  /// The EMA-smoothed chord-match confidence the musical-presence gate tests.
  @visibleForTesting
  double get debugChordConfEma => _chordConfEma;

  /// Whether the musical-presence gate is currently latched — the same bit
  /// [_buildFrame]'s `showChord` reads.
  @visibleForTesting
  bool get debugChordLatched => _chordLatched;

  /// Test-only entry point (ADR 0516 §6 pt.4): applies the Schmitt trigger's
  /// rise/release compare to an EXACT [ema] value, skipping the per-frame
  /// smoothing — the pt.4 boundary is about the `>=` inclusivity of
  /// [_chordConfRise], not the smoothing, so approximating it via repeated
  /// [addChunk] calls would measure the wrong thing.
  @visibleForTesting
  void debugApplyChordConfEma(double ema) => _applyChordConfEma(ema);

  /// The strum classifier actually behind the seam (r169 wiring proof).
  @visibleForTesting
  StrumDirectionClassifier get debugStrumClassifier => _strums.debugClassifier;

  /// H3 / L2 (E14-R28, ADR 0545 D5) — every value the chord latch read on the
  /// LAST processed chord frame, or `null` before the first one.
  ///
  /// Read-only and side-effect-free: every field is a value the per-frame
  /// path had ALREADY computed, and nothing on the decision path reads the
  /// record back. It exists so the "chord latch does not engage on a
  /// Karplus–Strong chord" report can be MEASURED
  /// (`chord_latch_diagnostics_report_test.dart`) before anyone proposes a
  /// change to `chordConfRise`, `chordNoChordScore` or the margin formula.
  /// The record is BUILT ON READ from scalars the frame path already keeps,
  /// so the real-time loop allocates nothing for it (ADR 0545 D5).
  ChordLatchDiagnostics? get chordLatchDiagnostics {
    if (_chordFrameIndex == 0) return null;
    return ChordLatchDiagnostics(
      frameIndex: _chordFrameIndex - 1,
      engineTimeSec: _lastChordFrameTimeSec,
      mode: mode,
      tonalness: _chroma.lastTonalness,
      tonalGatePassed: _lastTonalGatePassed,
      winnerLabel: _chordDecoder.lastWinnerLabel,
      winnerIsNoChord: _chordDecoder.lastWinnerIsNoChord,
      winSim: _chordDecoder.lastWinSim,
      secondSim: _chordDecoder.lastSecondSim,
      margin: _chordDecoder.lastMargin,
      rawConfidence: _chordDecoder.lastRawConfidence,
      noChordScore: _chordDecoder.noChordScore,
      chordConfEma: _chordConfEma,
      chordConfRise: _chordConfRise,
      chordConfRelease: _chordConfRelease,
      belowReleaseFrames: _belowReleaseFrames,
      chordLatched: _chordLatched,
      expectedTieBreakApplied: _chordDecoder.lastExpectedTieBreakApplied,
    );
  }

  /// Per-chord-frame bookkeeping for [chordLatchDiagnostics]: three scalar
  /// stores, no allocation, no branch on the decision path.
  void _recordChordLatchDiagnostics(bool tonalGatePassed) {
    _chordFrameIndex++;
    _lastChordFrameTimeSec = _samplesSeen / sampleRate;
    _lastTonalGatePassed = tonalGatePassed;
  }

  void reset() {
    _chordFramer.reset();
    _onsetFramer.reset();
    _chordDecoder.reset();
    _tempo.reset();
    _signalQuality.reset();
    _preprocessor.reset();
    _lastChord = null;
    _lastStrumPrediction = null;
    _lastStrumCalibration = _noCalibrationArtefact;
    _lastStrumSelectiveOutcome = const SelectiveOutcome.accept();
    _chordFrameIndex = 0;
    _lastChordFrameTimeSec = 0;
    _lastTonalGatePassed = false;
    _chordConfEma = 0;
    _chordLatched = false;
    _belowReleaseFrames = 0;
    _latestStrum = null;
    _latestStrumTime = -1;
    _lastOnsetTimeSec = -1;
    _strumSeq = 0;
    _clearBar();
    _lastSlot = -1;
    _barStartSec = -1;
    _samplesSeen = 0;
    _lastEmitAt = 0;
  }
}

/// Splits a display [label] into `(root, quality)` for [ChordPrediction] —
/// the same convention `Chord.transposeLabel` uses (root = first letter plus
/// an optional accidental), except the no-chord label `'N.C.'`, which has no
/// root to isolate.
(String, String) _splitChordLabel(String label) {
  if (label == 'N.C.') return ('N.C.', '');
  var rootLen = 1;
  if (label.length > 1 && (label[1] == '#' || label[1] == 'b')) rootLen = 2;
  return (label.substring(0, rootLen), label.substring(rootLen));
}
