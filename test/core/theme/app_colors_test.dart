import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/core/theme/app_colors.dart';

void main() {
  test('confidenceTier maps scores to 0/1/2 at the ramp boundaries', () {
    expect(AppColors.confidenceTier(0.9), 2);
    expect(AppColors.confidenceTier(0.75), 2);
    expect(AppColors.confidenceTier(0.6), 1);
    expect(AppColors.confidenceTier(0.45), 1);
    expect(AppColors.confidenceTier(0.2), 0);
  });

  test('confidence() returns light-mode-safe (darker) variants on light', () {
    for (final score in const [0.9, 0.6, 0.2]) {
      final dark = AppColors.confidence(score, Brightness.dark);
      final light = AppColors.confidence(score, Brightness.light);
      expect(light, isNot(dark), reason: 'light variant must differ');
      // Light variants must be darker (lower luminance) for contrast on #F3F0E9.
      expect(light.computeLuminance(), lessThan(dark.computeLuminance()));
    }
  });

  test('successOn is the bright green on dark and a darker green on light', () {
    expect(AppColors.successOn(Brightness.dark), AppColors.confidenceHigh);
    expect(
      AppColors.successOn(Brightness.light).computeLuminance(),
      lessThan(AppColors.confidenceHigh.computeLuminance()),
    );
  });
}
