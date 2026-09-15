/// Shared helpers for the Dio-backed Community repositories (feed +
/// post wiring).
///
/// Two things every HTTP repository in this folder needs and none of
/// them should re-derive:
///
/// * [communityEndpointUnavailable] — the typed failure for an
///   interface method whose backend endpoint does not exist yet. The
///   domain interfaces (``CommunityFeedRepository`` /
///   ``CommunityPostRepository``) surface errors as thrown
///   ``AppFailure`` values (the controllers catch ``on AppFailure``);
///   a ``ConfigurationFailure`` is the honest member of that taxonomy
///   for "this build's backend has no such route" — the same shape the
///   ``Disabled*Repository`` fallbacks throw when the account layer is
///   off, so the controllers need no special case. The ``cause``
///   names the missing route for the log line.
/// * [communityCursorQueryValue] — the ``CursorPage`` → query-string
///   normaliser the profile / social-graph impls carry as a private
///   method each.
library;

import '../../../../core/foundation/app_failure.dart';
import '../../domain/value_objects/cursor_page.dart';

/// The typed failure for a repository method with no backend route.
///
/// ``retryable`` stays ``false`` (the ``ConfigurationFailure``
/// default) — retrying a missing route cannot succeed.
ConfigurationFailure communityEndpointUnavailable(String route) {
  return ConfigurationFailure(
    cause: UnsupportedError('community backend has no route for $route'),
  );
}

/// Normalise the ``Object``-typed cursor of the domain contracts into
/// the optional ``cursor`` query value: ``null`` for the initial page,
/// the opaque server token otherwise.
String? communityCursorQueryValue(Object cursor) {
  if (cursor == const CursorPage.initial()) return null;
  if (cursor is CursorPage) {
    return cursor.cursor;
  }
  throw ArgumentError.value(
    cursor,
    'cursor',
    'cursor must be a CursorPage (initial / continued / haltedAfterRequest)',
  );
}
