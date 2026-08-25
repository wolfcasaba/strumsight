import 'package:flutter/material.dart';

/// The Stage feedback slot's microphone input-level readout: a small bar
/// meter plus — when the level is weak WHILE actively listening — an
/// icon+text warning, never colour alone (ADR 0278 §2, ADR 0280 §4).
///
/// [weakThreshold] is a PRESENTATION constant: `level` is the engine's raw
/// 0..1 microphone level, not a recognition confidence, so this threshold
/// only decides what the UI shows and never touches recognition (Ch13 §0.0
/// R9 — the detection thresholds stay in the recognition layer, ADR 0278
/// §5).
final class SsSignalQualityIndicator extends StatelessWidget {
  const SsSignalQualityIndicator({
    super.key,
    required this.level,
    required this.listening,
    required this.activeColor,
    required this.trackColor,
    required this.warningColor,
    this.levelSemanticLabel,
    this.weakLabel,
    this.weakThreshold = defaultWeakThreshold,
    this.bars = 5,
    this.barHeight = 12,
  });

  /// The default weak-signal threshold on the raw 0..1 mic level. Tuned so a
  /// quiet room (not silence) still reads as adequate; retune here only —
  /// never in `lib/features/live/engine/dsp/**` (that tree is DSP, not UI).
  static const double defaultWeakThreshold = 0.12;

  /// Raw microphone input level, 0..1.
  final double level;

  /// Whether the engine is actively listening — a weak reading while NOT
  /// listening (e.g. paused) is expected, not a warning.
  final bool listening;

  final Color activeColor;
  final Color trackColor;
  final Color warningColor;

  /// Accessible label for the bar meter itself (e.g. "Input level").
  final String? levelSemanticLabel;

  /// Shown next to a warning icon when the signal is weak; the warning row
  /// is omitted entirely when null.
  final String? weakLabel;

  final double weakThreshold;
  final int bars;
  final double barHeight;

  bool get isWeak => listening && level < weakThreshold;

  @override
  Widget build(BuildContext context) {
    final clamped = level.clamp(0.0, 1.0);
    final meter = Semantics(
      label: levelSemanticLabel,
      value: levelSemanticLabel == null ? null : '${(clamped * 100).round()}%',
      excludeSemantics: levelSemanticLabel != null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars; i++) ...[
            Container(
              width: 3,
              height: barHeight * (0.4 + 0.6 * (i + 1) / bars),
              decoration: BoxDecoration(
                color: (i + 1) / bars <= clamped ? activeColor : trackColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            if (i < bars - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );

    final label = weakLabel;
    if (!isWeak || label == null) return meter;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        meter,
        const SizedBox(width: 8),
        Icon(Icons.mic_off_outlined, size: 14, color: warningColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: warningColor,
            ),
          ),
        ),
      ],
    );
  }
}
