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

  // StrumSight is dark-first (a performance/stage surface), but light is fully
  // supported. Neutrals are warm-biased toward the copper accent, not pure grey.
  static const light = AppPalette(
    bg: Color(0xFFF3F0E9),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF1C1A17),
    muted: Color(0xFF6A645B),
    track: Color(0xFFEDE8DF),
    border: Color(0xFFD8D2C6),
  );

  static const dark = AppPalette(
    bg: Color(0xFF111013),
    surface: Color(0xFF191719),
    ink: Color(0xFFE9E5DE),
    muted: Color(0xFF948D82),
    track: Color(0xFF22201F),
    border: Color(0xFF2E2A28),
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
