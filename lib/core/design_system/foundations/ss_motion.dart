import 'package:flutter/animation.dart' show Curve, Curves;

/// Pinned motion durations and reduced-motion fallback verified by tests.
abstract final class SsMotion {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration emphasized = Duration(milliseconds: 300);
  static const Duration celebration = Duration(milliseconds: 700);

  static const List<Duration> durations = [
    instant,
    fast,
    standard,
    emphasized,
    celebration,
  ];

  static Duration forReducedMotion(bool reducedMotion) =>
      reducedMotion ? Duration.zero : standard;

  // --- Semantic aliases (Ch13 §9.7) — additive; each names one of the
  // pinned durations above by use case, no new base values. ---

  /// A micro-interaction: icon toggle, tap ripple settle.
  static const Duration microInteraction = instant;

  /// A chord-change crossfade/scale (Ch13 §9.7: "rövid crossfade/scale").
  static const Duration chordChange = fast;

  /// Content fade-in/out within a screen (list item, card, sheet).
  static const Duration contentFade = standard;

  /// A route/screen transition (Ch13 §9.7: "route transition: 200–300 ms").
  static const Duration routeTransition = emphasized;

  /// A success/celebration flourish (achievement, streak).
  static const Duration successFeedback = celebration;

  // --- Curve tokens (Ch13 §9.7) ---

  /// Default easing for content entering the screen.
  static const Curve enter = Curves.easeOutCubic;

  /// Default easing for content leaving the screen.
  static const Curve exit = Curves.easeInCubic;

  /// Emphasized easing for route transitions and large surface motion.
  static const Curve emphasizedCurve = Curves.easeInOutCubicEmphasized;

  /// Constant-rate motion for clock-driven (beat-synced) animation, where
  /// the phase itself — not the curve — carries the musical timing.
  static const Curve linear = Curves.linear;
}
