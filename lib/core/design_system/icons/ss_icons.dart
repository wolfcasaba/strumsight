import 'package:flutter/material.dart' show IconData, Icons;

/// The fourteen guitar-technique glyphs Ch13 §9.8 requires (`downstrum` …
/// `loopAB`). Referencing a value here — rather than a raw string — is the
/// translation-time guard against a name typo (ADR 0411 §3), the same role
/// Material's `Icons.*` constants play for the Material catalog below.
enum SsGuitarGlyphName {
  downstrum,
  upstrum,
  alternatePicking,
  palmMute,
  bend,
  vibrato,
  hammerOn,
  pullOff,
  slide,
  capo,
  metronome,
  tuningPeg,
  fretboard,
  loopAB,
}

/// The two-tier size contract pinned by ADR 0411 §5 — 24 dp base, 32–48 dp
/// Stage, both Stage bounds inclusive.
abstract final class SsIconSize {
  static const double base = 24;
  static const double stageMin = 32;
  static const double stageMax = 48;

  /// True only inside the inclusive Stage range; false for [base] itself.
  static bool isValidForStage(double size) =>
      size >= stageMin && size <= stageMax;

  /// Clamps [requested] into the inclusive Stage range — the value an
  /// [SsIcon] actually renders at in a Stage context, never the raw request
  /// (ADR 0411 §5: a below-range size must not reach the render path).
  static double resolveForStage(double requested) {
    if (requested < stageMin) return stageMin;
    if (requested > stageMax) return stageMax;
    return requested;
  }
}

/// What an [SsIconName] resolved to. [isFallback] is the queryable half of
/// ADR 0411 §6 — a caller (or a test) can tell a miss happened without
/// inspecting the render tree.
sealed class SsIconResolution {
  const SsIconResolution();

  bool get isFallback => false;
}

final class SsResolvedGuitarGlyph extends SsIconResolution {
  const SsResolvedGuitarGlyph(this.name);

  final SsGuitarGlyphName name;
}

final class SsResolvedMaterialIcon extends SsIconResolution {
  const SsResolvedMaterialIcon(this.data);

  final IconData data;
}

/// The visible, non-zero-size fallback (ADR 0411 §6) substituted when a
/// requested name resolves to neither catalog.
final class SsFallbackIcon extends SsIconResolution {
  const SsFallbackIcon();

  @override
  bool get isFallback => true;
}

/// The icon name catalog: Material Symbols aliases (pinned so a rename shows
/// up as a compile error here, not at every call site) plus the resolver
/// that also reaches the fourteen [SsGuitarGlyphName] painted glyphs.
abstract final class SsIcons {
  static const IconData play = Icons.play_arrow_outlined;
  static const IconData pause = Icons.pause_outlined;
  static const IconData settings = Icons.settings_outlined;
  static const IconData close = Icons.close_outlined;
  static const IconData check = Icons.check_outlined;
  static const IconData info = Icons.info_outlined;

  static const Map<String, IconData> _materialByName = {
    'play': play,
    'pause': pause,
    'settings': settings,
    'close': close,
    'check': check,
    'info': info,
  };

  /// Resolves [name] against the guitar-glyph names, then the Material
  /// catalog, then the visible fallback (ADR 0411 §6) — never a silent miss.
  static SsIconResolution resolveByName(String name) {
    for (final glyph in SsGuitarGlyphName.values) {
      if (glyph.name == name) return SsResolvedGuitarGlyph(glyph);
    }
    final material = _materialByName[name];
    if (material != null) return SsResolvedMaterialIcon(material);
    return const SsFallbackIcon();
  }
}
