// Golden snapshots of the E13-R33 community screens (belépő, profil,
// feed, keresés, profil-lista, szerkesztő, beszélgetés) at a compact
// portrait phone (412×915) and the same frame at textScaler 2.0, per the
// round brief §7/A9. Pattern follows the merged
// `test/ui/goldens/e13_r32_screens_golden_test.dart` precedent: `AppTheme`
// (the app's actual runtime theme) — each screen wraps itself in
// `CommunityThemeScope` internally, so this file does not need to.
//
// Recorded on x86_64 (ADR 0426, §0.0.B/B11) via `tools/golden-x86.sh
// record` — NOT `flutter test --update-goldens` on this (aarch64) box.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/feed_controller.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/data/local/feed_cache.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_comment.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/community_profile_repository.dart';
import 'package:strumsight/features/community/domain/repositories/feed_repository.dart';
import 'package:strumsight/features/community/domain/repositories/post_repository.dart';
import 'package:strumsight/features/community/domain/repositories/social_graph_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/bookmarks_screen.dart';
import 'package:strumsight/features/community/presentation/screens/comments_screen.dart';
import 'package:strumsight/features/community/presentation/screens/community_gate_screen.dart';
import 'package:strumsight/features/community/presentation/screens/community_search_screen.dart';
import 'package:strumsight/features/community/presentation/screens/edit_profile_screen.dart';
import 'package:strumsight/features/community/presentation/screens/followers_screen.dart';
import 'package:strumsight/features/community/presentation/screens/following_feed_screen.dart';
import 'package:strumsight/features/community/presentation/screens/post_composer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../core/storage/in_memory_key_value_store.dart';
import '../../support/fake_auth.dart';

const _compactPortrait = Size(412, 915);

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

class _FakeCommunityProfileRepository implements CommunityProfileRepository {
  _FakeCommunityProfileRepository({this.profile});
  CommunityProfile? profile;

  @override
  Future<CommunityProfile?> fetchMyProfile() async => profile;
  @override
  Future<CommunityProfile> fetchById(PublicUserId userId) =>
      throw UnsupportedError('golden fixture');
  @override
  Future<CommunityProfile?> fetchByHandle(CommunityHandle handle) =>
      throw UnsupportedError('golden fixture');
  @override
  Future<CommunityPage<CommunityProfile>> searchProfiles({
    required String query,
    required Object cursor,
  }) async => const CommunityPage<CommunityProfile>(
    items: <CommunityProfile>[],
    cursor: CursorPage.haltedAfterRequest(),
  );
  @override
  Future<AppResult<CommunityProfile>> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) => throw UnsupportedError('golden fixture');
}

List<Override> _authOverrides({CommunityProfile? profile}) => [
  appConfigProvider.overrideWith(
    (ref) => AppConfig.resolve(
      environment: AppEnvironment.development,
      apiBaseUrl: AppConfig.devApiBaseUrl,
      flags: FeatureFlags.forEnvironment(
        AppEnvironment.development,
        accountEnabled: true,
      ),
      diagnosticsToken: AppConfig.devDiagnosticsToken,
      buildMode: 'test',
      appVersion: 'test',
    ),
  ),
  tokenStoreProvider.overrideWithValue(FakeTokenStore('golden-token')),
  authRepositoryProvider.overrideWithValue(
    FakeAuthRepository(
      user: const AuthUser(id: 1, email: 'golden@strumsight.app'),
    ),
  ),
  communityProfileRepositoryProvider.overrideWithValue(
    _FakeCommunityProfileRepository(profile: profile),
  ),
];

CommunityProfile _profileFixture() => CommunityProfile(
  userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60'),
  handle: CommunityHandle('wolfcasaba'),
  displayName: 'Wolf Casaba',
  visibility: ProfileVisibility.followers,
  avatarUrl: null,
  bio: null,
  skillInterests: const <String>[],
  badges: const <String>[],
  relationship: CommunityRelationshipToViewer.notRelated,
  createdAt: DateTime.utc(2026, 8, 1),
);

// ---------------------------------------------------------------------------
// 1 — community_gate_screen.dart (UI-53)
// ---------------------------------------------------------------------------

Widget _gateScreen() => const CommunityGateScreen();
List<Override> _gateOverrides() => _authOverrides(profile: null);

// ---------------------------------------------------------------------------
// 2 — edit_profile_screen.dart (UI-53)
// ---------------------------------------------------------------------------

Widget _editProfileScreen() =>
    const EditProfileScreen(mode: EditProfileMode.create, initialProfile: null);
List<Override> _editProfileOverrides() => _authOverrides(profile: null);

// ---------------------------------------------------------------------------
// 3 — following_feed_screen.dart (UI-54)
// ---------------------------------------------------------------------------

