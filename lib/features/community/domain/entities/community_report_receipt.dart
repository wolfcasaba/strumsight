/// The reporter-facing receipt of a submitted content report (E09-R26
/// §5.1, wired in R33 / M10).
///
/// The backend's `build_sanitized_response` returns ONLY the wire-safe
/// fields — it never reads the reporter identity column — and this class
/// mirrors exactly the two the client actually consumes. Keeping it that
/// narrow is deliberate: an entity with a `reporterPublicId` field would
/// be a place for a future maintainer to put one.
library;

final class CommunityReportReceipt {
  const CommunityReportReceipt({
    required this.reportPublicId,
    required this.deduplicated,
  });

  /// The report row's UUID — the only identifier the reporter is shown.
  final String reportPublicId;

  /// `true` when the submit recycled an existing report row. The sheet
  /// shows the same thanks view either way; the flag exists so a caller
  /// can tell a fresh INSERT from a repeat.
  final bool deduplicated;

  @override
  bool operator ==(Object other) =>
      other is CommunityReportReceipt &&
      other.reportPublicId == reportPublicId &&
      other.deduplicated == deduplicated;

  @override
  int get hashCode => Object.hash(reportPublicId, deduplicated);
}
