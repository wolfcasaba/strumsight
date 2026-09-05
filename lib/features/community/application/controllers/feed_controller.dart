/// Community following-feed state machine (E09-R14, brief §1 / §3 / §5 / §6).
///
/// The controller is the *only* place where the feed's mutable state lives.
/// It is a Riverpod ``Notifier`` so the screen can reactively re-render on
/// every state transition. The dependencies — the [CommunityFeedRepository]
/// (interface, brief D6) and the per-user [FeedCache] — are injected through
/// Riverpod providers that the widget test overrides with fakes; a future
/// round wires the real HTTP repository here.
///
/// **State machine (brief §3):**
///
/// ```
/// initial ─load─▶ loading ─ack─▶ content (and the cache is primed)
///                       │
///                       └─nack/exception─▶ error (cache stays as
///                                              fallback)
/// content ─refresh─▶ refreshing ─ack─▶ content (cursor resets)
///                          │
///                          └─nack/exception─▶ offline (cache visible)
/// content ─loadMore─▶ paging ─ack─▶ content (items appended, cursor
///                          │                              advanced)
///                          └─halted─▶ end
///                          └─nack─▶ content (cache + error banner)
/// error ─retry─▶ loading
/// offline ─retry─▶ loading
/// ```
///
/// **Cursor handling (pre-flight D5):** the cursor is `Object`-typed on the
/// [CommunityFeedRepository.followingFeed] contract; the controller wraps
/// every call in a `CursorPage` type-state — `initial()` for the first page,
/// `continued(...)` for the next, and inspects the returned
/// `CommunityPage.cursor` to detect the halted-after-request end.
///
/// **No autoplay / no auto-pagination (§5.1, A3):** the controller never
/// invokes [loadMore] on its own; the screen calls it from an explicit
/// "Továbbiak betöltése" button. The controller has no scroll listener, no
/// timer, no intersection observer.
///
/// **Account isolation (§5.2, A2):** the cache is opened with the current
/// account's ``userId``; account switch replaces the cache, never merges.
///
/// **Cache fallback (A1):** a failed refresh leaves the cache visible and
/// publishes a non-fatal [FeedStatus.offline] state — the user keeps seeing
/// posts, and a banner explains the source is stale.
///
/// **Duplicate suppression (A4):** every append merges by ``postId`` — the
/// controller keeps a `Set<String>` of seen ids in the controller state, and
/// a refresh REPLACES the seen set with the new server response (a refetch
/// that returns fewer items than the cache must not leak stale ids into the
/// next append).
///
/// **No silent no-op (L309):** every repository call has a try/catch; the
/// controller never swallows a `StorageException` or a `NetworkFailure` —
/// each one flips the state to a label the UI can show.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/logging/logger_provider.dart';
import '../../data/local/feed_cache.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_reaction.dart';
import '../../domain/entities/moderation_state.dart';
import '../../domain/entities/share_artifact.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/repositories/feed_repository.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';

import '../../data/repositories/feed_repository_impl.dart'
    show communityFeedRepositoryProvider;
export '../../data/repositories/feed_repository_impl.dart'
    show communityFeedRepositoryProvider;

/// The seven discrete states the following-feed UI can be in.
///
/// The discriminated enum is the source of truth — UI code switches on this
/// directly, no flag combinations to misinterpret. Eight states are listed in
/// the brief §3; the eighth (`initial`) lives in the private initial-build
/// path and is not part of the public enum (the public surface is the seven
/// states the UI renders). The state machine in the library doc lists all
/// eight including the transient `initial`.
enum FeedStatus {
  /// The first frame — before the controller has read the cache or asked the
  /// repository. The screen shows a centred spinner.
  initial,

  /// The first repository call is in flight. The cache has been read but no
  /// content is available yet.
  loading,

  /// The repository returned posts and the cache has been primed. The screen
  /// renders the items.
  content,