class _FakeFeedRepository implements CommunityFeedRepository {
  @override
  Future<CommunityPage<CommunityPost>> followingFeed({
    required Object cursor,
    required int limit,
  }) async {
    final artifact = PracticeSummaryArtifact(
      schemaVersion: shareArtifactSchemaVersion,
      sourceId: 'sess-golden-1',
      createdAt: DateTime.utc(2026, 8, 23, 12),
      activeSeconds: 620,
      pausedSeconds: 40,
      attemptCount: 3,
      finishReasonCode: 'userFinished',
      bestScore: 0.82,
      coachingCodes: const <String>['strongDownBeats'],
    );
    return CommunityPage<CommunityPost>(
      items: <CommunityPost>[
        CommunityPost(
          id: ContentId('post-golden-1'),
          authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a10'),
          audience: CommunityAudience.followers,
          body: 'Ma sikerült végre a barré akkordos váltás!',
          artifact: artifact,
          createdAt: DateTime.utc(2026, 8, 23, 9),
          moderationState: ModerationState.visible,
          counts: CommunityPostCounts(
            reactionCount: 4,
            commentCount: 2,
            bookmarkCount: 1,
          ),
          viewerState: const CommunityViewerPostState.empty(),
        ),
      ],
      cursor: const CursorPage.haltedAfterRequest(),
    );
  }

  @override
  Future<CommunityPage<CommunityPost>> profilePosts({
    required PublicUserId userId,
    required Object cursor,
    required int limit,
  }) => throw UnsupportedError('golden fixture');

  @override
  Future<CommunityPage<CommunityPost>> clubPinned({
    required ContentId clubId,
    required Object cursor,
    required int limit,
  }) => throw UnsupportedError('golden fixture');
}

Widget _followingFeedScreen() => const FollowingFeedScreen();
List<Override> _followingFeedOverrides() => [
  communityFeedRepositoryProvider.overrideWithValue(_FakeFeedRepository()),
  feedCacheProvider.overrideWithValue(
    FeedCache.open(
      store: InMemoryKeyValueStore(),
      logger: const NoopAppLogger(),
      userId: 1,
    ),
  ),
];

// ---------------------------------------------------------------------------
// 4 — community_search_screen.dart (UI-55)
// ---------------------------------------------------------------------------

Widget _searchScreen() => const CommunitySearchScreen();
List<Override> _searchOverrides() => [
  communityProfileRepositoryProvider.overrideWithValue(
    _FakeCommunityProfileRepository(),
  ),
];

// ---------------------------------------------------------------------------
// 5 — followers_screen.dart / bookmarks_screen.dart (UI-56)
// ---------------------------------------------------------------------------

