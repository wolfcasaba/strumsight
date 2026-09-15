import 'package:flutter/material.dart';

import '../../../../core/widgets/strum_burst_overlay.dart';
import '../../../../core/widgets/strum_strings_band.dart';
import '../../domain/model/compiled_practice_target.dart';
import '../../domain/model/practice_metrics.dart';
import '../../domain/model/practice_verdict.dart';
import '../widgets/practice_chord_lane.dart';
import '../widgets/practice_feedback.dart';
import '../widgets/practice_highway.dart';

/// Mode-view for the Chord Progression practice. Composes the highway, the
/// strings band that rings under it, the chord lane (current + next +
/// upcoming bar), and the verdict feedback widget. The verdict and metrics
/// are passed as explicit
/// constructor params (R10) — the host wires them in, but the widget
/// renders correctly in isolation.
class ChordProgressionView extends StatelessWidget {
  const ChordProgressionView({
    required this.target,
    required this.playhead,
    required this.visualOffset,
    required this.width,
    required this.highwayHeight,
    required this.lastVerdict,
    required this.metrics,
    required this.showChordHint,
    this.leftHanded = false,
    this.strumSeq = 0,
    this.strumIsDown,
    this.strumStrength = 0,
    super.key,
  });

  /// Strike-line distance from the lane's leading edge (mirrored when
  /// [leftHanded]); the spark burst is centred on it.
  static const double strikeX = 68;

  final CompiledPracticeTarget target;
  final Duration playhead;
  final Duration visualOffset;
  final double width;
  final double highwayHeight;
  final PracticeVerdict? lastVerdict;
  final PracticeMetrics? metrics;
  final bool showChordHint;
  final bool leftHanded;

  /// Per-strum feedback trigger (chunk 016b P0): a rise fires a burst at the
  /// strike line AND strums the band below it, in the observed stroke's
  /// direction and sized by [strumStrength]. `strumIsDown == null` — a stroke
  /// whose direction is unknown — never bursts and never rings the band.
  final int strumSeq;
  final bool? strumIsDown;
  final double strumStrength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StrumBurstOverlay(
          strumSeq: strumSeq,
          isDown: strumIsDown,
          strength: strumStrength,
          centerOf: (size) => Offset(
            leftHanded ? size.width - strikeX : strikeX,
            size.height / 2,
          ),
          child: SizedBox(
            width: width,
            height: highwayHeight,
            child: PracticeHighway(
              target: target,
              playhead: playhead,
              visualOffset: visualOffset,
              width: width,
              height: highwayHeight,
              strikeX: strikeX,
              pixelsPerSecond: 240,
              visibleSeconds: 4,
              behindSeconds: 1.5,
              leftHanded: leftHanded,
            ),
          ),
        ),
        // The stroke that just sparked at the strike line rings on through
        // the strings right below it: same counter, same direction, same
        // strength, so the spark and the band are one event, not two.
        const SizedBox(height: 8),
        StrumStringsBand(
          strumSeq: strumSeq,
          isDown: strumIsDown,
          strength: strumStrength,
        ),
        const SizedBox(height: 12),
        PracticeChordLane(
          target: target,
          playhead: playhead,
          verdict: lastVerdict,
          showHint: showChordHint,
        ),
        const SizedBox(height: 12),
        PracticeFeedback(verdict: lastVerdict, metrics: metrics),
      ],
    );
  }
}
