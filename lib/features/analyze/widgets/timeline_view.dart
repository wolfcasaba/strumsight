import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../live/widgets/strum_arrow.dart';
import '../model/analyze_result.dart';

/// Renders an [AnalyzeResult] as summary chips + a scrollable list of chord
/// segments (each with its time range and the strum arrows within it). Shared
/// by the Analyze result screen and the Library session detail.
class TimelineView extends StatelessWidget {
  const TimelineView({super.key, required this.result});

  final AnalyzeResult result;

  static String fmtTime(double seconds) {
    final s = seconds.floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(text: fmtTime(result.durationSec)),
            if (result.bpm > 0) _Chip(text: '${result.bpm.round()} BPM'),
            _Chip(
              text: l10n.analyzeStrumsSummary(result.downCount, result.upCount),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: result.chords.isEmpty
              ? Center(
                  child: Text(
                    l10n.analyzeStrumsSummary(
                        result.downCount, result.upCount),
                    style: TextStyle(color: palette.muted),
                  ),
                )
              : ListView.separated(
                  itemCount: result.chords.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _ChordRow(chord: result.chords[i], strums: result.strums),
                ),
        ),
      ],
    );
  }
}

class _ChordRow extends StatelessWidget {
  const _ChordRow({required this.chord, required this.strums});

  final TimelineChord chord;
  final List<TimelineStrum> strums;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final inSegment = strums
        .where((s) => s.timeSec >= chord.startSec && s.timeSec < chord.endSec)
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              chord.label,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: palette.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${TimelineView.fmtTime(chord.startSec)} – '
                  '${TimelineView.fmtTime(chord.endSec)}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: palette.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (inSegment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final s in inSegment)
                        StrumArrow(
                          direction: s.direction,
                          confidence: s.confidence,
                          size: 16,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: palette.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
