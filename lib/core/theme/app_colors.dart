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
  static const Color confidenceHigh = Color(0xFF3ED598); // teal-green
  static const Color confidenceMid = Color(0xFFF2B33D); // amber
  static const Color confidenceLow = Color(0xFF6E7480); // grey (unsure ≠ error)

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

  /// Confidence colour for a 0..1 score. Thresholds mirror the Settings
  /// confidence gate (≥0.75 high, ≥0.45 mid, else low).
  static Color confidence(double score) {
    if (score >= 0.75) return confidenceHigh;
    if (score >= 0.45) return confidenceMid;
    return confidenceLow;
  }
}
