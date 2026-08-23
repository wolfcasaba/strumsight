/// Local, per-user, bounded Community feed cache (E09-R14, brief §1 / §5 / §6
/// A2).
///
/// **Scope:** holds the JSON envelopes of the posts the viewer has already
/// seen on the following feed — a bounded "last seen" snapshot that the
/// controller reads back to render an offline / instant-load fallback before
/// the next repository call resolves.
///
/// **User scope (pre-flight D1):** the storage key is partitioned by
/// ``userId`` — the same shape as [CommunityDraftStore]
/// (`ss.community.drafts.v2.<userId>`), the first user-id-keyed local storage
/// in the repo. Each user sees only their own cache; account switch (sign-out
/// / sign-in as someone else) never returns the previous user's feed, even
/// transiently. **A2** is enforced by the storage key, not by the
/// repository contract — the cache never shares a key across users.
///
/// **Bound (pre-flight D2):** the cache uses the same
/// ``JsonCollectionStore`` / ``RecordOrder.newestFirst`` pattern as the rest
/// of the bounded caches (see `PracticeLogRepository.maxEntries`,
/// `keyValuePracticeLogRepository`). The documented bound
/// [FeedCache.maxItems] = 80 keeps the persisted envelope well under the
/// per-document preference ceiling while leaving enough room for the user to
/// scroll back a few pages when offline. The bound is enforced on both read
/// and write (a blob that grew past it in an older build is trimmed, not
/// carried).
///
/// **Schema version:** ``1``. No legacy Community feed document exists to
/// migrate from — this round ships the first one. A future shape bump moves
/// to ``.v2`` next to the matching legacy entry.
///
/// **Corruption (L354 precedent):** the underlying ``JsonDocumentStore``
/// quarantines a per-record decode failure rather than rolling back the whole
/// envelope; a malformed record is dropped and the rest stays readable.
library;

import '../../../../core/foundation/json_validation.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/storage/json_document_store.dart';
import '../../../../core/storage/key_value_store.dart';

/// Documented storage bound for the feed cache (pre-flight D2).
///
/// The number balances two things: (1) the user can scroll back a few pages
/// of the feed when offline — a feed slice is 20 items, so 80 items = 4
/// pages, enough for one offline re-load session; (2) the persisted envelope
/// stays well under any per-document preference ceiling so a single user's
/// cache does not crowd out other features' storage.
///
/// This is the local "last seen" snapshot — not a history. The server's
/// per-page limit (Kör 13, `practice_log_repository.dart`-style `maxItems`)
/// is a separate, wire-side bound.
const int feedCacheMaxItems = 80;

/// Document schema version of the Community feed cache envelope.
const int feedCacheSchemaVersion = 1;

/// Stable, human-readable name for the document in logs and quarantines.
const String _documentName = 'community_feed_cache';

/// A single cached feed row.
///
/// The cache stores the **wire envelope** of each post as a generic JSON map
/// — opaque to the cache layer. The controller rehydrates the envelope into a
/// `CommunityPost` (with `UnfilledCommunityShareArtifact` for the artifact
/// field — the Kör 13 wire schema is the single source of truth for full
/// reconstruction, and the cache holds a snapshot, not the live record).
///
/// The class is intentionally minimal: it is the **wire shape** as a value
/// object, plus a stable hash so the A4 measure-matrix cell can detect
/// duplicates after a refresh. No additional fields — a future round that
/// needs more shape data adds them here AND on the wire schema in lockstep.
final class CachedFeedItem {
  const CachedFeedItem({required this.postId, required this.envelope});

  /// Build from a raw envelope JSON map. The only invariant is that
  /// ``postId`` is a non-empty string — the cache treats everything else as
  /// opaque.
  factory CachedFeedItem.fromEnvelope(Map<String, Object?> envelope) {
    final id = envelope['id'];
    if (id is! String || id.isEmpty) {
      throw JsonRecordException(
        'cached feed item id must be a non-empty string',
        field: 'id',
      );
    }
    return CachedFeedItem(postId: id, envelope: envelope);
  }

