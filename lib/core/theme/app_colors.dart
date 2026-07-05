import 'package:flutter/material.dart';

/// StrumSight brand + semantic colours — single source of truth.
///
/// The brand accent is a warm guitar-bronze **copper**. The **confidence
/// ramp** (high/mid/low) is a SEPARATE semantic scale — never the accent — and
/// is always reinforced by arrow shape (filled vs outline) so meaning never
/// depends on colour alone (colour-blind safe).
class AppColors {
  AppColors._();

  // --- Brand (copper / guitar bronze) ---
  static const Color primary = Color(0xFFD98A46); // copper — brand accent
  static const Color secondary = Color(0xFFE0A44A); // warm amber highlight
  static const Color primaryDark = Color(0xFFB26A2E);

  // --- Confidence ramp (semantic — kept distinct from the brand accent) ---
  // Bright variants are tuned for the dark stage background.
  static const Color confidenceHigh = Color(0xFF3ED598); // teal-green
  static const Color confidenceMid = Color(0xFFF2B33D); // amber
  static const Color confidenceLow = Color(0xFF6E7480); // grey (unsure ≠ error)

  // Darker variants for TEXT/marks on the light scaffold, so each tier keeps
  // WCAG AA contrast (≥4.5:1) against palette.bg in light mode.
  static const Color _confidenceHighInk = Color(0xFF178A57);
  static const Color _confidenceMidInk = Color(0xFF976214);
  static const Color _confidenceLowInk = Color(0xFF565B63);

  /// Neutral ink used for strum marks on the beat grid.
  static const Color strumInk = Color(0xFFE9E5DE);

  // --- Generic semantics ---
  static const Color danger = Color(0xFFE5533C);
  static const Color success = Color(0xFF3ED598);

  /// Primary brand gradient (copper → amber); use sparingly on brand surfaces.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Confidence colour for a 0..1 score, contrast-tuned for [brightness].
  /// Thresholds mirror the Settings gate (≥0.75 high, ≥0.45 mid, else low).
  static Color confidence(double score, [Brightness brightness = Brightness.dark]) {
    final light = brightness == Brightness.light;
    if (score >= 0.75) return light ? _confidenceHighInk : confidenceHigh;
    if (score >= 0.45) return light ? _confidenceMidInk : confidenceMid;
    return light ? _confidenceLowInk : confidenceLow;
  }

  /// Confidence tier for a 0..1 score (0 = low, 1 = mid, 2 = high). Drives
  /// arrow SHAPE so meaning never depends on colour alone.
  static int confidenceTier(double score) {
    if (score >= 0.75) return 2;
    if (score >= 0.45) return 1;
    return 0;
  }

  /// The "good"/success green, contrast-safe on both themes (used by the
  /// LISTENING dot+label and the tuner's IN TUNE confirmation).
  static Color successOn(Brightness brightness) =>
      brightness == Brightness.light ? _confidenceHighInk : confidenceHigh;
}
