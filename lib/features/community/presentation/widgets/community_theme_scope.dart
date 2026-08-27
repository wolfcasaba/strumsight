import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';

/// Guarantees the design-system `ThemeExtension`s this feature's migrated
/// widgets need (`SsColorScheme`, `SsTypography`, ... — consumed by
/// `SsSurface`/`SsButton`/`SsConfirmationSheet`) are present, regardless of
/// whether the ambient app theme already provides them.
///
/// Same measured fact `GamificationThemeScope` recorded for its own feature
/// (E13-R32): the ambient `Theme` carries only whatever the host
/// `MaterialApp` supplies, never the design system's own extensions, so any
/// screen consuming DS components needs this local merge. Kept inside this
/// feature's own tree rather than widening `lib/app/` (out of this round's
/// allowed paths).
final class CommunityThemeScope extends StatelessWidget {
  const CommunityThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: mergeSsExtensions(Theme.of(context)), child: child);
  }
}

/// Adds the SS design-system theme extensions (`SsColorScheme`,
/// `SsTypography`, ...) onto [ambient] without disturbing its own.
ThemeData mergeSsExtensions(ThemeData ambient) {
  final ssTheme = ambient.brightness == Brightness.dark
      ? SsDarkTheme.data()
      : SsLightTheme.data();
  return ambient.copyWith(
    extensions: [...ambient.extensions.values, ...ssTheme.extensions.values],
  );
}

/// A [SsConfirmationSheet.show] equivalent for use inside this feature.
///
/// [SsOverlayHost.showSheetSurface] (which the real `.show()` uses) presents
/// through raw `showGeneralDialog`, whose chrome widget resolves
/// `Theme.of(context)` at a build position ABOVE wherever a locally-supplied
/// builder could inject a `Theme` override — a plain `Theme` wrap around the
/// sheet's own content cannot reach it (measured against the same
/// `library_v2` precedent this helper mirrors, `library_theme_scope.dart`).
/// Flutter's own [showModalBottomSheet], by contrast, captures the
/// `InheritedTheme`s visible at the CALLING context and re-applies them
/// inside the sheet route, so a [CommunityThemeScope] ancestor at the call
/// site (present on every migrated community screen) correctly reaches
/// [SsConfirmationSheet]'s own `SsColorScheme`/`SsTypography` lookups here.
Future<void> showCommunityConfirmationSheet(
  BuildContext context, {
  required String title,
  required String consequence,
  required String confirmLabel,
  required String cancelLabel,
  required VoidCallback onConfirm,
  bool destructive = true,
}) {
  var confirmed = false;
  void guardedOnConfirm() {
    if (confirmed) return;
    confirmed = true;
    onConfirm();
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => CommunityThemeScope(
      child: SafeArea(
        child: SsConfirmationSheet(
          title: title,
          consequence: consequence,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          onConfirm: guardedOnConfirm,
          destructive: destructive,
        ),
      ),
    ),
  );
}
