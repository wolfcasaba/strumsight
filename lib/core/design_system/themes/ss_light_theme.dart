import 'package:flutter/material.dart';

import '../foundations/ss_colors.dart';
import 'ss_theme_extensions.dart';

abstract final class SsLightTheme {
  static ThemeData data() {
    final legacy = SsThemeExtensions.legacyThemeForBrightness(Brightness.light);
    final colors = SsColorScheme.forBrightness(Brightness.light);
    return legacy.copyWith(
      extensions: [
        ...legacy.extensions.values,
        colors,
        SsStateOverlays.fromColors(colors, highContrast: false),
        const SsThemeBehavior(
          borderWidth: 1,
          focusRingWidth: 2,
          surfaceOpacity: 1,
          decorativeEffectsEnabled: true,
        ),
      ],
    );
  }
}
