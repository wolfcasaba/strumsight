/// The three delete scopes the storage-management entry point offers
/// (§5.3/§5.4, ADR 0279 §1). The confirmation always names which of these is
/// about to happen — "Delete? Yes/No" with no scope is the forbidden
/// weakening §5.3 calls out.
library;

enum LibraryDeleteScope {
  /// Only the retained raw capture is removed — the analysis result stays
  /// openable (§5.5).
  rawOnly,

  /// Only the computed analysis result is removed — the raw capture, if any
  /// is retained, stays.
  resultOnly,

  /// The whole item — raw capture and result — is removed. Irreversible.
  everything,
}
