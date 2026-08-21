import 'package:flutter/material.dart';

import '../foundations/ss_typography.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';
import '../../theme/app_theme.dart';

/// Theme extension colors derived from the legacy palette and brand tokens.
@immutable
final class SsThemeColors extends ThemeExtension<SsThemeColors> {
  const SsThemeColors({
    required this.brand,
    required this.brandStrong,
    required this.canvas,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });

  final Color brand;
  final Color brandStrong;
  final Color canvas;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  @override
  SsThemeColors copyWith({
    Color? brand,
    Color? brandStrong,
    Color? canvas,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
  }) {
    return SsThemeColors(
      brand: brand ?? this.brand,
      brandStrong: brandStrong ?? this.brandStrong,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
    );
  }

  @override
  SsThemeColors lerp(ThemeExtension<SsThemeColors>? other, double t) {
    if (other is! SsThemeColors) return this;
    return SsThemeColors(
      brand: Color.lerp(brand, other.brand, t)!,
      brandStrong: Color.lerp(brandStrong, other.brandStrong, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

/// Compatibility accessors for the legacy theme contracts during migration.
abstract final class SsThemeExtensions {
  static const typography = SsTypography.standard();

  /// Returns extension colors for [brightness] from the legacy color sources.
  static SsThemeColors forBrightness(Brightness brightness) {
    final palette = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return SsThemeColors(
      brand: AppColors.primary,
      brandStrong: AppColors.primaryDark,
      canvas: palette.bg,
      surface: palette.surface,
      textPrimary: palette.ink,
      textSecondary: palette.muted,
      border: palette.border,
    );
  }

  /// Returns the legacy [AppTheme] while preserving its extensions.
  static ThemeData legacyThemeForBrightness(Brightness brightness) {
    final legacy = brightness == Brightness.dark
        ? AppTheme.dark()
        : AppTheme.light();
    return legacy.copyWith(
      extensions: [...legacy.extensions.values, typography],
    );
  }
}
