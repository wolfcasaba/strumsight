/// Community content moderation lifecycle (E09-R05, ADR 0399 §1, SDD §18.1).
///
/// The five-state lifecycle is the single canonical enumeration of a
/// piece of content's moderation posture. `removed`, `authorOnly` and
/// `pendingReview` are not display hints — they are read-side policy
/// triggers that the backend read-path uses to return placeholder or
/// tombstone rows, never the body (ADR 0398 §3 / §5.1).
library;

enum ModerationState { visible, limited, pendingReview, removed, authorOnly }
