import 'package:flutter/material.dart';

import '../../domain/model/compiled_practice_target.dart';
import '../../domain/model/practice_metrics.dart';
import '../../domain/model/practice_verdict.dart';
import '../widgets/practice_chord_lane.dart';
import '../widgets/practice_feedback.dart';
import '../widgets/practice_highway.dart';

/// Mode-view for the Chord Progression practice. Composes the highway,
/// the chord lane (current + next + upcoming bar), and the verdict
/// feedback widget. The verdict and metrics are passed as explicit
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
    super.key,
  });

  final CompiledPracticeTarget target;
  final Duration playhead;
  final Duration visualOffset;
  final double width;
  final double highwayHeight;
  final PracticeVerdict? lastVerdict;
  final PracticeMetrics? metrics;
  final bool showChordHint;
  final bool leftHanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: width,
          height: highwayHeight,
          child: PracticeHighway(
            target: target,
            playhead: playhead,
            visualOffset: visualOffset,
            width: width,
            height: highwayHeight,
            strikeX: 68,
            pixelsPerSecond: 240,
            visibleSeconds: 4,
            behindSeconds: 1.5,
            leftHanded: leftHanded,
          ),
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