  /// Stable post identifier from the wire envelope. Used by the controller
  /// to deduplicate after a refresh (A4).
  final String postId;

  /// The wire envelope, captured verbatim at the time the post was
  /// originally fetched. The cache never inspects or rewrites the contents.
  final Map<String, Object?> envelope;

  Map<String, Object?> toJson() => envelope;

  static CachedFeedItem fromJson(Map<String, dynamic> object) {
    return CachedFeedItem.fromEnvelope(object);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CachedFeedItem && other.postId == postId;

  @override
  int get hashCode => postId.hashCode;
}

/// A per-user, bounded, on-device Community feed cache.
///
/// Construction takes the user-id-keyed storage key — the producer (a
/// Riverpod provider) is responsible for picking the right key for the
/// signed-in user. Reading or writing for a user that does not have a cache
/// yet returns an empty list from [read] and is a no-op-on-error for [write].
class FeedCache {
  /// Internal constructor — use [FeedCache.open] to bind to a real
  /// [KeyValueStore].
  FeedCache._({required JsonCollectionStore<CachedFeedItem> body})
    : _body = body;

  /// The injected, versioned bounded list store.
  final JsonCollectionStore<CachedFeedItem> _body;

  /// Open a [FeedCache] against a real [KeyValueStore] for the given
  /// ``userId``.
  ///
  /// ``userId`` is interpolated into the storage key — never into the
  /// document body, and the document body carries the schema version that
  /// protects a future build from mis-decoding an older one.
  factory FeedCache.open({
    required KeyValueStore store,
    required AppLogger logger,
    required int userId,
  }) {
    final document = JsonDocumentStore(
      store: store,
      logger: logger,
      key: _storageKeyFor(userId),
      // No legacy key — the feed cache envelope is fresh in Kör 14
      // (no prior Community feed document exists to migrate from).
      // Wiring the same key for both would cause `JsonDocumentStore.write`
      // to immediately remove what it just wrote; passing an empty
      // string keeps the per-user `v1.<userId>` partition clean.
      legacyKey: '',
      name: _documentName,
    );
    return FeedCache._(
      body: JsonCollectionStore<CachedFeedItem>(
        document: document,
        fromJson: CachedFeedItem.fromJson,
        toJson: (item) => item.toJson(),
        maxItems: feedCacheMaxItems,
        order: RecordOrder.newestFirst,
      ),
    );
  }

  /// Resolve the namespaced storage key for the given user.
  ///
  /// The ``ss.community.feed.v1.<userId>`` shape follows the
  /// [CommunityDraftStore] precedent
  /// (``ss.community.drafts.v2.<userId>``, the first user-id-partitioned
  /// key in the repo). A future shape bump moves to ``.v2`` next to the
  /// matching legacy entry.
  static String _storageKeyFor(int userId) => 'ss.community.feed.v1.$userId';

  /// Public for the test surface and the round-auditor: the resolved
  /// storage key for [userId].
  static String storageKeyFor(int userId) => _storageKeyFor(userId);

  /// Every persisted item, newest-preserving-capped. Never throws.
  ///
  /// Returns a fresh, mutable list each call so the caller may re-order,
  /// filter, or truncate without aliasing the underlying persisted state.
  List<CachedFeedItem> read() => List<CachedFeedItem>.from(_body.read());

  /// Persist [items] for this user. The store enforces the bound on write
  /// — passing more than [feedCacheMaxItems] keeps the newest
  /// ``feedCacheMaxItems`` and drops the rest (A4's "no duplicate" cell is
  /// satisfied upstream by the controller, not by the cap).
  ///
  /// Throws [StorageException] on a platform write refusal — the caller
  /// (the feed controller) catches it and surfaces a non-fatal "couldn't
  /// persist cache" log without dropping the in-memory items the user is
  /// looking at.
  Future<void> write(List<CachedFeedItem> items) => _body.write(items);
}
