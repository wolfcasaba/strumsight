/// Community privacy + audience enums — E09-R04, ADR 0398 §7.
///
/// These two enums are the Flutter-side counterpart of the backend
/// `ProfileVisibility` / `CommunityAudience` (a `(str, Enum)` pair in
/// `backend/app/community/policies/access_policy.py`). The `wireValue`
/// constants are the single source of truth for the JSON / form-encoding
/// — they MUST stay byte-identical to the backend's `.value` strings;
///// a future Flutter round that wires the JSON layer is expected to
/// pass `wireValue` straight into the parser and the encoder.
///
/// Why two enums (not one): the profile-level visibility is a setting on
/// the privacy row, while the per-content audience is a setting on a post
/// / comment. They share the value space today, but they have distinct
/// ownership (one row vs. many rows) and a future round may decouple the
/// two value sets — keeping them separate now makes that a no-op locally.
///
/// The enums are intentionally minimal — no `fromJson`/`toJson` yet.
/// Wiring the serialization lands with the first read-path round (Kör
/// 5+), when the JSON parser/encoder needs to bind to them; building
/// that now would couple this round to a JSON layer that doesn't exist
/// yet (ADR 0397 §5 `IdentityService.new_public_id` precedent).
library;

enum ProfileVisibility {
  public('public'),
  followers('followers'),
  private('private');

  const ProfileVisibility(this.wireValue);

  /// Stable JSON / form encoding — byte-identical to the backend
  /// `.value` of the matching enum member. See `access_policy.py`.
  final String wireValue;
}

enum CommunityAudience {
  public('public'),
  followers('followers'),
  private('private');

  const CommunityAudience(this.wireValue);

  /// Stable JSON / form encoding — byte-identical to the backend
  /// `.value` of the matching enum member. See `access_policy.py`.
  final String wireValue;
}
