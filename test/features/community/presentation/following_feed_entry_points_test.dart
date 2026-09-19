/// Following-feed entry points — the compose FAB and the search action.
///
/// E18-R19 routed the feed, but the composer (E09-R12) and the profile
/// search (E09-R09) screens had no edge INTO them from the routed
/// surface. The feed screen now pushes both imperatively
/// (``Navigator.push`` — the edge the reachability tool measures):
///
/// * the ``FloatingActionButton`` opens [PostComposerScreen];
/// * the search ``IconButton`` in the app bar opens
///   [CommunitySearchScreen].
///
/// The harness is the ``following_feed_test.dart`` one (fake feed
/// repository + an in-memory cache) plus the composer seams the pushed
/// screen reads (``composer_audience_test.dart`` shape). The search
/// screen reads its repository only on a typed query, so the default
/// provider chain (account off → disabled repository) is enough.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/feed_controller.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/data/local/feed_cache.dart';
import 'package:strumsight/features/community/domain/entities/community_comment.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/feed_repository.dart';
import 'package:strumsight/features/community/domain/repositories/post_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/community_search_screen.dart';
import 'package:strumsight/features/community/presentation/screens/following_feed_screen.dart';
import 'package:strumsight/features/community/presentation/screens/post_composer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

class _FakeCommunityFeedRepository implements CommunityFeedRepository {
  int calls = 0;

  @override
  Future<CommunityPage<CommunityPost>> followingFeed({
    required Object cursor,
    required int limit,
  }) async {
    calls += 1;
    return CommunityPage<CommunityPost>(
      items: const <CommunityPost>[],
      cursor: const CursorPage.haltedAfterRequest(),
    );
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

/// Minimal fake — the pushed composer never submits in these tests, so
/// only `createPost` needs a body; every other method is unused.
class _FakeCommunityPostRepository implements CommunityPostRepository {
  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) async {
    return CommunityPost(
      id: ContentId('post-1'),
      authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f00'),
      audience: audience,
      body: body,
      artifact: UnfilledCommunityShareArtifact(),
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

  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._user);
  final AuthUser _user;
  @override
  Future<AuthUser?> build() async => _user;
}

Widget _harness(_FakeCommunityFeedRepository repository) {
  final store = InMemoryKeyValueStore();
  const logger = NoopAppLogger();
  return ProviderScope(
    overrides: [
      communityFeedRepositoryProvider.overrideWithValue(repository),
      feedCacheProvider.overrideWithValue(
        FeedCache.open(store: store, logger: logger, userId: 7),
      ),
      communityKeyValueStoreProvider.overrideWithValue(store),
      communityLoggerProvider.overrideWithValue(logger),
      communityPostRepositoryProvider.overrideWithValue(
        _FakeCommunityPostRepository(),
      ),
      authControllerProvider.overrideWith(
        () => _FakeAuthController(
          const AuthUser(id: 7, email: 'feed@strumsight.app'),
        ),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: FollowingFeedScreen(),
    ),
  );
}

void main() {
  // A „compose FAB" cellát az E18-vonal integrációja (2026-09-19) ejtette: a
  // szállított FAB a `communityWritesEnabled` kapu alatt áll és
  // `context.push(AppRoutes.communityCompose)`-zal navigál (a router ugyanazt
  // a zászlót kapuzza), nem `Navigator.push`-sal — a belépési pontot a
  // `test/app/routing/community_routes_test.dart` és a router-tábla méri.

  testWidgets('the search action pushes the CommunitySearchScreen', (
    tester,
  ) async {
    final repository = _FakeCommunityFeedRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    expect(find.byType(CommunitySearchScreen), findsNothing);
    final search = find.byIcon(Icons.search);
    expect(search, findsOneWidget);
    expect(find.byTooltip('Search people'), findsOneWidget);

    await tester.tap(search);
    await tester.pumpAndSettle();

    expect(find.byType(CommunitySearchScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the refresh action is still the only other app-bar action', (
    tester,
  ) async {
    final repository = _FakeCommunityFeedRepository();
    await tester.pumpWidget(_harness(repository));
    await tester.pumpAndSettle();

    // Search + refresh — the existing feed test taps `Icons.refresh` by
    // icon, so the new action must not shadow it.
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });
}
