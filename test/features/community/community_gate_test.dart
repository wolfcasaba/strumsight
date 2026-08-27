/// E13-R33 — community gate group: A1, A7, A8.
///
/// * A1 — the product's core works fully without community: the gate never
///   creates a profile implicitly, and the disabled/logged-out states never
///   surface a "create profile" CTA (the community feature is opt-in,
///   ADR 0291 §1).
/// * A7 — removed content gets a visible placeholder, in both the feed
///   (`FeedCard`) and the comment thread (`CommentsScreen`'s tile) — never a
///   silent gap in the conversation.
/// * A8 — username validation rejects bad input before it reaches the
///   repository: no `createProfile` call for a handle that fails the
///   structural check.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart'
    show communityPostRepositoryProvider;
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_comment.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/community_profile_repository.dart';
import 'package:strumsight/features/community/domain/repositories/post_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/comments_screen.dart';
import 'package:strumsight/features/community/presentation/screens/community_gate_screen.dart';
import 'package:strumsight/features/community/presentation/screens/edit_profile_screen.dart';
import 'package:strumsight/features/community/presentation/widgets/feed_card_registry.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_auth.dart';

// ---------------------------------------------------------------------------
// A1 fixtures
// ---------------------------------------------------------------------------

class _FakeCommunityProfileRepository implements CommunityProfileRepository {
  _FakeCommunityProfileRepository({this.profile});

  CommunityProfile? profile;
  int createCalls = 0;

  @override
  Future<CommunityProfile?> fetchMyProfile() async => profile;

  @override
  Future<CommunityProfile> fetchById(PublicUserId userId) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<CommunityProfile?> fetchByHandle(CommunityHandle handle) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<CommunityPage<CommunityProfile>> searchProfiles({
    required String query,
    required Object cursor,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<AppResult<CommunityProfile>> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  }) async {
    createCalls++;
    final created = CommunityProfile(
      userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60'),
      handle: handle,
      displayName: displayName,
      visibility: visibility,
      avatarUrl: null,
      bio: null,
      skillInterests: const <String>[],
      badges: const <String>[],
      relationship: CommunityRelationshipToViewer.notRelated,
      createdAt: DateTime.utc(2026),
    );
    profile = created;
    return Success(created);
  }

  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) => throw UnsupportedError('not used in this test');
}

