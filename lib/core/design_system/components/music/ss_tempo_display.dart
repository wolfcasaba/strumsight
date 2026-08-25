import 'package:flutter/material.dart';

/// The Stage status-header slot's tempo/tuning readout — "96 BPM · A=440 ·
/// Capo 2". Purely presentational: every string arrives pre-formatted from
/// the caller (l10n lives in the feature layer), so this stays reusable
/// across every Stage mode (Live, Practice, Song, …).
final class SsTempoDisplay extends StatelessWidget {
  const SsTempoDisplay({
    super.key,
    required this.bpm,
    required this.tuningLabel,
    required this.color,
    this.capoLabel,
    this.textAlign = TextAlign.end,
  });

  /// Detected tempo in BPM (rounded for display by the caller if desired).
  final double bpm;

  /// Pre-formatted tuning reference, e.g. "A=440".
  final String tuningLabel;

  /// Pre-formatted capo annotation, e.g. "Capo 2" — omitted when null.
  final String? capoLabel;

  final Color color;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final capo = capoLabel;
    final text =
        '${bpm.round()} BPM · $tuningLabel${capo != null ? ' · $capo' : ''}';
    return Text(
      text,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 11,
        letterSpacing: 0.5,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
