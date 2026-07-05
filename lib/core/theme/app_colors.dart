import 'package:flutter/material.dart';

/// Music Theory brand colors (PLACEHOLDER — refine when branding decided) — single source of truth.
/// Mirrors the web app: primary #ED068A, secondary #FE734C.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFED068A); // brand pink
  static const Color secondary = Color(0xFFFE734C); // brand orange
  static const Color primaryDark = Color(0xFF690F3E); // plum (fat macro / hover)
  static const Color ink = Color(0xFF1A1A1A);
  static const Color muted = Color(0xFF6B7280);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF6F6F8);

  // --- Semantic / status tokens (replace raw hex scattered across the app) ---

  /// Destructive actions & error states (delete, danger toggles).
  static const Color danger = Color(0xFFE5484D);

  /// A brighter alert red, used for low-coverage micronutrient bars.
  static const Color warning = Color(0xFFEF4444);

  /// Positive amounts & downward weight trends (credits, weight-down).
  static const Color success = Color(0xFF2BB673);

  /// Review / rating stars.
  static const Color star = Color(0xFFFFB400);

  /// Progress-ring track (matches the web ring-track token).
  static const Color ringTrack = Color(0xFFF3F4F6);

  // --- Category accent palette (cookbooks / charts) ---

  /// Accent blue — cookbook covers, micronutrient bars.
  static const Color accentBlue = Color(0xFF3B82F6);

  /// Accent purple — cookbook covers, micronutrient bars.
  static const Color accentPurple = Color(0xFF8B5CF6);

  /// Accent amber — cookbook covers, micronutrient bars.
  static const Color accentAmber = Color(0xFFF59E0B);

  /// Primary brand gradient (top-left → bottom-right).
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
