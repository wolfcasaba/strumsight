// Accessible measure heatmap.
//
// §5.3: "Heatmap szín MELLETT label/icon/text semanticsot ad; screen-reader
// live feedback throttled." The colour is mandatory-only — every cell
// additionally exposes a label, an icon, and the average score text.

import 'package:flutter/material.dart';

import '../../application/trainer/song_trainer_result.dart';

/// Accessible measure heatmap. Each cell renders a label, an icon, AND its
/// numeric score in addition to the colour cue. The screen-reader live
/// feedback is throttled to one update per second via the parent screen.
final class MeasureHeatmap extends StatelessWidget {
  const MeasureHeatmap({
    super.key,
    required this.measureResults,
    required this.sectionResults,
    this.maxWidth = 360,
  });

  final List<SongMeasureTrainerResult> measureResults;
  final List<SongSectionTrainerResult> sectionResults;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Measure heatmap',
      container: true,
      child: Container(
        key: const Key('song-result-heatmap'),
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            for (final measure in measureResults)
              _MeasureCell(
                key: ValueKey<String>(
                  'measure-heatmap-${measure.measureIndex}',
                ),
                measureIndex: measure.measureIndex,
                score: measure.averageEventScore,
                colors: colors,
              ),
          ],
        ),
      ),
    );
  }
}

final class _MeasureCell extends StatelessWidget {
  const _MeasureCell({
    super.key,
    required this.measureIndex,
    required this.score,
    required this.colors,
  });

  final int measureIndex;
  final double score;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final tone = score >= 0.9
        ? colors.primary
        : score >= 0.7
        ? colors.tertiary
        : colors.error;
    final icon = score >= 0.9
        ? Icons.check
        : score >= 0.7
        ? Icons.tune
        : Icons.close;
    return Semantics(
      label: 'Measure ${measureIndex + 1}, score ${(score * 100).round()}%',
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: tone,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Icon(icon, size: 14, color: colors.onSurface),
            Text(
              '${(score * 100).round()}',
              style: TextStyle(
                fontSize: 10,
                color: colors.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