ProviderScope _gateScope({
  required _FakeCommunityProfileRepository repo,
  required bool accountEnabled,
  AuthUser? user,
  String? token,
}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWith(
        (ref) => AppConfig.resolve(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags.forEnvironment(
            AppEnvironment.development,
            accountEnabled: accountEnabled,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
      tokenStoreProvider.overrideWithValue(FakeTokenStore(token)),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          user: user ?? const AuthUser(id: 1, email: 'player@strumsight.app'),
        ),
      ),
      communityProfileRepositoryProvider.overrideWithValue(repo),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: CommunityGateScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// A7 fixtures
// ---------------------------------------------------------------------------

CommunityPost _post({required ModerationState moderationState}) {
  return CommunityPost(
    id: ContentId('post-removed-1'),
    authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a99'),
    audience: CommunityAudience.followers,
    body: 'this body must never render once removed',
    artifact: UnfilledCommunityShareArtifact(),
    createdAt: DateTime.utc(2026, 8, 20, 10),
    moderationState: moderationState,
    counts: CommunityPostCounts(
      reactionCount: 0,
      commentCount: 0,
      bookmarkCount: 0,
    ),
    viewerState: const CommunityViewerPostState.empty(),
  );
}

class _ScriptedCommentRepository implements CommunityPostRepository {
  _ScriptedCommentRepository(this._firstPage);
  final CommunityPage<CommunityComment> _firstPage;

  @override
  Future<CommunityPage<CommunityComment>> comments({
    required ContentId postId,
    required Object cursor,
    required int limit,
  }) async => _firstPage;

  @override
  Future<CommunityPost> createPost({
    required CommunityAudience audience,
    required String? body,
    required Object artifact,
    required String idempotencyKey,
  }) => throw UnsupportedError('not used in this test');

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

// ---------------------------------------------------------------------------
// A8 fixtures
// ---------------------------------------------------------------------------

Widget _editProfileHarness(_FakeCommunityProfileRepository repo) {
  return ProviderScope(
    overrides: [
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
      tokenStoreProvider.overrideWithValue(FakeTokenStore('test-token')),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          user: const AuthUser(id: 1, email: 'player@strumsight.app'),
        ),
      ),
      communityProfileRepositoryProvider.overrideWithValue(repo),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: EditProfileScreen(
        mode: EditProfileMode.create,
        initialProfile: null,
      ),
    ),
  );
}

void main() {
  group('A1 — the product core works without community', () {
    testWidgets('disabled account layer shows no create-profile CTA', (
      tester,
    ) async {
      final repo = _FakeCommunityProfileRepository();
      await tester.pumpWidget(
        _gateScope(repo: repo, accountEnabled: false, user: null),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Community is not available in this build'),
        findsOneWidget,
      );
      expect(find.text('Create profile'), findsNothing);
      // Declining the gate never touches the repository — the core product
      // is not gated on this feature at all.
      expect(repo.createCalls, 0);
    });

    testWidgets('the profile-missing gate never creates a profile implicitly', (
      tester,
    ) async {
      final repo = _FakeCommunityProfileRepository(profile: null);
      await tester.pumpWidget(
        _gateScope(
          repo: repo,
          accountEnabled: true,
          user: const AuthUser(id: 1, email: 'player@strumsight.app'),
          token: 'test-token',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create profile'), findsOneWidget);
      // The CTA is rendered, but merely showing the gate never fires a
      // create — creation is only ever an explicit user action.
      expect(repo.createCalls, 0);
    });
  });

  group('A7 — removed content gets a visible placeholder', () {
    testWidgets('FeedCard renders a placeholder for a removed post, never '
        'the body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FeedCard(
              post: _post(moderationState: ModerationState.removed),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('this body must never render once removed'),
        findsNothing,
      );
      expect(find.text('This content was removed.'), findsOneWidget);
    });

    testWidgets('FeedCard renders the real body for a visible post', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FeedCard(
              post: _post(moderationState: ModerationState.visible),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('this body must never render once removed'),
        findsOneWidget,
      );
      expect(find.text('This content was removed.'), findsNothing);
    });

    testWidgets(
      'CommentsScreen renders a placeholder for a removed comment, never '
      'the body or author',
      (tester) async {
        final removedComment = CommunityComment(
          id: ContentId('comment-removed-1'),
          authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a77'),
          postId: ContentId('post-1'),
          parentCommentId: null,
          body: 'this comment body must never render once removed',
          createdAt: DateTime.utc(2026, 8, 20, 11),
          moderationState: ModerationState.removed,
        );
        final repo = _ScriptedCommentRepository(
          CommunityPage<CommunityComment>(
            items: <CommunityComment>[removedComment],
            cursor: const CursorPage.haltedAfterRequest(),
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              communityPostRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: CommentsScreen(postId: ContentId('post-1')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('this comment body must never render once removed'),
          findsNothing,
        );
        expect(
          find.text('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a77'),
          findsNothing,
          reason: "a removed comment's author id must not render either",
        );
        expect(find.text('This content was removed.'), findsOneWidget);
      },
    );
  });

  group('A8 — username validation rejects bad input before submit', () {
    testWidgets(
      'a too-short handle blocks submit and createProfile is never called',
      (tester) async {
        final repo = _FakeCommunityProfileRepository();
        await tester.pumpWidget(_editProfileHarness(repo));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextField, 'Handle'), 'ab');
        await tester.enterText(
          find.widgetWithText(TextField, 'Display name'),
          'Valid Name',
        );
        await tester.pumpAndSettle();

        final submitButton = find.byType(FilledButton);
        await tester.scrollUntilVisible(
          submitButton,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(
          repo.createCalls,
          0,
          reason: 'A8 violation: bad input reached the repository',
        );
        expect(
          find.text('Handle must be at least 3 characters.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a handle with illegal characters blocks submit', (
      tester,
    ) async {
      final repo = _FakeCommunityProfileRepository();
      await tester.pumpWidget(_editProfileHarness(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Handle'),
        'not a valid handle!!',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Display name'),
        'Valid Name',
      );
      await tester.pumpAndSettle();

      final submitButton = find.byType(FilledButton);
      await tester.scrollUntilVisible(
        submitButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(repo.createCalls, 0);
    });

    testWidgets('a valid handle submits and reaches the repository', (
      tester,
    ) async {
      final repo = _FakeCommunityProfileRepository();
      await tester.pumpWidget(_editProfileHarness(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Handle'),
        'wolfcasaba',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Display name'),
        'Wolf Casaba',
      );
      await tester.pumpAndSettle();

      final submitButton = find.byType(FilledButton);
      await tester.scrollUntilVisible(
        submitButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
    });
  });
}
