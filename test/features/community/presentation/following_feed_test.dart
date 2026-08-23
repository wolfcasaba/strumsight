/// Following-feed widget tests (E09-R14).
///
/// Covers the §6 / §6.1 acceptance matrix for the following-feed
/// surface. Every cell has at least one dedicated test so a default
/// fixture cannot hide a regression:
///
/// * A1 — network failure does NOT crash the feed (error state).
/// * A2 — cache is per-user; account switch never returns the previous
///   user's snapshot.
/// * A3 — no autoplay, no auto-scroll-pagination (the explicit button
///   is the only path).
/// * A4 — duplicate post never appears in a single session (refresh
///   or loadMore that returns an already-seen id is dropped).
/// * A5 — unknown artifact type renders the fallback card, not a crash.
/// * A6 — explicit end-of-feed state (button disabled, end card visible).
/// * A7 — pull-to-refresh preserves the first-visible row and signals
///   the new content arrived.
///
/// The fake repository records every call so the tests assert the
/// controller's contract — not the repository's. The test cache is
/// bound to an [InMemoryKeyValueStore] and opened per userId; A2
/// asserts the storage key differs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/community/application/controllers/feed_controller.dart';
import 'package:strumsight/features/community/data/local/feed_cache.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/feed_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/following_feed_screen.dart';
import 'package:strumsight/features/community/presentation/widgets/feed_card_registry.dart';

import '../../../../core/storage/in_memory_key_value_store.dart';

// ---------------------------------------------------------------------------
// Fixture data — CommunityPost + ShareArtifact builders
// ---------------------------------------------------------------------------

const _userIdA = 1001;
const _userIdB = 1002;

PracticeSummaryArtifact _practiceArtifact({
  String sourceId = 'sess-fixture-1',
}) {
  return PracticeSummaryArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: sourceId,
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    activeSeconds: 60,
    pausedSeconds: 5,
    attemptCount: 1,
    finishReasonCode: 'userFinished',
    bestScore: 0.85,
    coachingCodes: const <String>['strongDownBeats'],
  );
}

SongResultArtifact _songArtifact() {
  return SongResultArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'song-fixture-1',
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    songName: 'Sample Song',
    chords: const <String>['C', 'G', 'Am', 'F'],
    strumPattern: 'd-d-u-d',
    bpm: 90,
    beatsPerBar: 4,
  );
}

OriginalProgressionArtifact _progressionArtifact() {
  return OriginalProgressionArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'song-fixture-2',
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    songName: 'My Progression',
    chords: const <String>['Am', 'F', 'C', 'G'],
    strumPattern: 'd---du-u-',
    bpm: 110,
    beatsPerBar: 4,
  );
}

PlanTemplateArtifact _planArtifact() {
  return PlanTemplateArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'song-fixture-3',
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    songName: 'Plan template',
    chords: const <String>['C', 'G'],
    strumPattern: 'd-d-d-d',
    bpm: 80,
    beatsPerBar: 4,
  );
}

AnalysisImprovementArtifact _analysisArtifact() {
  return AnalysisImprovementArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'analysis-fixture-1',
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    metrics: const <MetricImprovement>[
      MetricImprovement(
        metricId: 'tempo',
        directionCode: 'improved',
        beforeValue: 80,
        afterValue: 90,
        relativeDelta: 0.125,
      ),
    ],
  );
}

AchievementArtifact _achievementArtifact() {
  return AchievementArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'achievement-fixture-1',
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    achievementId: 'first_strum',
    categoryCode: 'practice',
    catalogVersion: 1,
    progressValue: 1,
    completedAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
  );
}

ChallengeArtifact _challengeArtifact() {
  return ChallengeArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'challenge-fixture-1',
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    challengeTypeCode: 'strumPattern',
    challengeName: 'Daily strum drill',
    rewardStatusCode: 'verified',
    completedAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    rewardXp: 50,
    ledgerId: 'ledger-fixture-1',
  );
}

