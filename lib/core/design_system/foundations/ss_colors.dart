import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_palette.dart';

enum SsStatusMarkerKind { confidence, offline, localAi, cloudAi }

final class SsStatusMarkerData {
  const SsStatusMarkerData({required this.icon});

  final IconData icon;
}

abstract final class SsStatusMarkers {
  static const _confidence = SsStatusMarkerData(icon: Icons.help_outline);
  static const _offline = SsStatusMarkerData(icon: Icons.cloud_off_outlined);
  static const _localAi = SsStatusMarkerData(icon: Icons.memory_outlined);
  static const _cloudAi = SsStatusMarkerData(icon: Icons.cloud_outlined);

  static SsStatusMarkerData forKind(SsStatusMarkerKind kind) {
    return switch (kind) {
      SsStatusMarkerKind.confidence => _confidence,
      SsStatusMarkerKind.offline => _offline,
      SsStatusMarkerKind.localAi => _localAi,
      SsStatusMarkerKind.cloudAi => _cloudAi,
    };
  }
}

final class SsColorScheme extends ThemeExtension<SsColorScheme> {
  const SsColorScheme({
    required this.brand,
    required this.brandStrong,
    required this.onBrand,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.confidenceHigh,
    required this.confidenceMedium,
    required this.confidenceLow,
    required this.offline,
    required this.localAi,
    required this.cloudAi,
    required this.syncPending,
  });

  factory SsColorScheme.forBrightness(
    Brightness brightness, {
    bool highContrast = false,
  }) {
    final palette = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return SsColorScheme(
      brand: AppColors.primary,
      brandStrong: AppColors.primaryDark,
      onBrand: palette.onAccent,
      canvas: palette.bg,
      surface: palette.surface,
      surfaceRaised: palette.surface,
      surfaceSunken: palette.track,
      border: highContrast ? palette.ink : palette.border,
      borderStrong: palette.ink,
      textPrimary: palette.ink,
      textSecondary: palette.muted,
      textDisabled: palette.muted,
      success: AppColors.successOn(brightness),
      warning: AppColors.confidence(.5, brightness),
      danger: AppColors.danger,
      info: AppColors.secondary,
      confidenceHigh: AppColors.confidence(1, brightness),
      confidenceMedium: AppColors.confidence(.5, brightness),
      confidenceLow: AppColors.confidence(0, brightness),
      offline: palette.muted,
      localAi: AppColors.primary,
      cloudAi: AppColors.secondary,
      syncPending: palette.track,
    );
  }

  final Color brand;
  final Color brandStrong;
  final Color onBrand;
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color confidenceHigh;
  final Color confidenceMedium;
  final Color confidenceLow;
  final Color offline;
  final Color localAi;
  final Color cloudAi;
  final Color syncPending;

  @override
  SsColorScheme copyWith({
    Color? brand,
    Color? brandStrong,
    Color? onBrand,
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? confidenceHigh,
    Color? confidenceMedium,
    Color? confidenceLow,
    Color? offline,
    Color? localAi,
    Color? cloudAi,
    Color? syncPending,
  }) {
    return SsColorScheme(
      brand: brand ?? this.brand,
      brandStrong: brandStrong ?? this.brandStrong,
      onBrand: onBrand ?? this.onBrand,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      confidenceHigh: confidenceHigh ?? this.confidenceHigh,
      confidenceMedium: confidenceMedium ?? this.confidenceMedium,
      confidenceLow: confidenceLow ?? this.confidenceLow,
      offline: offline ?? this.offline,
      localAi: localAi ?? this.localAi,
      cloudAi: cloudAi ?? this.cloudAi,
      syncPending: syncPending ?? this.syncPending,
    );
  }

