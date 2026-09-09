import 'package:meta/meta.dart';

import 'recognition_mode.dart';

/// A read-only, per-chord-frame snapshot of every value the musical-presence
/// chord latch reads (H3 / L2 diagnostics, E14-R28, ADR 0545 D5).
///
/// This type exists so the latch can be MEASURED without retuning it. It adds
/// no decision, no threshold and no state: `LivePipeline` fills it from values
/// it has already computed for the frame, and nothing in the production path
/// reads it back. It is developer diagnostics only and is never rendered to a
/// user, so it carries no localized text (AGENTS.md §5 applies to what the
/// screen claims, not to a debug table).
///
/// The three H3 suspects the HANDOFF names are exactly the fields below:
///   1. the raw match confidence formula `winSim * (0.5 + 2 * margin)`
///      ([winSim], [margin], [rawConfidence]);
///   2. the EMA + Schmitt trigger ([chordConfEma], [chordConfRise],
///      [chordConfRelease], [chordLatched], [belowReleaseFrames]);
///   3. the no-chord floor the winner has to beat ([noChordScore],
///      [winnerIsNoChord], [winSimOverNoChordFloor]).
@immutable
class ChordLatchDiagnostics {
  const ChordLatchDiagnostics({
    required this.frameIndex,
    required this.engineTimeSec,
    required this.mode,
    required this.tonalness,
    required this.tonalGatePassed,
    required this.winnerLabel,
    required this.winnerIsNoChord,
    required this.winSim,
    required this.secondSim,
    required this.margin,
    required this.rawConfidence,
    required this.noChordScore,
    required this.chordConfEma,
    required this.chordConfRise,
    required this.chordConfRelease,
    required this.belowReleaseFrames,
    required this.chordLatched,
    required this.expectedTieBreakApplied,
  });

  /// Zero-based index of the chord frame (the ~93 ms NNLS hop), not the
  /// ~66 ms emission frame.
  final int frameIndex;

  /// The pipeline's own sample-clock instant when this chord frame was
  /// processed (seconds from session start).
  final double engineTimeSec;

  /// Which regime the producing engine was constructed in (ADR 0544 D5): a
  /// measurement taken in `guided` is not comparable to one taken in `free`.
  final RecognitionMode mode;

  /// Chroma tonalness of this frame (top-3 pitch-class energy share).
  final double tonalness;

  /// Whether [tonalness] cleared `DspConfig.chordMinTonalness`. When false the
  /// frame was fed to the decoder as GATED silence, so [winSim] and friends
  /// describe the silent frame, not the audio.
  final bool tonalGatePassed;

  /// The label the decoder reported for this frame, or `N.C.` when the path
  /// sat in the no-chord state.
  final String winnerLabel;

  /// Whether the decoded state was the no-chord state (the reason the
  /// pipeline saw a `null` match).
  final bool winnerIsNoChord;

  /// Raw dictionary similarity of the reported state for THIS frame (`0..1`),
  /// the `best` of `chord_matcher.dart`'s formula. Zero when the no-chord
  /// state won (the no-chord profile has no similarity — see [noChordScore]).
  final double winSim;

  /// Raw similarity of the best competing real chord (`0..1`) — the `second`
  /// of the same formula.
  final double secondSim;

  /// `(winSim - secondSim) / winSim`, the decisiveness term. Zero when
  /// [winSim] is zero.
  final double margin;

  /// `winSim * (0.5 + 2 * margin)` clamped to `0..1` — the number that is fed
  /// into the EMA, i.e. the value the H3 hypothesis says collapses to
  /// `0.5 * winSim` when two templates are near-tied.
  final double rawConfidence;

  /// The constant no-chord floor score (`DspConfig.chordNoChordScore`) every
  /// real chord has to beat to be decoded at all.
  final double noChordScore;

  /// `winSim - noChordScore` — positive means this frame's winning template
  /// out-scored the N.C. floor on raw evidence. The single number that says
  /// whether the frame failed at the FLOOR or at the LATCH.
  double get winSimOverNoChordFloor => winSim - noChordScore;

  /// The EMA-smoothed [rawConfidence] after this frame.
  final double chordConfEma;

  /// The Schmitt trigger's rise threshold in force for this pipeline.
  final double chordConfRise;

  /// The Schmitt trigger's release threshold in force for this pipeline.
  final double chordConfRelease;

  /// Consecutive frames [chordConfEma] has been below [chordConfRelease]
  /// while latched (the release debounce counter).
  final int belowReleaseFrames;

  /// Whether the latch is engaged after this frame — the same bit
  /// `LiveFrame.current` is gated on.
  final bool chordLatched;

  /// Whether the guided-mode expected-chord TIE-BREAK changed the reported
  /// label on this frame (ADR 0544 D3). Always false in
  /// [RecognitionMode.free] — that is the fact the free-mode guard test
  /// pins.
  final bool expectedTieBreakApplied;

  /// `chordConfEma - chordConfRise` — negative means the latch could not
  /// engage this frame, and the magnitude says by how much.
  double get emaOverRise => chordConfEma - chordConfRise;

  /// Column header matching [toCsvRow], so a measurement run can be pasted
  /// straight into a spreadsheet.
  static const String csvHeader =
      'frame,timeSec,mode,tonalness,tonalGate,label,isNC,winSim,secondSim,'
      'margin,rawConf,ncFloor,winSimOverNC,ema,rise,release,emaOverRise,'
      'belowRelease,latched,tieBreak';

  /// One fixed-precision row for the diagnostics table (see [csvHeader]).
  String toCsvRow() => [
    '$frameIndex',
    engineTimeSec.toStringAsFixed(3),
    mode.name,
    tonalness.toStringAsFixed(4),
    '$tonalGatePassed',
    winnerLabel,
    '$winnerIsNoChord',
    winSim.toStringAsFixed(4),
    secondSim.toStringAsFixed(4),
    margin.toStringAsFixed(4),
    rawConfidence.toStringAsFixed(4),
    noChordScore.toStringAsFixed(4),
    winSimOverNoChordFloor.toStringAsFixed(4),
    chordConfEma.toStringAsFixed(4),
    chordConfRise.toStringAsFixed(4),
    chordConfRelease.toStringAsFixed(4),
    emaOverRise.toStringAsFixed(4),
    '$belowReleaseFrames',
    '$chordLatched',
    '$expectedTieBreakApplied',
  ].join(',');
}
