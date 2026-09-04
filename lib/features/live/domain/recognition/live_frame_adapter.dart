import '../../../../core/music/chord.dart';
import '../../../../core/music/strum.dart';
import '../../model/live_frame.dart';
import 'chord_prediction.dart';
import 'recognition_decision.dart';
import 'recognition_frame.dart';
import 'strum_prediction.dart';

/// Translates a [RecognitionFrame] to the legacy [LiveFrame] so the 22
/// existing callers (`live_screen.dart`, `live_status_bar.dart`,
/// `chord_timeline_provider.dart`, `live_practice_observation_gateway.dart`,
/// …) stay untouched (ADR 0505 D5, ADR 0116 pattern). The adapter FORDÍT,
/// nem DÖNT: it never upgrades a non-[RecognitionDecision.confirmed] chord
/// to visible "so there's something to show" — that state stays exactly
/// what today's `_chordLatched == false` produces: `current: null`.
///
/// This is the ONLY file in `domain/recognition/**` allowed to import
/// `model/live_frame.dart` (the architecture guard in
/// `test/core/architecture_dependency_test.dart` enforces this).
///
/// The live pipeline / engine is NOT rewired to this adapter in this round
/// (`live_pipeline.dart` and `engine/**` are this round's tilos zóna) — that
/// is a later round's job.
final class LiveFrameAdapter {
  const LiveFrameAdapter._();

  /// Builds the legacy [LiveFrame] the 22 callers expect from [frame],
  /// reusing [base]'s fields that [RecognitionFrame] doesn't model yet
  /// (`bar`, `bpm`, `inputLevel`, `tuningHz`, `listening`, `strumSeq`, and
  /// the ghosted `next` chord — none of those exist in the new contract
  /// this round).
  static LiveFrame toLiveFrame(RecognitionFrame frame, LiveFrame base) {
    return LiveFrame(
      current: _chordFor(frame.chord),
      next: base.next,
      latestStrum: _strumFor(frame.strum),
      bar: base.bar,
      bpm: base.bpm,
      inputLevel: base.inputLevel,
      tuningHz: base.tuningHz,
      listening: base.listening,
      strumSeq: base.strumSeq,
      latestStrumTime: frame.strum?.onsetTimeSec ?? base.latestStrumTime,
      engineTimeSec: frame.frameTimeSec,
    );
  }

  /// `confirmed` shows the chord; `candidate`, `provisional`, `uncertain`,
  /// `rejected` and `expired` all produce `null` — PRECISELY today's
  /// `_chordLatched == false` behaviour (ADR 0505 D5). Upgrading any of
  /// those five states to "show it anyway" is the exact weakening D5
  /// forbids.
  static Chord? _chordFor(ChordPrediction? chord) {
    if (chord == null || chord.decision != RecognitionDecision.confirmed) {
      return null;
    }
    return Chord(chord.label);
  }

  /// The legacy `Strum.confidence` field is non-nullable — but ADR 0505 D2
  /// forbids copying a raw probability into a confidence-shaped field, even
  /// at this legacy boundary. While [StrumPrediction.calibratedConfidence]
  /// is `null` (no measured calibration yet), the legacy confidence reports
  /// `0`, the same "we don't know anything confident" value
  /// `LiveFrame.empty` already uses.
  static Strum? _strumFor(StrumPrediction? strum) {
    if (strum == null) return null;
    return Strum(
      direction: strum.pDown >= strum.pUp
          ? StrumDirection.down
          : StrumDirection.up,
      confidence: strum.calibratedConfidence ?? 0,
    );
  }
}
