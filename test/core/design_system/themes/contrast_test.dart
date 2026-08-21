import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

import '../../../../tool/ui_contrast_check.dart';

void main() {
  test('uses the WCAG sRGB relative luminance transform', () {
    expect(
      ContrastCheck.relativeLuminance(0xff948d82),
      closeTo(0.2695735834450039, 1e-12),
    );
  });

  test('text threshold rejects below, accepts at, and accepts above 4.5:1', () {
    expect(
      ContrastCheck.meetsTextContrastForLuminances(1, 1.05 / 4.4 - .05),
      isFalse,
    );
    expect(
      ContrastCheck.meetsTextContrastForLuminances(1, 1.05 / 4.5 - .05),
      isTrue,
    );
    expect(
      ContrastCheck.meetsTextContrastForLuminances(1, 1.05 / 7 - .05),
      isTrue,
    );
  });

  test(
    'all themes meet their text and important border contrast contracts',
    () {
      for (final theme in <SsColorScheme>[
        SsDarkTheme.data().extension<SsColorScheme>()!,
        SsLightTheme.data().extension<SsColorScheme>()!,
        SsHighContrastTheme.data().extension<SsColorScheme>()!,
      ]) {
        expect(
          ContrastCheck.meetsTextContrast(
            theme.textPrimary.toARGB32(),
            theme.canvas.toARGB32(),
          ),
          isTrue,
        );
        expect(
          ContrastCheck.meetsTextContrast(
            theme.textSecondary.toARGB32(),
            theme.canvas.toARGB32(),
          ),
          isTrue,
        );
        expect(
          ContrastCheck.meetsNonTextContrast(
            theme.borderStrong.toARGB32(),
            theme.canvas.toARGB32(),
          ),
          isTrue,
        );
      }
    },
  );

  test('a real low-contrast text mutation is rejected', () {
    final theme = SsDarkTheme.data().extension<SsColorScheme>()!;
    final violatingTheme = theme.copyWith(textPrimary: theme.canvas);

    expect(
      ContrastCheck.meetsTextContrast(
        violatingTheme.textPrimary.toARGB32(),
        violatingTheme.canvas.toARGB32(),
      ),
      isFalse,
    );
  });
}
