/// Community content moderation lifecycle (E09-R05, ADR 0399 §1, SDD §18.1).
///
/// The five-state lifecycle is the single canonical enumeration of a
/// piece of content's moderation posture. `removed`, `authorOnly` and
/// `pendingReview` are not display hints — they are read-side policy
/// triggers that the backend read-path uses to return placeholder or
/// tombstone rows, never the body (ADR 0398 §3 / §5.1).
///
/// The wire-string form uses snake_case (`pendingReview` →
/// `"pending_review"`, `authorOnly` → `"author_only"`). No live
/// backend enum mirrors `ModerationState` yet (no match under
/// `backend/app/community/`), so the wire form is the Dart-side
/// default per brief §1 F1; a future backend round that adds a
/// matching enum is expected to keep the `.value` strings
/// byte-identical to `wireValue`. The decoder returns `null` for
/// unknown wire values instead of throwing so the data layer can
/// preserve unknown states as tombstone rows (A3).
library;

enum ModerationState {
  visible('visible'),
  limited('limited'),
  pendingReview('pending_review'),
  removed('removed'),
  authorOnly('author_only');

  const ModerationState(this.wireValue);

  /// Stable JSON / form encoding. The Dart identifier and the wire
  /// string differ for `pendingReview` / `authorOnly` — see the
  /// library doc above.
  final String wireValue;
}

/// Decode a wire-string into a [ModerationState]. Returns `null` for
/// unknown values (A3) — the data layer's row-deserializer preserves
/// unknown states as tombstone rows instead of throwing.
ModerationState? moderationStateFromWire(String? wire) {
  if (wire == null || wire.isEmpty) return null;
  for (final state in ModerationState.values) {
    if (state.wireValue == wire) return state;
  }
  return null;
}

/// The wire-string form for the given [ModerationState].
String moderationStateToWire(ModerationState state) => state.wireValue;