  @override
  SsColorScheme lerp(ThemeExtension<SsColorScheme>? other, double t) {
    if (other is! SsColorScheme) return this;
    return SsColorScheme(
      brand: Color.lerp(brand, other.brand, t)!,
      brandStrong: Color.lerp(brandStrong, other.brandStrong, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      confidenceHigh: Color.lerp(confidenceHigh, other.confidenceHigh, t)!,
      confidenceMedium: Color.lerp(
        confidenceMedium,
        other.confidenceMedium,
        t,
      )!,
      confidenceLow: Color.lerp(confidenceLow, other.confidenceLow, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      localAi: Color.lerp(localAi, other.localAi, t)!,
      cloudAi: Color.lerp(cloudAi, other.cloudAi, t)!,
      syncPending: Color.lerp(syncPending, other.syncPending, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SsColorScheme &&
        other.brand == brand &&
        other.brandStrong == brandStrong &&
        other.onBrand == onBrand &&
        other.canvas == canvas &&
        other.surface == surface &&
        other.surfaceRaised == surfaceRaised &&
        other.surfaceSunken == surfaceSunken &&
        other.border == border &&
        other.borderStrong == borderStrong &&
        other.textPrimary == textPrimary &&
        other.textSecondary == textSecondary &&
        other.textDisabled == textDisabled &&
        other.success == success &&
        other.warning == warning &&
        other.danger == danger &&
        other.info == info &&
        other.confidenceHigh == confidenceHigh &&
        other.confidenceMedium == confidenceMedium &&
        other.confidenceLow == confidenceLow &&
        other.offline == offline &&
        other.localAi == localAi &&
        other.cloudAi == cloudAi &&
        other.syncPending == syncPending;
  }

  @override
  int get hashCode => Object.hashAll([
    brand,
    brandStrong,
    onBrand,
    canvas,
    surface,
    surfaceRaised,
    surfaceSunken,
    border,
    borderStrong,
    textPrimary,
    textSecondary,
    textDisabled,
    success,
    warning,
    danger,
    info,
    confidenceHigh,
    confidenceMedium,
    confidenceLow,
    offline,
    localAi,
    cloudAi,
    syncPending,
  ]);
}

final class SsStateOverlays extends ThemeExtension<SsStateOverlays> {
  const SsStateOverlays({
    required this.disabled,
    required this.focused,
    required this.hovered,
    required this.pressed,
    required this.selected,
  });

  factory SsStateOverlays.fromColors(
    SsColorScheme colors, {
    required bool highContrast,
  }) {
    return SsStateOverlays(
      disabled: colors.textDisabled,
      focused: highContrast ? colors.borderStrong : colors.brand,
      hovered: highContrast ? colors.borderStrong : colors.surfaceRaised,
      pressed: colors.brandStrong,
      selected: colors.brand,
    );
  }

  final Color disabled;
  final Color focused;
  final Color hovered;
  final Color pressed;
  final Color selected;

  @override
  SsStateOverlays copyWith({
    Color? disabled,
    Color? focused,
    Color? hovered,
    Color? pressed,
    Color? selected,
  }) => SsStateOverlays(
    disabled: disabled ?? this.disabled,
    focused: focused ?? this.focused,
    hovered: hovered ?? this.hovered,
    pressed: pressed ?? this.pressed,
    selected: selected ?? this.selected,
  );

  @override
  SsStateOverlays lerp(ThemeExtension<SsStateOverlays>? other, double t) {
    if (other is! SsStateOverlays) return this;
    return SsStateOverlays(
      disabled: Color.lerp(disabled, other.disabled, t)!,
      focused: Color.lerp(focused, other.focused, t)!,
      hovered: Color.lerp(hovered, other.hovered, t)!,
      pressed: Color.lerp(pressed, other.pressed, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SsStateOverlays &&
      other.disabled == disabled &&
      other.focused == focused &&
      other.hovered == hovered &&
      other.pressed == pressed &&
      other.selected == selected;

  @override
  int get hashCode =>
      Object.hash(disabled, focused, hovered, pressed, selected);
}

final class SsThemeBehavior extends ThemeExtension<SsThemeBehavior> {
  const SsThemeBehavior({
    required this.borderWidth,
    required this.focusRingWidth,
    required this.surfaceOpacity,
    required this.decorativeEffectsEnabled,
  });

  final double borderWidth;
  final double focusRingWidth;
  final double surfaceOpacity;
  final bool decorativeEffectsEnabled;

  @override
  SsThemeBehavior copyWith({
    double? borderWidth,
    double? focusRingWidth,
    double? surfaceOpacity,
    bool? decorativeEffectsEnabled,
  }) => SsThemeBehavior(
    borderWidth: borderWidth ?? this.borderWidth,
    focusRingWidth: focusRingWidth ?? this.focusRingWidth,
    surfaceOpacity: surfaceOpacity ?? this.surfaceOpacity,
    decorativeEffectsEnabled:
        decorativeEffectsEnabled ?? this.decorativeEffectsEnabled,
  );

  @override
  SsThemeBehavior lerp(ThemeExtension<SsThemeBehavior>? other, double t) {
    if (other is! SsThemeBehavior) return this;
    return SsThemeBehavior(
      borderWidth: borderWidth + (other.borderWidth - borderWidth) * t,
      focusRingWidth:
          focusRingWidth + (other.focusRingWidth - focusRingWidth) * t,
      surfaceOpacity:
          surfaceOpacity + (other.surfaceOpacity - surfaceOpacity) * t,
      decorativeEffectsEnabled: t < .5
          ? decorativeEffectsEnabled
          : other.decorativeEffectsEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SsThemeBehavior &&
      other.borderWidth == borderWidth &&
      other.focusRingWidth == focusRingWidth &&
      other.surfaceOpacity == surfaceOpacity &&
      other.decorativeEffectsEnabled == decorativeEffectsEnabled;

  @override
  int get hashCode => Object.hash(
    borderWidth,
    focusRingWidth,
    surfaceOpacity,
    decorativeEffectsEnabled,
  );
}

final class SsStatusMarker extends StatelessWidget {
  const SsStatusMarker({super.key, required this.kind, required this.color});

  final SsStatusMarkerKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(SsStatusMarkers.forKind(kind).icon, color: color);
  }
}
