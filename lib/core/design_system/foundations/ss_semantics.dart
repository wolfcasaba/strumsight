import '../../../l10n/app_localizations.dart';

/// Pinned accessibility dimensions verified by the foundation tests.
abstract final class SsSemantics {
  static const double minimumInteractiveDimension = 48;
  static const double maximumTextScale = 2.0;

  /// The minimum gap between two [SsLiveRegion] announcements (ADR 0280
  /// §2), the boundary is INCLUSIVE — a gap of exactly this duration is
  /// allowed to announce (verified by `semantics_contract_test.dart` A1,
  /// "at the threshold").
  static const Duration liveRegionAnnouncementGap = Duration(
    milliseconds: 1000,
  );

  /// The tuner's cents-offset read as text (ADR 0280 §5.3, A2): the same
  /// fact the visual gauge shows — how far off, and which way — so a
  /// screen-reader user gets it too, not a colour or a needle position.
  /// Mirrors the rounding `cents_gauge.dart` already uses so both surfaces
  /// speak the same number.
  static String tunerAccuracyLabel(
    AppLocalizations l10n, {
    required double cents,
    required bool inTune,
  }) {
    if (inTune) return l10n.tunerInTune;
    final rounded = cents.abs().round();
    return cents >= 0
        ? l10n.tunerCentsSharp(rounded)
        : l10n.tunerCentsFlat(rounded);
  }

  /// The strum direction read as text (ADR 0280 §5.3, A2) — not conveyed by
  /// arrow glyph or colour alone.
  static String strumDirectionLabel(
    AppLocalizations l10n, {
    required bool isDown,
  }) => isDown ? l10n.strumDown : l10n.strumUp;
}
