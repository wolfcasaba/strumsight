import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';

/// Feature-layer wiring over the design system's [SsTunerGauge] (Ch13 §9.9
/// migration): computes the spoken/visible cents-direction text (ADR 0280
/// §3) and the in-tune colour, both of which need l10n/theme access the
/// design-system component deliberately does not have. Turns green when the
/// note is in tune.
class CentsGauge extends StatelessWidget {
  const CentsGauge({
    super.key,
    required this.cents,
    required this.inTune,
    this.width = 300,
    this.height = 80,
  });

  final double cents;
  final bool inTune;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // The painter is invisible to a screen reader — speak the same fact the
    // triangle shows: how far off and which way (round 88).
    final l10n = AppLocalizations.of(context);
    final rounded = cents.abs().round();
    final label = inTune
        ? l10n.tunerInTune
        : (cents >= 0
              ? l10n.tunerCentsSharp(rounded)
              : l10n.tunerCentsFlat(rounded));
    return SsTunerGauge(
      cents: cents,
      hasSignal: true,
      markerColor: inTune
          ? AppColors.successOn(Theme.of(context).brightness)
          : AppColors.primary,
      trackColor: palette.track,
      tickColor: palette.muted,
      semanticLabel: label,
      width: width,
      height: height,
    );
  }
}
