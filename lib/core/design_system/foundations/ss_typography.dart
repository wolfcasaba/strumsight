import 'package:flutter/material.dart';

/// The Chapter 13 typography scale available from a design-system theme.
@immutable
final class SsTypography extends ThemeExtension<SsTypography> {
  const SsTypography({
    required this.displayChord,
    required this.displayScore,
    required this.headlineLarge,
    required this.headlineMedium,
    required this.titleLarge,
    required this.titleMedium,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.labelLarge,
    required this.metricLarge,
    required this.metricMedium,
    required this.metricSmall,
  });

  const SsTypography.standard()
    : displayChord = const TextStyle(
        fontFamily: poppinsFamily,
        fontSize: 80,
        height: 1.1,
        fontWeight: FontWeight.w800,
      ),
      displayScore = const TextStyle(
        fontFamily: poppinsFamily,
        fontSize: 56,
        height: 64 / 56,
        fontWeight: FontWeight.w800,
      ),
      headlineLarge = const TextStyle(
        fontFamily: poppinsFamily,
        fontSize: 32,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium = const TextStyle(
        fontFamily: poppinsFamily,
        fontSize: 26,
        height: 34 / 26,
        fontWeight: FontWeight.w700,
      ),
      titleLarge = const TextStyle(
        fontFamily: poppinsFamily,
        fontSize: 22,
        height: 30 / 22,
        fontWeight: FontWeight.w600,
      ),
      titleMedium = const TextStyle(
        fontFamily: poppinsFamily,
        fontSize: 18,
        height: 26 / 18,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge = const TextStyle(
        fontFamily: poppinsFamily,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium = const TextStyle(
        fontFamily: poppinsFamily,
        fontSize: 14,
        height: 22 / 14,
        fontWeight: FontWeight.w400,
      ),
      labelLarge = const TextStyle(
        fontFamily: poppinsFamily,
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
      ),
      metricLarge = const TextStyle(
        fontFamily: montserratFamily,
        fontSize: 28,
        height: 34 / 28,
        fontWeight: FontWeight.w600,
        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      ),
      metricMedium = const TextStyle(
        fontFamily: montserratFamily,
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      ),
      metricSmall = const TextStyle(
        fontFamily: montserratFamily,
        fontSize: 12,
        height: 1.5,
        fontWeight: FontWeight.w500,
        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      );

  static const poppinsFamily = 'Poppins';
  static const montserratFamily = 'Montserrat';

  final TextStyle displayChord;
  final TextStyle displayScore;
  final TextStyle headlineLarge;
  final TextStyle headlineMedium;
  final TextStyle titleLarge;
  final TextStyle titleMedium;
  final TextStyle bodyLarge;
  final TextStyle bodyMedium;
  final TextStyle labelLarge;
  final TextStyle metricLarge;
  final TextStyle metricMedium;
  final TextStyle metricSmall;

  /// Selects the chord design size while leaving platform text scaling intact.
  TextStyle displayChordForViewport({required double viewportWidth}) {
    final viewportProgress = ((viewportWidth - 320) / (840 - 320)).clamp(
      0.0,
      1.0,
    );
    final designSize = 80 + (48 * viewportProgress);

    // The Text widget applies its TextScaler; this only selects its base design size.
    return displayChord.copyWith(fontSize: designSize);
  }

  /// Joins a metric value and its unit with the non-breaking space contract.
  static String metricLabel(num value, String unit) => '$value\u00a0$unit';

  @override
  SsTypography copyWith({
    TextStyle? displayChord,
    TextStyle? displayScore,
    TextStyle? headlineLarge,
    TextStyle? headlineMedium,
    TextStyle? titleLarge,
    TextStyle? titleMedium,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? labelLarge,
    TextStyle? metricLarge,
    TextStyle? metricMedium,
    TextStyle? metricSmall,
  }) {
    return SsTypography(
      displayChord: displayChord ?? this.displayChord,
      displayScore: displayScore ?? this.displayScore,
      headlineLarge: headlineLarge ?? this.headlineLarge,
      headlineMedium: headlineMedium ?? this.headlineMedium,
      titleLarge: titleLarge ?? this.titleLarge,
      titleMedium: titleMedium ?? this.titleMedium,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      labelLarge: labelLarge ?? this.labelLarge,
      metricLarge: metricLarge ?? this.metricLarge,
      metricMedium: metricMedium ?? this.metricMedium,
      metricSmall: metricSmall ?? this.metricSmall,
    );
  }

  @override
  SsTypography lerp(ThemeExtension<SsTypography>? other, double t) {
    if (other is! SsTypography) return this;

    return SsTypography(
      displayChord: TextStyle.lerp(displayChord, other.displayChord, t)!,
      displayScore: TextStyle.lerp(displayScore, other.displayScore, t)!,
      headlineLarge: TextStyle.lerp(headlineLarge, other.headlineLarge, t)!,
      headlineMedium: TextStyle.lerp(headlineMedium, other.headlineMedium, t)!,
      titleLarge: TextStyle.lerp(titleLarge, other.titleLarge, t)!,
      titleMedium: TextStyle.lerp(titleMedium, other.titleMedium, t)!,
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t)!,
      bodyMedium: TextStyle.lerp(bodyMedium, other.bodyMedium, t)!,
      labelLarge: TextStyle.lerp(labelLarge, other.labelLarge, t)!,
      metricLarge: TextStyle.lerp(metricLarge, other.metricLarge, t)!,
      metricMedium: TextStyle.lerp(metricMedium, other.metricMedium, t)!,
      metricSmall: TextStyle.lerp(metricSmall, other.metricSmall, t)!,
    );
  }
}
