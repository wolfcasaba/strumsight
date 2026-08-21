import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/theme/app_colors.dart';
import 'package:strumsight/core/theme/app_palette.dart';

void main() {
  final themes = <ThemeData>[
    SsDarkTheme.data(),
    SsLightTheme.data(),
    SsHighContrastTheme.data(),
  ];

  group('SsColorScheme', () {
    test('exposes the complete semantic contract in every theme', () {
      for (final theme in themes) {
        final colors = theme.extension<SsColorScheme>();

        expect(colors, isNotNull);
        expect(colors!.confidenceLow, isNot(colors.danger));
        expect(colors.offline, isNot(colors.danger));
        expect(colors.syncPending, isNot(colors.warning));
        expect(theme.extension<SsStateOverlays>(), isNotNull);
        expect(theme.extension<SsThemeBehavior>(), isNotNull);
      }
    });

    test('reads semantic colors from the legacy palette and color APIs', () {
      final dark = SsDarkTheme.data().extension<SsColorScheme>()!;
      final light = SsLightTheme.data().extension<SsColorScheme>()!;

      expect(dark.brand, same(AppColors.primary));
      expect(dark.canvas, same(AppPalette.dark.bg));
      expect(dark.textPrimary, same(AppPalette.dark.ink));
      expect(light.canvas, same(AppPalette.light.bg));
      expect(light.textPrimary, same(AppPalette.light.ink));
    });

    test('provides icon data for every color-independent status marker', () {
      for (final kind in SsStatusMarkerKind.values) {
        expect(SsStatusMarkers.forKind(kind).icon, isNotNull);
      }
    });

    test('copyWith preserves semantic values and lerp is endpoint stable', () {
      final colors = SsDarkTheme.data().extension<SsColorScheme>()!;

      expect(colors.copyWith(), equals(colors));
      expect(colors.lerp(colors, 0), equals(colors));
      expect(colors.lerp(colors, 1), equals(colors));
    });

    test('builds all three themes with stable value equality', () {
      expect(SsDarkTheme.data(), equals(SsDarkTheme.data()));
      expect(SsLightTheme.data(), equals(SsLightTheme.data()));
      expect(SsHighContrastTheme.data(), equals(SsHighContrastTheme.data()));
    });

    test('high contrast has measurable non-color accessibility properties', () {
      final dark = SsDarkTheme.data().extension<SsThemeBehavior>()!;
      final highContrast = SsHighContrastTheme.data()
          .extension<SsThemeBehavior>()!;
      final overlays = SsHighContrastTheme.data().extension<SsStateOverlays>()!;

      expect(highContrast.borderWidth, greaterThan(dark.borderWidth));
      expect(highContrast.focusRingWidth, greaterThan(dark.focusRingWidth));
      expect(highContrast.surfaceOpacity, 1.0);
      expect(highContrast.decorativeEffectsEnabled, isFalse);
      expect(overlays.focused.a, 1.0);
    });

    test('new semantic theme files do not introduce copied color literals', () {
      for (final path in const [
        'lib/core/design_system/foundations/ss_colors.dart',
        'lib/core/design_system/themes/ss_dark_theme.dart',
        'lib/core/design_system/themes/ss_light_theme.dart',
        'lib/core/design_system/themes/ss_high_contrast_theme.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains(RegExp(r'Color\\(0x[0-9A-Fa-f]+\\)'))));
      }
    });
  });

  testWidgets('catalog renders non-color status markers in every theme', (
    tester,
  ) async {
    final route = ComponentCatalog.createRouteForTesting(
      catalogEnabled: true,
      debugBuild: true,
    );
    await tester.pumpWidget(MaterialApp(onGenerateRoute: (_) => route));
    await tester.pumpAndSettle();

    for (final icon in const [
      Icons.dark_mode_outlined,
      Icons.light_mode_outlined,
      Icons.contrast_outlined,
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      expect(find.byType(SsStatusMarker), findsNWidgets(4));
    }
  });
}