  /// The user triggered a pull-to-refresh; the repository is in flight and
  /// the previous content stays visible. The screen shows a non‑blocking
  /// refresh indicator (A7).
  refreshing,

  /// The user tapped "Továbbiak betöltése"; the repository is in flight and
  /// the previous content stays visible.
  paging,

  /// The repository is unreachable AND a cached snapshot exists. The screen
  /// renders the cache with a non‑blocking banner.
  offline,

  /// The repository failed and no cached snapshot is available. The screen
  /// shows an error card with a retry button (A1).
  error,

  /// The repository has explicitly halted (returned a non‑initial cursor
  /// with a null `cursor` value); the screen renders an end‑of‑feed marker
  /// and a CTA (A6).
  end,
}

/// Immutable snapshot of the feed's state.
///
/// Every mutation emits a fresh copy so Riverpod's reference-equality
/// triggers the UI rebuilds. The state deliberately holds BOTH the visible
/// items and the cursor the next page would consume — separating them would
/// invite the "end-of-feed" vs "first-request" code paths to step on each
/// other (the L349 cursor footgun, mitigated at the controller boundary by
/// keeping both halves co-located).
class FeedState {
  const FeedState({
    required this.status,
    required this.items,
    required this.cursor,
    required this.hasCache,
    required this.lastError,
    required this.refreshedAt,
    required this.loadedFromCache,
  });

  /// Build the initial state — pre-build, pre-cache.
  factory FeedState.initial() {
    return const FeedState(
      status: FeedStatus.initial,
      items: <CommunityPost>[],
      cursor: null,
      hasCache: false,
      lastError: null,
      refreshedAt: null,
      loadedFromCache: false,
    );
  }

  /// The discrete UI state.
  final FeedStatus status;

  /// The posts visible on screen, in server order (newest first).
  final List<CommunityPost> items;

  /// The opaque cursor the next ``loadMore`` would consume, or ``null`` when
  /// the controller has no next page to ask for (initial page OR halted).
  final CursorPage? cursor;

  /// True when the underlying [FeedCache] has at least one item. The UI uses
  /// this to decide whether to render the offline snapshot on a refresh
  /// failure (A1: the user keeps seeing posts instead of an error card).
  final bool hasCache;

  /// The most recent failure, surfaced for the UI banner. Cleared on the
  /// next successful refresh.
  final AppFailure? lastError;

  /// Wall-clock timestamp of the last successful repository response.
  final DateTime? refreshedAt;

  /// True when the current `items` came from the local cache rather than the
  /// repository. Flipped off by the first successful repository response.
  final bool loadedFromCache;

  FeedState copyWith({
    FeedStatus? status,
    List<CommunityPost>? items,
    Object? cursor = _sentinel,
    bool? hasCache,
    Object? lastError = _sentinel,
    DateTime? refreshedAt,
    bool? loadedFromCache,
  }) {
    return FeedState(
      status: status ?? this.status,
      items: items ?? this.items,
      cursor: identical(cursor, _sentinel)
          ? this.cursor
          : cursor as CursorPage?,
      hasCache: hasCache ?? this.hasCache,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as AppFailure?,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      loadedFromCache: loadedFromCache ?? this.loadedFromCache,
    );
  }
}

const Object _sentinel = Object();

/// Provider for the per-user [FeedCache]. Reads the signed-in user's id
/// and opens the cache against that partition (A2 — account isolation).
///
/// **This provider is wired in production via an override** (a future
/// round's scope, D6). The widget test in `following_feed_test.dart`
/// overrides it with a cache bound to an in-memory store; the production
/// wiring lives next to the real HTTP repository (Kör 15/16).
final feedCacheProvider = Provider<FeedCache>((ref) {
  throw UnimplementedError(
    'feedCacheProvider must be overridden in production wiring; the test '
    'overrides it with a cache bound to an InMemoryKeyValueStore.',
  );
});

