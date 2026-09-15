import 'package:flutter/material.dart';

import '../design_system/public.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// The six-string band ([SsStrumStrings]) as the SCORED surfaces show it: a
/// short, decorative band hung directly under the Practice highway and under
/// the Song Trainer strum lane, right below the strike line the matching
/// `StrumBurstOverlay` sparks on.
///
/// It exists so those call sites cannot drift apart. One height, one colour
/// pairing — copper down / confidence green up over the palette's muted
/// strings, the SAME two colours the burst overlay tints its sparks with — so
/// a single stroke reads as one event across the spark and the band.
///
/// ## No onset counter here
/// The Live hero is wired to the pipeline directly and hears the onset ~70 ms
/// before the direction verdict, so its band rings neutrally first and takes
/// the direction colour afterwards ([SsStrumStrings.onsetSeq]). Practice and
/// the Song Trainer are fed by `PracticeStrumFeedback`, which is emitted ONCE
/// per stroke — after the scoring pass, with the direction already decided.
/// There is no earlier signal to pass on, so [SsStrumStrings.onsetSeq] stays 0
/// and every stroke here is a directed one: the pick sweeps, and the strings
/// are excited one after the other instead of all at once.
///
/// ## Reduced motion
/// Owned by [SsStrumStrings] itself (ADR 0274 §5.1): no ticker and no ring-out,
/// while the last known direction stays readable as a static pick glyph parked
/// at the string the sweep would have ended on. Nothing to gate here — the
/// information survives the motion.
///
/// ## Deliberately decorative
/// No semantic label, so the band is excluded from the semantics tree. Both
/// surfaces already announce the stroke in words — Practice through its verdict
/// feedback, the Song Trainer through its loop feedback — and a second
/// "Strings" node beside them is a label a screen-reader user cannot act on.
/// The Live hero labels its band because there the band IS the readout.
final class StrumStringsBand extends StatelessWidget {
  const StrumStringsBand({
    super.key,
    required this.strumSeq,
    required this.isDown,
    required this.strength,
  });

  /// Monotonic per-strum counter; a rise strums the band. Never on a rebuild
  /// carrying the same value, never on first mount.
  final int strumSeq;

  /// Direction of the latest stroke; `null` (nothing detected yet) never
  /// strums the band.
  final bool? isDown;

  /// 0..1 — how far the strings swing and how hot they glow. Floored at
  /// [minStrength], exactly like `StrumBurstOverlay` floors its spark, so a
  /// dim stroke still shows its direction instead of a dead band under a
  /// visible spark.
  final double strength;

  /// Band height in logical pixels — shorter than the Live hero's 72 dp,
  /// because here the band is a companion to a lane that already owns most of
  /// the vertical budget, not the primary readout of the screen.
  static const double height = 56;

  /// Smallest swing a real stroke is ever drawn with; see [strength].
  static const double minStrength = 0.35;

  @override
  Widget build(BuildContext context) => SsStrumStrings(
    onsetSeq: 0,
    strumSeq: strumSeq,
    isDown: isDown,
    strength: strength.clamp(minStrength, 1.0),
    height: height,
    downColor: AppColors.primary,
    upColor: AppColors.confidenceHigh,
    stringColor: context.palette.muted,
  );
}
