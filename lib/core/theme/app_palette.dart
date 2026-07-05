import 'package:flutter/material.dart';

/// Semantic, theme-aware colors (light/dark). Brand colors stay in
/// [AppColors]; everything surface/text/border related comes from here so
/// the app can flip between light and dark.
///
/// Access via `context.palette.ink` etc.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.track,
    required this.border,
  });

  /// Scaffold / screen background.
  final Color bg;

  /// Card / elevated surface background.
  final Color surface;

  /// Primary text.
  final Color ink;

  /// Secondary text / icons.
  final Color muted;

  /// Progress tracks / subtle fills.
  final Color track;

  /// Hairline borders / dividers.
  final Color border;

  static const light = AppPalette(
    bg: Color(0xFFF6F6F8),
    surface: Colors.white,
    ink: Color(0xFF1A1A1A),
    muted: Color(0xFF6B7280),
    track: Color(0xFFEFEFF4),
    border: Color(0xFFE6E6EC),
  );

  static const dark = AppPalette(
    bg: Color(0xFF101015),
    surface: Color(0xFF1B1B22),
    ink: Color(0xFFF3F3F7),
    muted: Color(0xFF9AA0AC),
    track: Color(0xFF2A2A33),
    border: Color(0xFF2E2E38),
  );

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? track,
    Color? border,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      track: track ?? this.track,
      border: border ?? this.border,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      track: Color.lerp(track, other.track, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

extension PaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
