import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';

/// Guarantees the design-system `ThemeExtension`s this feature's migrated
/// widgets need (`SsColorScheme`, `SsTypography`, ... — consumed by
/// `SsSurface`/`SsButton`/`SsStatusBadge`) are present, regardless of
/// whether the ambient app theme already provides them.
///
/// Measured (2026-08-27, same fact `progress_theme_scope.dart` and
/// `vision_theme_scope.dart` recorded for their own features): the ambient
/// `Theme` carries only whatever the host `MaterialApp` supplies, never the
/// design system's own extensions, so any screen consuming DS components
/// needs this local merge. Kept inside this feature's own tree rather than
/// widening `lib/app/` (out of this round's allowed paths).
final class GamificationThemeScope extends StatelessWidget {
  const GamificationThemeScope({super.key, required this.child});

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