CommunityPost _post({
  required String id,
  required CommunityShareArtifact artifact,
  String body = 'Fixture body text.',
  String authorSuffix = 'a01',
  CommunityAudience audience = CommunityAudience.public,
}) {
  return CommunityPost(
    id: ContentId(id),
    authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5$authorSuffix'),
    audience: audience,
    body: body,
    artifact: artifact,
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    moderationState: ModerationState.visible,
    counts: CommunityPostCounts(
      reactionCount: 0,
      commentCount: 0,
      bookmarkCount: 0,
    ),
    viewerState: const CommunityViewerPostState.empty(),
  );
}

List<CommunityPost> _postsFor(CommunityShareArtifact Function(int i) make) {
  return <CommunityPost>[
    for (var i = 0; i < 3; i++) _post(id: 'post-$i', artifact: make(i)),
  ];
}

// ---------------------------------------------------------------------------
// Fake repository — records every call, lets tests script pages
// ---------------------------------------------------------------------------

class _FakeCommunityFeedRepository implements CommunityFeedRepository {
  _FakeCommunityFeedRepository();

  /// Programmable next response. The next ``followingFeed`` call pops
  /// this queue.
  final List<CommunityPage<CommunityPost>> scriptedPages =
      <CommunityPage<CommunityPost>>[];

  /// Programmable next throw. The next ``followingFeed`` call consumes
  /// this.
  Object? nextThrow;

  /// Recorded calls.
  final List<Object> cursors = <Object>[];
  final List<int> limits = <int>[];

  @override
  Future<CommunityPage<CommunityPost>> followingFeed({
    required Object cursor,
    required int limit,
  }) async {
    cursors.add(cursor);
    limits.add(limit);
    final throwable = nextThrow;
    if (throwable != null) {
      nextThrow = null;
      throw throwable;
    }
    if (scriptedPages.isEmpty) {
      // Default to a halted page so callers don't accidentally loop.
      return CommunityPage<CommunityPost>(
        items: const <CommunityPost>[],
        cursor: const CursorPage.haltedAfterRequest(),
      );
    }
    return scriptedPages.removeAt(0);
  }

