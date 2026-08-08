/// Explicit bounds for privacy-safe, local Vision history.
///
/// This is a domain policy rather than a storage implementation: the data
/// layer enforces the cap with `JsonCollectionStore`, while presentation can
/// explain the retention bound without learning storage details.
abstract final class VisionPrivacyControl {
  /// Keep the most recent 100 aggregate-only sessions.
  ///
  /// A session contains no image, frame, coordinate, or landmark sequence.
  /// The cap prevents an unbounded local history while leaving enough recent
  /// sessions for a player to review their coaching trend.
  static const int maxStoredSessions = 100;
}
