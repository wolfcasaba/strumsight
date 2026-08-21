import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/theme/app_colors.dart';
import 'package:strumsight/core/theme/app_palette.dart';

void main() {
  test('exports the pinned foundation values through the public barrel', () {
    expect(SsBreakpoints.compactMax, 599);
    expect(SsBreakpoints.mediumMax, 839);
    expect(SsBreakpoints.expandedMin, 840);
    expect(SsBreakpoints.wideMin, 1200);
    expect(SsSpacing.values, const [0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64]);
    expect(SsRadius.values, const [6, 10, 16, 20, 28, 999]);
    expect(SsMotion.durations, const [
      Duration(milliseconds: 80),
      Duration(milliseconds: 120),
      Duration(milliseconds: 200),
      Duration(milliseconds: 300),
      Duration(milliseconds: 700),
    ]);
    expect(SsMotion.forReducedMotion(true), Duration.zero);
    expect(SsSemantics.minimumInteractiveDimension, 48);
    expect(SsSemantics.maximumTextScale, 2.0);
  });

  test('theme compatibility adapter reads the legacy color sources', () {
    final dark = SsThemeExtensions.forBrightness(Brightness.dark);
    final light = SsThemeExtensions.forBrightness(Brightness.light);

    expect(dark.brand, same(AppColors.primary));
    expect(dark.brandStrong, same(AppColors.primaryDark));
    expect(dark.canvas, same(AppPalette.dark.bg));
    expect(dark.surface, same(AppPalette.dark.surface));
    expect(light.canvas, same(AppPalette.light.bg));
    expect(light.textPrimary, same(AppPalette.light.ink));
  });

  test(
    'adapter source references legacy tokens without copied color literals',
    () {
      final source = File(
        'lib/core/design_system/themes/ss_theme_extensions.dart',
      ).readAsStringSync();

      expect(source, contains('AppColors.primary'));
      expect(source, contains('AppPalette.dark'));
      expect(source, isNot(contains(RegExp(r'Color\(0x[0-9A-Fa-f]+\)'))));
    },
  );
}
