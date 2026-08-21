import 'package:flutter/material.dart';

import '../foundations/ss_colors.dart';
import 'ss_theme_extensions.dart';

abstract final class SsDarkTheme {
  static ThemeData data() => build(highContrast: false);

  static ThemeData build({required bool highContrast}) {
    final legacy = SsThemeExtensions.legacyThemeForBrightness(Brightness.dark);
    final colors = SsColorScheme.forBrightness(
      Brightness.dark,
      highContrast: highContrast,
    );
    return legacy.copyWith(
      extensions: [
        ...legacy.extensions.values,
        colors,
        SsStateOverlays.fromColors(colors, highContrast: highContrast),
        SsThemeBehavior(
          borderWidth: highContrast ? 2 : 1,
          focusRingWidth: highContrast ? 4 : 2,
          surfaceOpacity: 1,
          decorativeEffectsEnabled: !highContrast,
        ),
      ],
    );
  }
}
