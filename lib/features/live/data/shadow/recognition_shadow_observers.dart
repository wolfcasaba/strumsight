import '../../../../core/music/strum.dart';
import '../../domain/recognition/chord_prediction.dart';
import '../../domain/recognition/recognition_decision.dart';
import '../../domain/recognition/recognition_mode.dart';
import '../../domain/recognition/strum_prediction.dart';
import '../../engine/recognition_shadow_observer.dart';
import '../../model/live_frame.dart';
import 'chord_shadow_candidate.dart';
import 'recognition_shadow_recorder.dart';
import 'shadow_metrics.dart';

/// Fans one seam call out to several observers (E14-R23, ADR 0548 D2).
///
/// `LivePipeline` accepts exactly ONE observer; the strum band and the chord
/// band are separately gated, so they are separate observers and this joins
/// them. The list is fixed at construction — nothing subscribes at runtime,
/// so the per-frame cost is a bounded `for` over a `const`-sized list.
///
/// No `try`/`catch`: a throwing observer must fail loudly (AGENTS.md's
/// silent-no-op rule, restated by the seam's own contract).
class CompositeRecognitionShadowObserver implements RecognitionShadowObserver {
  CompositeRecognitionShadowObserver(List<RecognitionShadowObserver> observers)
    : _observers = List<RecognitionShadowObserver>.unmodifiable(observers);

  final List<RecognitionShadowObserver> _observers;

  @override
  void onRecognitionFrame({
    required RecognitionMode mode,
    required LiveFrame frame,
    required ChordPrediction? chord,
    required StrumPrediction? strum,
  }) {
    for (final observer in _observers) {
      observer.onRecognitionFrame(
        mode: mode,
        frame: frame,
        chord: chord,
        strum: strum,
      );
    }
  }
}

/// The STRUM-band shadow consumer (SDD Ch14 Kör 23, ADR 0548).
///
/// **What it compares, precisely** — this matters more than the round's
/// headline, because the seam decides it:
///
/// * the CANDIDATE is the strum model's own verdict for the onset, i.e. the
///   `argmax` of [StrumPrediction.pDown]/[StrumPrediction.pUp]/
///   [StrumPrediction.pNoStrum], with the contract's own abstention rule
///   ([StrumPrediction.decision] `== uncertain`) applied;
/// * PRODUCTION is what the pipeline actually PUBLISHED for that onset —
///   `frame.latestStrum` on the frame where [LiveFrame.strumSeq] advances.
///
/// So this measures raw model verdict vs. shipped output: how often the
/// direction gate, the no-strum suppression and the emit cadence change the
/// answer the model gave. It does NOT run a second inference — the seam
/// hands over OUTPUTS, not features, and the round's plan explicitly forbids
/// a second FFT on the live path. Comparing a genuinely different candidate
/// network against production needs a FEATURE tap in `live_pipeline.dart`;
/// that patch is written down in the round report and is not this package's
/// to apply. Saying so is the honest version of "shadow mode": what is here
/// is measured, what is not is named.
///
/// The observer NEVER writes to [frame], the predictions, or any pipeline
/// state: its only side effect is the recorder it was handed.
class StrumShadowObserver implements RecognitionShadowObserver {
  StrumShadowObserver(this._recorder);

  final RecognitionShadowRecorder _recorder;

  /// The last prediction instance already recorded. The pipeline HOLDS a
  /// verdict across frames, so identity de-duplication is what keeps one
  /// strum from being counted ten times.
  StrumPrediction? _lastRecorded;

  /// The strum sequence number at the previous frame — used to tell "the
  /// pipeline published a NEW strum" from "it is still showing the old one".
  int _lastStrumSeq = -1;

  @override
  void onRecognitionFrame({
    required RecognitionMode mode,
    required LiveFrame frame,
    required ChordPrediction? chord,
    required StrumPrediction? strum,
  }) {
    _recorder.noteStrumFrame();

    final publishedNewStrum = frame.strumSeq != _lastStrumSeq;
    _lastStrumSeq = frame.strumSeq;

    if (strum == null) {
      // The heuristic ladder is running: there is no model verdict at all.
      // Counted as UNAVAILABLE, never as an abstention — "the candidate was
      // not there" and "the candidate declined" are different findings.
      _recorder.noteStrumCandidateUnavailable();
      return;
    }
    if (identical(strum, _lastRecorded)) return;
    _lastRecorded = strum;

    final candidate = _candidateVerdict(strum);
    final production = publishedNewStrum
        ? _verdictOf(frame)
        : null; // production published nothing new for this onset
    _recorder.recordStrum(
      StrumShadowSample(
        onsetTimeSec: strum.onsetTimeSec,
        production: production,
        candidate: candidate,
        agreement: _agreementOf(production, candidate),
        latency: ShadowLatencyBucket.forSeconds(
          _latencySeconds(strum),
        ),
      ),
    );
  }

