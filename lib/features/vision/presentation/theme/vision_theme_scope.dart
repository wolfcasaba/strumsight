import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';

/// Guarantees the design-system `ThemeExtension`s the Result screen's
/// components need (`SsColorScheme`, `SsTypography`, ... — consumed by
/// `SsMetricCard`, `SsInsightCard`, `SsCoachActionCard`, `SsStatusBadge`) are
/// present, regardless of whether the ambient app theme
/// (`core/theme/app_theme.dart`) already provides them.
///
/// Measured (2026-08-27, same fact `library_theme_scope.dart` recorded for
/// its own feature): `AppTheme` carries only `AppPalette`, never the design
/// system's own extensions, so any screen consuming those DS components
/// needs this local merge. Kept inside this feature's own tree rather than
/// widening `lib/app/` (out of this round's allowed paths).
final class VisionThemeScope extends StatelessWidget {
  const VisionThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ambient = Theme.of(context);
    final ssTheme = ambient.brightness == Brightness.dark
        ? SsDarkTheme.data()
        : SsLightTheme.data();
    return Theme(
      data: ambient.copyWith(
        extensions: [
          ...ambient.extensions.values,
          ...ssTheme.extensions.values,
        ],
      ),
      child: child,
    );
  }
}