  @override
  Future<CommunityPage<CommunityPost>> profilePosts({
    required PublicUserId userId,
    required Object cursor,
    required int limit,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityPost>> clubPinned({
    required ContentId clubId,
    required Object cursor,
    required int limit,
  }) => throw UnsupportedError('not used in this test');
}

// ---------------------------------------------------------------------------
// Test harness — ProviderScope with overrides
// ---------------------------------------------------------------------------

class _Harness {
  _Harness({required this.repository, required this.cache});

  final _FakeCommunityFeedRepository repository;
  final FeedCache cache;
}

Widget _harness(_Harness h) {
  return ProviderScope(
    overrides: <Override>[
      communityFeedRepositoryProvider.overrideWithValue(h.repository),
      feedCacheProvider.overrideWithValue(h.cache),
    ],
    child: const MaterialApp(home: FollowingFeedScreen()),
  );
}

_Harness _buildHarness({int userId = _userIdA}) {
  final store = InMemoryKeyValueStore();
  final logger = const NoopAppLogger();
  final repo = _FakeCommunityFeedRepository();
  final cache = FeedCache.open(store: store, logger: logger, userId: userId);
  return _Harness(repository: repo, cache: cache);
}

// ---------------------------------------------------------------------------
// Tests — one block per acceptance cell
// ---------------------------------------------------------------------------

void main() {
  group('A1 — network failure does not crash the feed', () {
    testWidgets(
      'shows the error state with a retry button when no cache exists',
      (tester) async {
        final h = _buildHarness();
        h.repository.nextThrow = const NetworkFailure(
          code: FailureCode.networkUnavailable,
        );
        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        expect(find.text('A feed nem tölthető be.'), findsOneWidget);
        expect(find.text('Újrapróbálkozás'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'falls back to the offline state when a cache snapshot exists',
      (tester) async {
        final h = _buildHarness();
        // Prime the cache with one item.
        final post = _post(id: 'cached-1', artifact: _practiceArtifact());
        await h.cache.write(<CachedFeedItem>[
          CachedFeedItem(
            postId: post.id.value,
            envelope: _envelopeOfForTest(post),
          ),
        ]);
        h.repository.nextThrow = const NetworkFailure(
          code: FailureCode.networkUnavailable,
        );
        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        // The cached post is visible AND the offline banner is up.
        expect(
          find.text('Offline · a helyi másolat jelenik meg.'),
          findsOneWidget,
        );
        expect(find.text('Fixture body text.'), findsOneWidget);
      },
    );
  });

  group('A2 — cache is per-user; account switch never leaks', () {
    test('storage key contains the userId', () {
      expect(
        FeedCache.storageKeyFor(_userIdA),
        'ss.community.feed.v1.$_userIdA',
      );
      expect(
        FeedCache.storageKeyFor(_userIdB),
        'ss.community.feed.v1.$_userIdB',
      );
      expect(
        FeedCache.storageKeyFor(_userIdA),
        isNot(equals(FeedCache.storageKeyFor(_userIdB))),
      );
    });

    testWidgets('two caches against different userIds never share data', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      final logger = const NoopAppLogger();
      final cacheA = FeedCache.open(
        store: store,
        logger: logger,
        userId: _userIdA,
      );
      final cacheB = FeedCache.open(
        store: store,
        logger: logger,
        userId: _userIdB,
      );

      final post = _post(
        id: 'user-a-only',
        artifact: _practiceArtifact(),
        authorSuffix: 'a01',
      );
      await cacheA.write(<CachedFeedItem>[
        CachedFeedItem(
          postId: post.id.value,
          envelope: _envelopeOfForTest(post),
        ),
      ]);

      // User B's cache is empty even though both caches target the
      // same backing store.
      expect(cacheB.read(), isEmpty);

      // User A's cache holds the post.
      final aItems = cacheA.read();
      expect(aItems, hasLength(1));
      expect(aItems.single.postId, 'user-a-only');
    });
  });

  group('A3 — no autoplay, no auto-scroll-pagination', () {
    testWidgets(
      'the rendered widget tree never installs a scroll listener that triggers loadMore',
      (tester) async {
        final h = _buildHarness();
        final posts = _postsFor((_) => _practiceArtifact());
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: posts,
            cursor: CursorPage.continued('cursor-1'),
          ),
        );
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: <CommunityPost>[],
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );

        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        // The repository was called exactly once — the initial load.
        // No automatic loadMore fired on first paint.
        expect(h.repository.cursors, hasLength(1));
        expect(h.repository.cursors.single is CursorPage, isTrue);
        final firstCursor = h.repository.cursors.single as CursorPage;
        expect(firstCursor.isInitial, isTrue);

        // Scroll to the bottom of the list — no further repository call
        // should be triggered automatically (A3).
        await tester.drag(find.byType(ListView), const Offset(0, -10000));
        await tester.pumpAndSettle();

        expect(
          h.repository.cursors,
          hasLength(1),
          reason: 'no auto-scroll-pagination',
        );

        // Tapping "Továbbiak betöltése" is the ONLY path to the second
        // call — confirms the button exists and is the explicit gate.
        expect(find.text('Továbbiak betöltése'), findsOneWidget);
        await tester.tap(find.text('Továbbiak betöltése'));
        await tester.pumpAndSettle();

        expect(h.repository.cursors, hasLength(2));
        final secondCursor = h.repository.cursors.last as CursorPage;
        expect(secondCursor.cursor, equals('cursor-1'));
      },
    );

    testWidgets(
      'no video / audio widget is auto-started — every card is inert on load',
      (tester) async {
        final h = _buildHarness();
        final songPost = _post(id: 'song-1', artifact: _songArtifact());
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: <CommunityPost>[songPost],
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );

        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        // No VideoPlayerController, no AudioPlayer, no auto-playing
        // widget. The widget tree must hold exactly one FeedCard and
        // that card must be inert (no tap-to-play surfaced).
        expect(find.byType(FeedCard), findsOneWidget);
        // No autoplay icons.
        expect(find.byIcon(Icons.play_circle_filled), findsNothing);
        expect(find.byIcon(Icons.volume_up), findsNothing);
      },
    );
  });

