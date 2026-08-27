import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';

/// Guarantees the design-system `ThemeExtension`s this feature's components
/// need (`SsColorScheme`, `SsThemeBehavior`, ... — consumed by
/// `SsStatusBadge`, `SsEmptyState`, `SsConfirmationSheet`) are present,
/// regardless of whether the ambient app theme (`core/theme/app_theme.dart`)
/// already provides them.
///
/// MEASURED (2026-08-27, `grep -rl` across `lib/features/`): no other
/// feature screen consumes any of those three components today, so
/// `AppTheme` has never needed to carry their extensions — there is no
/// existing app-wide wiring to reuse. Merging locally here keeps the fix
/// inside this feature's own tree rather than widening `lib/app/` (out of
/// this round's allowed paths).
final class LibraryThemeScope extends StatelessWidget {
  const LibraryThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: mergeSsExtensions(Theme.of(context)), child: child);
  }
}

/// Adds the SS design-system theme extensions (`SsColorScheme`,
/// `SsThemeBehavior`, ...) onto [ambient] without disturbing its own
/// (e.g. `AppPalette`).
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
/// through raw `showGeneralDialog`, whose chrome widget
/// (`_SsBottomSheetSurface`) resolves `Theme.of(context)` at a build
/// position ABOVE wherever a locally-supplied builder could inject a
/// `Theme` override — a plain `Theme` wrap around the sheet's own content
/// cannot reach it (MEASURED: still throws under `AppTheme`, 2026-08-27).
/// Flutter's own [showModalBottomSheet], by contrast, captures the
/// `InheritedTheme`s visible at the CALLING context and re-applies them
/// inside the sheet route, so a [LibraryThemeScope] ancestor at the call
/// site (present on every `library_v2` screen) correctly reaches
/// [SsConfirmationSheet]'s own `SsColorScheme`/`SsTypography` lookups here.
/// The trade-off is the sheet's chrome: Material's default modal-bottom-
/// sheet surface, not `SsOverlayHost`'s custom elevation/side-sheet
/// adaptation — [SsConfirmationSheet]'s content, consequence-first copy and
/// exactly-once confirm guard (mirrored below) are unchanged.
Future<void> showLibraryConfirmationSheet(
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
    builder: (sheetContext) => LibraryThemeScope(
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
