/// Opaque feed cursor page (E09-R05, ADR 0399 §1, SDD §13.4).
///
/// Per ADR §0.0 / brief §0.0 D3 the cursor's *content* is owned by the
/// server — the Kör 5 type deliberately refuses to interpret it. Two
/// Kör 6+ states must NOT share a representation:
///
/// * **Initial page** — the user has never paged, no cursor was sent.
///   Emitted as [CursorPage.initial]; the implementing repo has
///   nothing to pass back.
///
/// * **Continued page** — the previous page returned a non-null cursor;
///   the UI should request the next page with that cursor. Modeled as
///   [CursorPage.continued] with the server-issued opaque string.
///
/// The two cases *would have collapsed* into a single nullable-cursor
/// API; Kör 6+ pagination explicitly distinguishes them so the
/// "end-of-feed" vs "first-request" code paths stop stepping on each
/// other. The L349 measured footgun (same nullable cursor for both
/// "start" and "halt") is encoded here as an explicit type-state, not
/// a nullable field.
library;

final class CursorPage {
  const CursorPage._(this.cursor, this.isInitial);

  /// The empty / first-request cursor page. The Kör 6+ repository
  /// returns this for a list that was never paged, before the first
  /// server call.
  const CursorPage.initial() : cursor = null, isInitial = true;

  /// A page that returned a server cursor. The Kör 6+ repository passes
  /// the returned [cursor] back to the next list call. A `null` cursor
  /// here signals the server's "end of feed" (or a HALT result), which
  /// is a CONCRETE state distinct from [initial]; see the test matrix
  /// for the cell that proves a non-initial `CursorPage` with `cursor ==
  /// null` is a valid value (the repo's HALT answer).
  const CursorPage.continued(String this.cursor) : isInitial = false;

  /// True when [cursor] is null because the page has not yet been
  /// requested. False when [cursor] was returned by a server call,
  /// INCLUDING when the call returned `null` as an explicit end-of-feed
  /// signal.
  final bool isInitial;

  /// The opaque server-issued cursor (or `null`). Callers MUST treat
  /// this as a black box and feed it back to the next page request.
  final String? cursor;

  /// Test-only convenience: a non-initial page with no further pages.
  /// Use this to assert that the repo layer can emit an empty cursor
  /// (`null`) at end-of-feed without losing the type-state distinction
  /// from the initial page.
  const CursorPage.haltedAfterRequest() : cursor = null, isInitial = false;

  @override
  bool operator ==(Object other) =>
      other is CursorPage &&
      other.isInitial == isInitial &&
      other.cursor == cursor;

  @override
  int get hashCode => Object.hash(isInitial, cursor);

  @override
  String toString() =>
      isInitial ? 'CursorPage.initial' : 'CursorPage.continued($cursor)';
}