  group('A4 — no duplicate post in a single session', () {
    testWidgets(
      'loadMore that returns an already-seen post does not duplicate it on screen',
      (tester) async {
        final h = _buildHarness();
        final firstPage = _postsFor((_) => _practiceArtifact());
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: firstPage,
            cursor: CursorPage.continued('cursor-1'),
          ),
        );
        // Second page OVERLAPS — the first post is already on screen.
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: firstPage,
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );

        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        // Tap "Továbbiak betöltése" — the duplicate-first-post response
        // is dropped; the visible list does NOT grow.
        await tester.tap(find.text('Továbbiak betöltése'));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(FollowingFeedScreen)),
        );
        final state = container.read(feedControllerProvider);
        expect(state.items, hasLength(firstPage.length));
        // No duplicate ids.
        final ids = state.items.map((p) => p.id.value).toList();
        expect(ids.toSet().length, equals(ids.length));
      },
    );

    testWidgets(
      'a refresh that returns a subset of the cache replaces, not merges, the list',
      (tester) async {
        final h = _buildHarness();
        final first = _post(id: 'post-A', artifact: _practiceArtifact());
        final second = _post(id: 'post-B', artifact: _songArtifact());
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: <CommunityPost>[first, second],
            cursor: CursorPage.continued('cursor-1'),
          ),
        );
        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        // Server returns ONLY first on the next fetch.
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: <CommunityPost>[first],
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );
        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(FollowingFeedScreen)),
        );
        final state = container.read(feedControllerProvider);
        // second was deleted server-side — must be gone from the list.
        expect(state.items.map((p) => p.id.value), equals(<String>['post-A']));
      },
    );
  });

  group('A5 — unknown artifact type renders a fallback card, not a crash', () {
    testWidgets(
      'an artifact whose runtime type is not in the registry renders the fallback card',
      (tester) async {
        final h = _buildHarness();
        final post = _post(
          id: 'mystery-1',
          // The registry exhaustively maps every concrete
          // ShareArtifactType; a card whose artifact is the placeholder
          // `UnfilledCommunityShareArtifact` exercises the
          // fallback path (A5). The fallback's content must NOT crash
          // the feed and must NOT auto-play anything.
          artifact: UnfilledCommunityShareArtifact(),
        );
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: <CommunityPost>[post],
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );

        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // Fallback copy.
        expect(
          find.text('Ehhez a poszthoz nincs megjeleníthető tartalom.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'every one of the seven known artifact types renders without throwing',
      (tester) async {
        final posts = <CommunityPost>[
          _post(id: 'p-1', artifact: _practiceArtifact()),
          _post(id: 'p-2', artifact: _songArtifact()),
          _post(id: 'p-3', artifact: _progressionArtifact()),
          _post(id: 'p-4', artifact: _planArtifact()),
          _post(id: 'p-5', artifact: _analysisArtifact()),
          _post(id: 'p-6', artifact: _achievementArtifact()),
          _post(id: 'p-7', artifact: _challengeArtifact()),
        ];
        final h = _buildHarness();
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: posts,
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );
        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        // Every one of the seven cards rendered without crashing.
        expect(tester.takeException(), isNull);
        expect(find.byType(FeedCard), findsNWidgets(7));
      },
    );
  });

  group('A6 — explicit end-of-feed state', () {
    testWidgets(
      'a halted response leaves the end-of-feed marker and a CTA on screen',
      (tester) async {
        final h = _buildHarness();
        final post = _post(id: 'last-1', artifact: _practiceArtifact());
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: <CommunityPost>[post],
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );

        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        expect(find.text('Elérted a feed végét.'), findsOneWidget);
        expect(find.text('Gyakorlás indítása'), findsOneWidget);
        // The "Továbbiak betöltése" button is NOT shown in the end
        // state (the cursor is halted; tapping it would be a no-op).
        expect(find.text('Továbbiak betöltése'), findsNothing);
      },
    );
  });

  group('A7 — pull-to-refresh preserves scroll position', () {
    testWidgets(
      'the refresh action replaces the items without jumping the list to the top',
      (tester) async {
        final h = _buildHarness();
        // A long first page so the list is scrollable.
        final first = <CommunityPost>[
          for (var i = 0; i < 12; i++)
            _post(
              id: 'p-$i',
              artifact: _practiceArtifact(sourceId: 's-$i'),
            ),
        ];
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: first,
            cursor: CursorPage.continued('cursor-1'),
          ),
        );
        // Refresh returns the same first page.
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: first,
            cursor: CursorPage.continued('cursor-1'),
          ),
        );

        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        // Scroll the list down a few cards before refreshing.
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();

        final scrollController = Scrollable.of(find.byType(ListView)).position;
        final scrollBefore = scrollController.pixels;
        expect(scrollBefore, greaterThan(0));

        // Tap the refresh icon — the controller refetches the first
        // page. The screen must NOT jump the list back to the top
        // (A7).
        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pumpAndSettle();

        final scrollAfter = scrollController.pixels;
        // The exact pixel may shift because the rebuilt list re-lays
        // out, but the scroll position must remain anchored to the
        // same first-visible row (A7 — scroll position is preserved).
        expect(
          (scrollAfter - scrollBefore).abs() < 200,
          isTrue,
          reason:
              'refresh must not jump the list to the top '
              '(was $scrollBefore, now $scrollAfter)',
        );

        // The controller transitioned back to content (the refresh
        // succeeded).
        final container = ProviderScope.containerOf(
          tester.element(find.byType(FollowingFeedScreen)),
        );
        final state = container.read(feedControllerProvider);
        expect(state.status, equals(FeedStatus.content));
      },
    );
  });

  group('Real-violation probe for A3', () {
    testWidgets(
      'a future regression that installs a scroll-listener auto-pagination '
      'would surface as a second repository call after a drag',
      (tester) async {
        // The probe is the assertion ITSELF: scrolling to the bottom of
        // the rendered list must NOT trigger another ``followingFeed``
        // call. If a future patch adds a `NotificationListener` that
        // calls ``loadMore`` on scroll, the test flips red.
        final h = _buildHarness();
        final posts = _postsFor((_) => _practiceArtifact());
        h.repository.scriptedPages.add(
          CommunityPage<CommunityPost>(
            items: posts,
            cursor: CursorPage.continued('cursor-1'),
          ),
        );
        await tester.pumpWidget(_harness(h));
        await tester.pumpAndSettle();

        // A large drag — the list reaches the bottom.
        for (var i = 0; i < 5; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -2000));
          await tester.pump();
        }
        await tester.pumpAndSettle();

        // No scroll-driven loadMore — the controller should have
        // received exactly one call (the initial load).
        expect(h.repository.cursors, hasLength(1));
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helpers — must stay aligned with FeedController._envelopeOf
// ---------------------------------------------------------------------------

Map<String, Object?> _envelopeOfForTest(CommunityPost post) {
  return <String, Object?>{
    'id': post.id.value,
    'authorId': post.authorId.value,
    'audience': post.audience.wireValue,
    'body': post.body,
    'createdAt': post.createdAt.toIso8601String(),
    'editedAt': null,
    'moderationState': post.moderationState.wireValue,
    'counts': <String, Object?>{
      'reactionCount': post.counts.reactionCount,
      'commentCount': post.counts.commentCount,
      'bookmarkCount': post.counts.bookmarkCount,
    },
    'viewerState': <String, Object?>{'bookmarkedAt': null, 'myReaction': null},
    'artifact': <String, Object?>{'type': 'unfilled', 'schemaVersion': 0},
  };
}
