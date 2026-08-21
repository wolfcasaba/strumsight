import 'package:flutter/material.dart';

import 'ss_colors.dart';

/// The closed hierarchy used by StrumSight surface primitives.
enum SsElevation {
  base,
  raised,
  overlay,
  modal;

  /// Resolves this level from the active semantic theme contract.
  SsSurfaceStyle resolve(ThemeData theme) {
    final colors = theme.extension<SsColorScheme>()!;
    final behavior = theme.extension<SsThemeBehavior>()!;
    final isHighContrast = !behavior.decorativeEffectsEnabled;
    final blend = switch (this) {
      SsElevation.base => 0.0,
      SsElevation.raised => _raisedBlend,
      SsElevation.overlay => _overlayBlend,
      SsElevation.modal => _modalBlend,
    };
    final shadowElevation = switch (this) {
      SsElevation.base => _noShadow,
      SsElevation.raised => _raisedShadow,
      SsElevation.overlay => _overlayShadow,
      SsElevation.modal => _modalShadow,
    };
    final useShadow = theme.brightness == Brightness.light && !isHighContrast;

    return SsSurfaceStyle(
      background: _elevatedBackground(
        colors: colors,
        brightness: theme.brightness,
        blend: blend,
      ),
      border: this == SsElevation.base
          ? colors.border
          : isHighContrast
          ? colors.borderStrong
          : Color.lerp(colors.border, colors.borderStrong, blend)!,
      borderWidth: behavior.borderWidth,
      shadowColor: Colors.black.withValues(alpha: _shadowOpacity),
      shadowElevation: useShadow ? shadowElevation : _noShadow,
    );
  }

  static Color _elevatedBackground({
    required SsColorScheme colors,
    required Brightness brightness,
    required double blend,
  }) {
    final target = brightness == Brightness.dark
        ? colors.textPrimary
        : colors.canvas;
    return Color.lerp(colors.surfaceRaised, target, blend)!;
  }
}

@immutable
final class SsSurfaceStyle {
  const SsSurfaceStyle({
    required this.background,
    required this.border,
    required this.borderWidth,
    required this.shadowColor,
    required this.shadowElevation,
  });

  final Color background;
  final Color border;
  final double borderWidth;
  final Color shadowColor;
  final double shadowElevation;

  @override
  bool operator ==(Object other) {
    return other is SsSurfaceStyle &&
        other.background == background &&
        other.border == border &&
        other.borderWidth == borderWidth &&
        other.shadowColor == shadowColor &&
        other.shadowElevation == shadowElevation;
  }

  @override
  int get hashCode => Object.hash(
    background,
    border,
    borderWidth,
    shadowColor,
    shadowElevation,
  );
}

const double _noShadow = 0;
const double _raisedShadow = 1;
const double _overlayShadow = 2;
const double _modalShadow = 4;
const double _raisedBlend = .04;
const double _overlayBlend = .08;
const double _modalBlend = .12;
const double _shadowOpacity = .16;