// A `communityFeedRepositoryProvider` EGYETLEN definíciója a
// `data/repositories/feed_repository_impl.dart`-ban él, és onnan
// exportáljuk tovább.
//
// MÉRT hibaosztály (2026-09-05): itt korábban egy MÁSODIK, dobó
// provider állt ugyanezen a néven („must be overridden in production
// wiring"). A képernyő ezt a fájlt importálja, tehát a valódi
// implementáció megírása UTÁN is a dobó változatot kapta volna — a
// bekötés némán hatástalan marad. Ugyanez a hiba a kihívás-repositorynál
// már egyszer előfordult; az egy-definíció szabály az orvosság.


/// The following-feed state machine.
class FeedController extends Notifier<FeedState> {
  @override
  FeedState build() {
    // The build itself is synchronous; the screen calls [load] (or its
    // initial-frame trigger) to actually fetch. We return the initial
    // sentinel so the first frame renders the loading spinner.
    return FeedState.initial();
  }

  CommunityFeedRepository get _repository =>
      ref.read(communityFeedRepositoryProvider);

  FeedCache get _cache => ref.read(feedCacheProvider);

  AppLogger get _logger => ref.read(appLoggerProvider);

  /// Default page size for the feed. Mirrors the Kör 13 server-side page
  /// cap; the test fixture can override via [load] callers.
  static const int defaultPageSize = 20;

  /// Set of post ids already on screen in the current session. A
  /// load-more / refresh that returns an id already in this set is dropped
  /// (A4 — no duplicate post in a session).
  final Set<String> _seenIds = <String>{};

