import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../chords/widgets/chord_diagram.dart';
import '../model/chord_event.dart';
import '../model/strum.dart';
import 'strum_arrow.dart';

/// One card in the [ChordTimeline] filmstrip, rendered at a size *tier*.
///
/// The hero (newest) card is large — chord label + mini fingering diagram +
/// big ↓/↑ [StrumArrow] + a confidence ramp bar, sitting on a surgical
/// frosted / copper-tinted glass surface. History cards are smaller, flatter
/// and carry just the label + their strum direction.
///
/// The card is self-contained: it renders the label at concert pitch minus the
/// [capo] (exactly as the rest of the Live screen), and it never manages its
/// own opacity/blur recede — the parent [ChordTimeline] owns that so the card
/// stays a pure function of [event]/[isHero]/[scale].
class ChordTimelineCard extends StatelessWidget {
  const ChordTimelineCard({
    super.key,
    required this.event,
    required this.isHero,
    required this.capo,
    this.scale = 1.0,
  });

  /// The recognised chord + strum this card represents (concert pitch).
  final ChordEvent event;

  /// Hero = the newest, largest card (the only one with glass + diagram).
  final bool isHero;

  /// Capo fret — the label is shown transposed by `-capo` (shape the player
  /// frets), matching the rest of the Live screen. The event stays concert.
  final int capo;

  /// Size multiplier for history cards (1.0 = nearest the hero, shrinking to
  /// the left). Ignored for the hero, which uses its own large dimensions.
  final double scale;

  @override
  Widget build(BuildContext context) {
    return isHero ? _buildHero(context) : _buildHistory(context);
  }

  String get _label => event.chord.transposed(-capo).label;

  /// Localized "down/up N%" for the ↓/↑ arrow — the moat output must be
  /// announced to screen readers, not left as a bare CustomPaint.
  String _dirLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dir = event.direction == StrumDirection.down
        ? l10n.strumDown
        : l10n.strumUp;
    return '$dir ${(event.confidence.clamp(0.0, 1.0) * 100).round()}%';
  }

  // --- Hero -----------------------------------------------------------------

  Widget _buildHero(BuildContext context) {
    final palette = context.palette;
    final brightness = Theme.of(context).brightness;
    final confColor = AppColors.confidence(event.confidence, brightness);

    // RepaintBoundary: the hero carries a BackdropFilter (a saveLayer-class
    // blur) and a ChordDiagram CustomPaint — isolate them so the frame-rate
    // rebuilds of the surrounding timeline don't force them to re-raster.
    return RepaintBoundary(
      child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            // Surgical copper-tinted glass — hero only.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.18),
                palette.surface.withValues(alpha: 0.28),
              ],
            ),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.20),
                blurRadius: 32,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChordDiagram(label: _label, size: 78, showLabel: false),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _label,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 104,
                    height: 0.9,
                    letterSpacing: -3,
                    color: palette.ink,
                  ),
                ),
              ),
              if (event.direction != null) ...[
                const SizedBox(height: 10),
                StrumArrow(
                  direction: event.direction!,
                  confidence: event.confidence,
                  size: 72,
                  glow: true,
                  semanticLabel: _dirLabel(context),
                ),
                const SizedBox(height: 12),
                _ConfidenceBar(
                  confidence: event.confidence,
                  color: confColor,
                  track: palette.track,
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  // --- History --------------------------------------------------------------

  Widget _buildHistory(BuildContext context) {
    final palette = context.palette;
    final labelSize = 46.0 * scale;
    final arrowSize = 30.0 * scale;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0 * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _label,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w700,
                fontSize: labelSize,
                height: 0.9,
                letterSpacing: -1,
                color: palette.muted,
              ),
            ),
          ),
          SizedBox(height: 6 * scale),
          SizedBox(
            height: arrowSize * 1.2,
            child: event.direction != null
                ? StrumArrow(
                    direction: event.direction!,
                    confidence: event.confidence,
                    size: arrowSize,
                    semanticLabel: _dirLabel(context),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// A compact confidence ramp bar (fill length + colour communicate the score)
/// with a trailing percentage — the hero's "▓▓▓▓░ 82%" indicator.
class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({
    required this.confidence,
    required this.color,
    required this.track,
  });

  final double confidence;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final pct = (confidence.clamp(0.0, 1.0) * 100).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 96,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: confidence.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: track,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$pct%',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: color,
          ),
        ),
      ],
    );
  }
}