class _FakeSocialGraphRepository implements SocialGraphRepository {
  @override
  Future<CommunityPage<CommunityProfile>> followersPage({
    required PublicUserId userId,
    required Object cursor,
  }) async => CommunityPage<CommunityProfile>(
    items: <CommunityProfile>[
      _profileFixture(),
      CommunityProfile(
        userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a20'),
        handle: CommunityHandle('szitakoto'),
        displayName: 'Szita Kóto',
        visibility: ProfileVisibility.followers,
        avatarUrl: null,
        bio: null,
        skillInterests: const <String>[],
        badges: const <String>[],
        relationship: CommunityRelationshipToViewer.notRelated,
        createdAt: DateTime.utc(2026, 7, 15),
      ),
    ],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityPage<CommunityProfile>> followingPage({
    required PublicUserId userId,
    required Object cursor,
  }) => throw UnsupportedError('golden fixture');

  @override
  Future<ContentId> follow({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> unfollow({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> removeFollower({
    required PublicUserId follower,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> acceptFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> declineFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> block({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> unblock({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> mute({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> unmute({
    required PublicUserId target,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<CommunityPage<CommunityProfile>> blockedProfilesPage({
    required Object cursor,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<CommunityPage<CommunityProfile>> mutedProfilesPage({
    required Object cursor,
  }) => throw UnsupportedError('golden fixture');
}

Widget _followersScreen() => FollowersScreen(
  profileId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60'),
  mode: FollowersMode.followers,
);
List<Override> _followersOverrides() => [
  socialGraphRepositoryProvider.overrideWithValue(_FakeSocialGraphRepository()),
];

Widget _bookmarksScreen() => const BookmarksScreen();
List<Override> _bookmarksOverrides() => [
  bookmarksProvider.overrideWith(
    (ref) => Stream.value(
      BookmarksState(
        rows: <BookmarkRow>[
          BookmarkRow(
            id: 1,
            postId: ContentId('post-golden-1'),
            createdAt: DateTime.utc(2026, 8, 20),
            isTombstone: false,
          ),
          BookmarkRow(
            id: 2,
            postId: ContentId('post-golden-2'),
            createdAt: DateTime.utc(2026, 8, 18),
            isTombstone: true,
          ),
        ],
        nextCursor: const CursorPage.haltedAfterRequest(),
        isLoadingMore: false,
        isRemoving: false,
      ),
    ),
  ),
];

// ---------------------------------------------------------------------------
// 6 — post_composer_screen.dart (UI-57)
// ---------------------------------------------------------------------------

class _FakeCommunityPostRepository implements CommunityPostRepository {
  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) =>
      throw UnsupportedError('golden fixture');
  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
}

class _GoldenAuthController extends AuthController {
  @override
  Future<AuthUser?> build() async =>
      const AuthUser(id: 1, email: 'golden@strumsight.app');
}

Map<String, Object?> _composerArtifactFixture() {
  return PracticeSummaryArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'sess-golden-composer',
    createdAt: DateTime.utc(2026, 8, 23, 12),
    activeSeconds: 300,
    pausedSeconds: 10,
    attemptCount: 2,
    finishReasonCode: 'userFinished',
    bestScore: 0.7,
    coachingCodes: const <String>[],
  ).toJson();
}

Widget _composerScreen() => const PostComposerScreen();
List<Override> _composerOverrides() => [
  communityKeyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
  communityLoggerProvider.overrideWithValue(const NoopAppLogger()),
  communityPostRepositoryProvider.overrideWithValue(
    _FakeCommunityPostRepository(),
  ),
  composerSourceArtifactProvider.overrideWithValue(_composerArtifactFixture()),
  authControllerProvider.overrideWith(() => _GoldenAuthController()),
];

// ---------------------------------------------------------------------------
// 7 — comments_screen.dart (UI-58)
// ---------------------------------------------------------------------------

class _ScriptedCommentRepository implements CommunityPostRepository {
  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) async => CommunityPage<CommunityComment>(
    items: <CommunityComment>[
      CommunityComment(
        id: ContentId('comment-golden-1'),
        authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a30'),
        postId: ContentId('post-golden-1'),
        parentCommentId: null,
        body: 'Szuper, gratulálok!',
        createdAt: DateTime.utc(2026, 8, 23, 10),
        moderationState: ModerationState.visible,
      ),
      CommunityComment(
        id: ContentId('comment-golden-2'),
        authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a31'),
        postId: ContentId('post-golden-1'),
        parentCommentId: null,
        body: 'Ez a komment el lett távolítva moderálás miatt.',
        createdAt: DateTime.utc(2026, 8, 23, 11),
        moderationState: ModerationState.removed,
      ),
    ],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<CommunityPost?> fetchPost({required ContentId postId}) =>
      throw UnsupportedError('golden fixture');
  @override
  Future<CommunityPost> updatePost({
    required ContentId postId,
    required String? body,
    required CommunityAudience audience,
    required Object resourceVersion,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> deletePost({
    required ContentId postId,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> setReaction({
    required ContentId postId,
    required Object? kind,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> setBookmark({
    required ContentId postId,
    required bool bookmarked,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<CommunityComment> createComment({
    required ContentId postId,
    required ContentId? parentCommentId,
    required String body,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<CommunityComment> updateComment({
    required ContentId commentId,
    required String body,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
  @override
  Future<void> deleteComment({
    required ContentId commentId,
    required String idempotencyKey,
  }) => throw UnsupportedError('golden fixture');
}

Widget _commentsScreen() => CommentsScreen(postId: ContentId('post-golden-1'));
List<Override> _commentsOverrides() => [
  communityPostRepositoryProvider.overrideWithValue(
    _ScriptedCommentRepository(),
  ),
];

// ---------------------------------------------------------------------------
// Pump / golden helpers
// ---------------------------------------------------------------------------

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  List<Override> overrides, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screens = <String, (Widget Function(), List<Override> Function())>{
    'gate': (_gateScreen, _gateOverrides),
    'edit_profile': (_editProfileScreen, _editProfileOverrides),
    'following_feed': (_followingFeedScreen, _followingFeedOverrides),
    'search': (_searchScreen, _searchOverrides),
    'followers': (_followersScreen, _followersOverrides),
    'bookmarks': (_bookmarksScreen, _bookmarksOverrides),
    'composer': (_composerScreen, _composerOverrides),
    'comments': (_commentsScreen, _commentsOverrides),
  };

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    for (final entry in screens.entries) {
      testWidgets('${entry.key} — $suffix', (tester) async {
        final (widgetBuilder, overridesBuilder) = entry.value;
        await _pump(
          tester,
          widgetBuilder(),
          overridesBuilder(),
          textScale: textScale,
        );
        await _expectGolden(tester, 'e13_r33_${entry.key}_$suffix');
      });
    }
  }
}
