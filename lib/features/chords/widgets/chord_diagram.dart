import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/public.dart';
import '../chord_shape.dart';

/// A compact open-position chord diagram: 6 strings × 4 frets, with ○/× markers
/// above the nut and dots on the fretted positions. Names a genuinely missing
/// shape instead of disappearing silently (ADR 0282 §4 spirit — a gap must be
/// visible, never a silent void). Mirrors the DRAWING **and** the spoken
/// fingering when left-handed, from the same [SsChordDiagram.readingOrder]
/// mapping (ADR 0282 §1/§2), so the two channels can never independently
/// drift. RAG chunk 014.
class ChordDiagram extends ConsumerWidget {
  const ChordDiagram({
    super.key,
    required this.label,
    this.size = 96,
    this.showLabel = true,
  });

  final String label;
  final double size;

  /// Show the chord name above the grid. Off where the name is already shown
  /// prominently elsewhere (e.g. the Live screen's huge chord).
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mirror = ref.watch(leftHandedProvider);
    final shape = ChordShapes.forLabel(label);
    if (shape == null) {
      return Semantics(
        label: l10n.chordDiagramUnavailable(label),
        excludeSemantics: true,
        child: SizedBox(
          width: size,
          height: size * 1.05 + (showLabel ? 17 : 0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.music_off,
                  size: 20,
                  color: Theme.of(context).hintColor,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.chordDiagramUnavailable(label),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // Painter-only content is invisible to a screen reader — speak the
    // fingering, reordered by the SAME mapping the grid painter uses to
    // position each string, so a mirrored drawing always mirrors its
    // spoken order too (round 88; reversed for left-handed since ADR 0282).
    final order = SsChordDiagram.readingOrder(shape.frets, mirrored: mirror);
    final fingering = order.map((f) => f < 0 ? 'x' : '$f').join(' ');
    return Semantics(
      label: l10n.chordDiagramSemantics(label, fingering),
      excludeSemantics: true,
      child: SsChordDiagram(
        frets: shape.frets,
        baseFret: shape.baseFret,
        baseFretLabel: shape.baseFret > 0 ? '${shape.baseFret + 1}fr' : null,
        mirrored: mirror,
        label: showLabel ? label : null,
        size: size,
        ink: onSurface,
        dotColor: AppColors.primary,
      ),
    );
  }
}