  /// Open the feed for the current account. Reads the cache first
  /// (instant snapshot), then asks the repository for the first page. A
  /// repository failure after a successful cache read leaves the cache
  /// visible with [FeedStatus.offline].
  ///
  /// The cache is **rebuilt for the current userId** — when the user signs
  /// out and signs in as someone else, the cache is opened against the new
  /// user's storage key and the old snapshot never re-appears (A2).
  Future<void> load({int pageSize = defaultPageSize}) async {
    final current = state;
    if (current.status == FeedStatus.loading ||
        current.status == FeedStatus.refreshing ||
        current.status == FeedStatus.paging) {
      // A concurrent fetch is already in flight — drop the second call.
      // (The widget test's "double-tap refresh" path depends on this.)
      return;
    }
    // Prime from cache first so the first frame can render the snapshot.
    final cached = _cache.read();
    final cachedPosts = _rehydrateAll(cached);
    _seenIds
      ..clear()
      ..addAll(cachedPosts.map((p) => p.id.value));
    state = FeedState(
      status: FeedStatus.loading,
      items: cachedPosts,
      cursor: const CursorPage.initial(),
      hasCache: cachedPosts.isNotEmpty,
      lastError: null,
      refreshedAt: current.refreshedAt,
      loadedFromCache: cachedPosts.isNotEmpty,
    );

    try {
      final page = await _repository.followingFeed(
        cursor: const CursorPage.initial(),
        limit: pageSize,
      );
      _absorbPage(page, fromCache: cachedPosts.isNotEmpty);
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.feed.load.failure',
        fields: {
          'items': cachedPosts.length,
          'hasCache': cachedPosts.isNotEmpty,
        },
      );
      state = state.copyWith(
        status: cachedPosts.isNotEmpty ? FeedStatus.offline : FeedStatus.error,
        lastError: failure,
        loadedFromCache: cachedPosts.isNotEmpty,
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.feed.load.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'items': cachedPosts.length,
          'hasCache': cachedPosts.isNotEmpty,
        },
      );
      final failure = UnknownFailure(
        code: FailureCode.unknown,
        cause: error,
        stackTrace: stackTrace,
      );
      state = state.copyWith(
        status: cachedPosts.isNotEmpty ? FeedStatus.offline : FeedStatus.error,
        lastError: failure,
        loadedFromCache: cachedPosts.isNotEmpty,
      );
    }
  }

  /// Pull-to-refresh. Re-fetches the first page from scratch, replacing the
  /// seen-id set (A7 — scroll position is the screen's responsibility, the
  /// controller preserves the items the user is already looking at while
  /// the new fetch is in flight).
  Future<void> refresh({int pageSize = defaultPageSize}) async {
    final current = state;
    if (current.status == FeedStatus.loading ||
        current.status == FeedStatus.refreshing ||
        current.status == FeedStatus.paging) {
      return;
    }
    state = state.copyWith(status: FeedStatus.refreshing, lastError: null);

    try {
      final page = await _repository.followingFeed(
        cursor: const CursorPage.initial(),
        limit: pageSize,
      );
      // The refresh replaces the seen-id set with the new server ids;
      // any post that disappeared between fetches is dropped, and a
      // stale id cannot re-appear from the cache on the next append.
      // The seen-id set MUST be cleared BEFORE `_dedupe` so a post
      // that disappeared server-side is allowed back in if it shows
      // up again on a later refresh — and a post that disappeared
      // server-side is correctly absent here.
      _seenIds.clear();
      final newItems = _dedupe(page.items);
      _seenIds.addAll(newItems.map((p) => p.id.value));
      await _persistCache(newItems);
      state = state.copyWith(
        status: FeedStatus.content,
        items: newItems,
        cursor: page.cursor,
        hasCache: true,
        lastError: null,
        refreshedAt: DateTime.now(),
        loadedFromCache: false,
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.feed.refresh.failure',
        fields: {'items': current.items.length},
      );
      state = state.copyWith(
        status: current.items.isNotEmpty
            ? FeedStatus.offline
            : FeedStatus.error,
        lastError: failure,
        loadedFromCache: current.items.isNotEmpty,
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.feed.refresh.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'items': current.items.length},
      );
      state = state.copyWith(
        status: current.items.isNotEmpty
            ? FeedStatus.offline
            : FeedStatus.error,
        lastError: UnknownFailure(
          code: FailureCode.unknown,
          cause: error,
          stackTrace: stackTrace,
        ),
        loadedFromCache: current.items.isNotEmpty,
      );
    }
  }

  /// Explicit "Továbbiak betöltése" — the controller NEVER auto-paginates.
  /// The screen calls this from the load-more button (A3 / §5.1).
  Future<void> loadMore({int pageSize = defaultPageSize}) async {
    final current = state;
    if (current.status == FeedStatus.loading ||
        current.status == FeedStatus.refreshing ||
        current.status == FeedStatus.paging) {
      return;
    }
    if (current.status == FeedStatus.end) {
      // Already halted — no further pages exist. A second tap is a no-op.
      return;
    }
    final cursor = current.cursor;
    if (cursor == null || !cursor.isInitial && cursor.cursor == null) {
      // No cursor to follow — flip to end and bail out (defensive: this is
      // the case where a previous fetch halted but the status wasn't
      // updated, which can only happen if a future code path forgets to).
      state = current.copyWith(status: FeedStatus.end);
      return;
    }
    state = current.copyWith(status: FeedStatus.paging, lastError: null);

    try {
      final page = await _repository.followingFeed(
        cursor: cursor,
        limit: pageSize,
      );
      final merged = _mergeUnique(current.items, page.items);
      final cursorIsEnd = !page.cursor.isInitial && page.cursor.cursor == null;
      _seenIds.addAll(merged.map((p) => p.id.value).toSet());
      await _persistCache(merged);
      state = state.copyWith(
        status: cursorIsEnd ? FeedStatus.end : FeedStatus.content,
        items: merged,
        cursor: page.cursor,
        hasCache: true,
        refreshedAt: DateTime.now(),
        loadedFromCache: false,
      );
    } on AppFailure catch (failure) {
      _logger.warning(
        'community.feed.loadMore.failure',
        fields: {'items': current.items.length},
      );
      state = state.copyWith(
        status: current.items.isNotEmpty
            ? FeedStatus.content
            : FeedStatus.error,
        lastError: failure,
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'community.feed.loadMore.failure',
        error: error,
        stackTrace: stackTrace,
        fields: {'items': current.items.length},
      );
      state = state.copyWith(
        status: current.items.isNotEmpty
            ? FeedStatus.content
            : FeedStatus.error,
        lastError: UnknownFailure(
          code: FailureCode.unknown,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Retry from the error / offline state. Equivalent to [load] but does
  /// NOT clear the items already on screen — the user keeps what they
  /// were looking at and gets the new content merged on top.
  Future<void> retry({int pageSize = defaultPageSize}) =>
      load(pageSize: pageSize);

  // ---- internal helpers ------------------------------------------------

  /// Apply a freshly-fetched first page to the state. Replaces any cache
  /// the user was looking at with the server's authoritative response.
  void _absorbPage(
    CommunityPage<CommunityPost> page, {
    required bool fromCache,
  }) {
    // Clear the seen-id set BEFORE `_dedupe` (see the refresh comment
    // for the rationale — the order matters).
    _seenIds.clear();
    final items = _dedupe(page.items);
    _seenIds.addAll(items.map((p) => p.id.value));
    final cursorIsEnd = !page.cursor.isInitial && page.cursor.cursor == null;
    // Fire-and-forget cache persist — we do not await so the screen does
    // not block on storage; the cache is a snapshot, not the source of
    // truth.
    unawaited(_persistCache(items));
    state = FeedState(
      status: cursorIsEnd ? FeedStatus.end : FeedStatus.content,
      items: items,
      cursor: page.cursor,
      hasCache: items.isNotEmpty || fromCache,
      lastError: null,
      refreshedAt: DateTime.now(),
      loadedFromCache: false,
    );
  }

  /// Persist the visible items to the cache. A platform write refusal is
  /// logged but never thrown at the UI — the in-memory items stay the
  /// user's truth for the session (the same rule the draft store follows).
  Future<void> _persistCache(List<CommunityPost> items) async {
    try {
      final envelopes = <CachedFeedItem>[
        for (final post in items) _envelopeOf(post),
      ];
      await _cache.write(envelopes);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'community.feed.cache.persist_failed',
        error: error,
        stackTrace: stackTrace,
        fields: {'items': items.length},
      );
    }
  }

  /// Wrap a [CommunityPost] into a [CachedFeedItem] using the wire envelope
  /// the controller hands to the cache. The wire envelope is the cache's
  /// source of truth; the cache never inspects the artifact payload.
  ///
  /// The envelope mirrors the §10 / Kör 13 read shape — every field the
  /// card-registry reads is present; the artifact is stored as its raw
  /// `ShareArtifact.toJson()` map so a future round that wires the full
  /// Kör 13 schema can decode it losslessly. The Kör 14 cache stays
  /// read-only — the artifact is opaque here.
  CachedFeedItem _envelopeOf(CommunityPost post) {
    final envelope = <String, Object?>{
      'id': post.id.value,
      'authorId': post.authorId.value,
      'audience': post.audience.wireValue,
      'body': post.body,
      'createdAt': post.createdAt.toIso8601String(),
      'editedAt': post.editedAt?.toIso8601String(),
      'moderationState': post.moderationState.wireValue,
      'counts': <String, Object?>{
        'reactionCount': post.counts.reactionCount,
        'commentCount': post.counts.commentCount,
        'bookmarkCount': post.counts.bookmarkCount,
      },
      'viewerState': <String, Object?>{
        'bookmarkedAt': post.viewerState.bookmarkedAt?.toIso8601String(),
        'myReaction': post.viewerState.myReaction?.wireValue,
      },
      'artifact': _artifactEnvelope(post),
    };
    return CachedFeedItem(postId: post.id.value, envelope: envelope);
  }

  Object? _artifactEnvelope(CommunityPost post) {
    final artifact = post.artifact;
    // The artifact's sealed hierarchy is the source of truth — every
    // concrete subclass knows its own wire shape via `toJson()`. The cache
    // stores that verbatim, so a future round with the full Kör 13 decoder
    // round-trips losslessly. The Kör 14 controller, when rehydrating, only
    // needs the type discriminator to route to the right fallback card
    // (A5).
    if (artifact is UnfilledCommunityShareArtifact) {
      return <String, Object?>{'type': 'unfilled', 'schemaVersion': 0};
    }
    return _artifactJson(artifact);
  }

  /// Decode the sealed artifact's wire shape via its own `toJson()`. The
  /// runtime type is checked against the Kör 10 sealed subclasses; unknown
  /// artifact classes fall through to a typed-only stub so the cache never
  /// crashes on a future artifact type.
  Object? _artifactJson(CommunityShareArtifact artifact) {
    if (artifact is ShareArtifact) {
      return artifact.toJson();
    }
    return <String, Object?>{
      'type': 'unknown',
      'schemaVersion': artifact.schemaVersion,
      'sourceId': artifact.sourceId,
      'createdAt': artifact.createdAt.toIso8601String(),
    };
  }

  /// Rehydrate a list of cache envelopes into [CommunityPost]s. The
  /// rehydration is best-effort: a malformed envelope is skipped (the
  /// underlying [JsonCollectionStore] already quarantines these) and the
  /// rest stays usable.
  List<CommunityPost> _rehydrateAll(List<CachedFeedItem> items) {
    final result = <CommunityPost>[];
    for (final item in items) {
      try {
        result.add(_rehydrateOne(item.envelope));
      } on Object catch (error, stackTrace) {
        _logger.warning(
          'community.feed.cache.rehydrate_skipped',
          error: error,
          stackTrace: stackTrace,
          fields: {'postId': item.postId},
        );
      }
    }
    return result;
  }

  CommunityPost _rehydrateOne(Map<String, Object?> envelope) {
    final id = envelope['id'];
    final authorIdRaw = envelope['authorId'];
    final audienceRaw = envelope['audience'];
    final body = envelope['body'];
    final createdAtRaw = envelope['createdAt'];
    final editedAtRaw = envelope['editedAt'];
    final moderationRaw = envelope['moderationState'];
    final countsRaw = envelope['counts'];
    final viewerRaw = envelope['viewerState'];
    final artifactRaw = envelope['artifact'];

    if (id is! String || id.isEmpty) {
      throw const FormatException('envelope.id missing');
    }
    if (authorIdRaw is! String || authorIdRaw.isEmpty) {
      throw const FormatException('envelope.authorId missing');
    }
    if (audienceRaw is! String) {
      throw const FormatException('envelope.audience missing');
    }
    if (createdAtRaw is! String) {
      throw const FormatException('envelope.createdAt missing');
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) {
      throw const FormatException('envelope.createdAt not parseable');
    }
    final editedAt = editedAtRaw is String
        ? DateTime.tryParse(editedAtRaw)
        : null;
    final counts = _countsFromEnvelope(countsRaw);
    final viewerState = _viewerStateFromEnvelope(viewerRaw);
    final moderation = _moderationFromWire(moderationRaw);
    final audience = _audienceFromWire(audienceRaw);
    final artifact = _artifactFromEnvelope(artifactRaw);

    return CommunityPost(
      id: ContentId(id),
      authorId: PublicUserId(authorIdRaw),
      audience: audience,
      body: body is String ? body : null,
      artifact: artifact,
      createdAt: createdAt,
      editedAt: editedAt,
      moderationState: moderation,
      counts: counts,
      viewerState: viewerState,
    );
  }

  CommunityPostCounts _countsFromEnvelope(Object? raw) {
    if (raw is! Map) return _zeroCounts();
    final reaction = raw['reactionCount'];
    final comment = raw['commentCount'];
    final bookmark = raw['bookmarkCount'];
    return CommunityPostCounts(
      reactionCount: reaction is int && reaction >= 0 ? reaction : 0,
      commentCount: comment is int && comment >= 0 ? comment : 0,
      bookmarkCount: bookmark is int && bookmark >= 0 ? bookmark : 0,
    );
  }

  CommunityPostCounts _zeroCounts() =>
      CommunityPostCounts(reactionCount: 0, commentCount: 0, bookmarkCount: 0);

  CommunityViewerPostState _viewerStateFromEnvelope(Object? raw) {
    if (raw is! Map) return const CommunityViewerPostState.empty();
    final bookmarkedRaw = raw['bookmarkedAt'];
    final reactionRaw = raw['myReaction'];
    final bookmarked = bookmarkedRaw is String
        ? DateTime.tryParse(bookmarkedRaw)
        : null;
    final reactionKind = reactionRaw is String
        ? _reactionFromWire(reactionRaw)
        : null;
    return CommunityViewerPostState(
      bookmarkedAt: bookmarked,
      myReaction: reactionKind,
    );
  }

  ReactionKind? _reactionFromWire(String wire) {
    for (final kind in ReactionKind.values) {
      if (kind.wireValue == wire) return kind;
    }
    return null;
  }

  ModerationState _moderationFromWire(Object? raw) {
    if (raw is! String) return ModerationState.visible;
    for (final state in ModerationState.values) {
      if (state.wireValue == raw) return state;
    }
    return ModerationState.visible;
  }

  CommunityAudience _audienceFromWire(String wire) {
    for (final value in CommunityAudience.values) {
      if (value.wireValue == wire) return value;
    }
    return CommunityAudience.public;
  }

  CommunityShareArtifact _artifactFromEnvelope(Object? raw) {
    if (raw is! Map) return UnfilledCommunityShareArtifact();
    final typeRaw = raw['type'];
    if (typeRaw is! String) return UnfilledCommunityShareArtifact();
    if (typeRaw == 'unfilled') return UnfilledCommunityShareArtifact();
    if (typeRaw == 'unknown') {
      return UnfilledCommunityShareArtifact();
    }
    // F2 (review): the cache envelope persists the artifact's full wire
    // JSON via `artifact.toJson()` for every known `ShareArtifact`
    // subtype. Rehydrate through `ShareArtifact.fromJson` so a
    // cache-primed post renders its real card (the offline / fallback
    // path was always the headline feature — see §1). Any decode
    // failure (corrupt envelope, future-flavoured type the decoder
    // does not yet understand) collapses to `UnfilledCommunityShareArtifact`
    // so A5's "unknown type never crashes" guarantee still holds.
    try {
      return ShareArtifact.fromJson(raw);
    } on Object {
      return UnfilledCommunityShareArtifact();
    }
  }

  /// Deduplicate a freshly-fetched list against the current seen-id set.
  /// Order is preserved; duplicates are dropped in place. Returns a fresh
  /// list — the input is not mutated.
  List<CommunityPost> _dedupe(List<CommunityPost> items) {
    final out = <CommunityPost>[];
    for (final item in items) {
      if (_seenIds.add(item.id.value)) {
        out.add(item);
      }
    }
    return out;
  }

  /// Merge a new page into the existing list, keeping the existing order
  /// and dropping any post whose id was already on screen. Used by
  /// [loadMore] so a server-side overlap (a stale cursor that returned a
  /// duplicate row) never produces a duplicate in the UI (A4).
  List<CommunityPost> _mergeUnique(
    List<CommunityPost> existing,
    List<CommunityPost> incoming,
  ) {
    final out = <CommunityPost>[...existing];
    final incomingIds = <String>{};
    for (final post in incoming) {
      if (_seenIds.contains(post.id.value)) continue;
      if (incomingIds.contains(post.id.value)) continue;
      incomingIds.add(post.id.value);
      out.add(post);
    }
    return out;
  }
}

/// Provider for the [FeedController]. The screen reads this directly; the
/// repository / cache dependencies are pulled from the overrideable
/// providers [communityFeedRepositoryProvider] and [feedCacheProvider].
final feedControllerProvider = NotifierProvider<FeedController, FeedState>(
  FeedController.new,
);