  /// `null` when the model declines: either the no-strum class wins, or the
  /// down/up margin is inside the contract's uncertainty band.
  static ShadowStrumVerdict? _candidateVerdict(StrumPrediction strum) {
    if (strum.decision == RecognitionDecision.uncertain) return null;
    if (strum.pNoStrum >= strum.pDown && strum.pNoStrum >= strum.pUp) {
      return null;
    }
    return strum.pDown >= strum.pUp
        ? ShadowStrumVerdict.down
        : ShadowStrumVerdict.up;
  }

  static ShadowStrumVerdict? _verdictOf(LiveFrame frame) =>
      switch (frame.latestStrum?.direction) {
        null => null,
        StrumDirection.down => ShadowStrumVerdict.down,
        StrumDirection.up => ShadowStrumVerdict.up,
      };

  /// `null` when either clock is unstamped (`-1` / non-finite) or the
  /// difference is negative — an unusable latency stays unknown rather than
  /// being clamped to a plausible-looking zero.
  static double? _latencySeconds(StrumPrediction strum) {
    final onset = strum.onsetTimeSec;
    final verdict = strum.verdictTimeSec;
    if (!onset.isFinite || !verdict.isFinite) return null;
    if (onset < 0 || verdict < 0) return null;
    final delta = verdict - onset;
    return delta < 0 ? null : delta;
  }

  static ShadowAgreement _agreementOf(
    ShadowStrumVerdict? production,
    ShadowStrumVerdict? candidate,
  ) {
    if (production == null && candidate == null) {
      return ShadowAgreement.bothAbstained;
    }
    if (candidate == null) return ShadowAgreement.candidateAbstained;
    if (production == null) return ShadowAgreement.productionAbstained;
    return production == candidate
        ? ShadowAgreement.agreed
        : ShadowAgreement.disagreed;
  }
}

/// The CHORD-band shadow consumer (SDD Ch14 Kör 26, ADR 0549).
///
/// Pairs the label production PUBLISHED on the frame (`frame.current`, i.e.
/// the NNLS-chroma → dictionary → Viterbi path after its latch) with the
/// chord CRNN's verdict at the same instant, and folds both into the
/// root/quality agreement matrix.
///
/// **N.C. handling (ADR 0549 D3):** a frame where production published no
/// chord is recorded as [ShadowChordClass.noChord], not skipped. That
/// deliberately conflates "silence" with "production is not confident enough
/// to latch" — because those are the same thing to the user looking at the
/// screen, and separating them would need a chord-confidence field the
/// published frame does not carry. The conflation is recorded here and in
/// the ADR rather than hidden in a rate.
class ChordShadowObserver implements RecognitionShadowObserver {
  ChordShadowObserver({
    required RecognitionShadowRecorder recorder,
    required ChordShadowCandidateSource candidate,
  }) : _recorder = recorder,
       _candidate = candidate;

  final RecognitionShadowRecorder _recorder;
  final ChordShadowCandidateSource _candidate;

  @override
  void onRecognitionFrame({
    required RecognitionMode mode,
    required LiveFrame frame,
    required ChordPrediction? chord,
    required StrumPrediction? strum,
  }) {
    _recorder.noteChordFrame();
    final timeSec = frame.engineTimeSec;
    final verdict = _candidate.verdictAtSeconds(timeSec);
    if (verdict == null) {
      _recorder.noteChordCandidateUnavailable();
      return;
    }
    final production = ShadowChordClass.parse(frame.current?.label);
    final candidateClass = ShadowChordClass.parse(verdict.label);
    _recorder.recordChord(
      ChordShadowSample(
        timeSec: timeSec,
        production: production,
        candidate: candidateClass,
        agreement: chordAgreementOf(production, candidateClass),
      ),
    );
  }

  /// Both sides always commit to a CLASS here (N.C. is a class), so the only
  /// two outcomes are agreement and disagreement — an abstention on the
  /// chord band shows up as `N.C.`, which the aggregate counts separately.
  static ShadowAgreement chordAgreementOf(
    ShadowChordClass production,
    ShadowChordClass candidate,
  ) {
    return production == candidate
        ? ShadowAgreement.agreed
        : ShadowAgreement.disagreed;
  }
}
