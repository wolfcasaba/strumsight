/// E13-R33 — post-composer audience + share-preview widget tests.
///
/// Covers the §6 / §6.1 acceptance cells the round's gate_tests groups under
/// this file:
///
/// * A2 — the default audience is NOT public (`CommunityAudience.followers`,
///   §0.0.B/B5), plus the full three-cell audience-threshold matrix: below
///   the threshold (fresh composer, no choice — `followers`), on the
///   threshold (the user explicitly picks `followers` — the choice applies
///   and is visible before submit), above the threshold (the user picks
///   `public` — a spelled-out irreversibility confirmation gates the
///   change, ADR 0291 §2).
/// * A3 — the practice-share editor lists exactly the five `SharePreview`
///   rows, and the label reflects the actual field value (not a hardcoded
///   string).
/// * A4 — structural abstinence: `SharePreview`'s five flags are false by
///   default, and the composer renders no raw-audio / waveform control —
///   there is no such field to render (§0.0.B/B7).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_comment.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/community_profile_repository.dart';
import 'package:strumsight/features/community/domain/repositories/post_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/edit_profile_screen.dart';
import 'package:strumsight/features/community/presentation/screens/post_composer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_auth.dart';

import '../../core/storage/in_memory_key_value_store.dart';

/// Minimal fake — the composer widget tests below never submit, so only
/// `createPost` needs a body; every other method is unused.
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

Map<String, Object?> _practiceSummaryArtifactJson() {
  return PracticeSummaryArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'sess-fixture-1',
    createdAt: DateTime.utc(2026, 8, 23, 12, 0, 0),
    activeSeconds: 60,
    pausedSeconds: 5,
    attemptCount: 1,
    finishReasonCode: 'userFinished',
    bestScore: 0.85,
    coachingCodes: const <String>['strongDownBeats'],
  ).toJson();
}

Widget _harness({Locale locale = const Locale('en')}) {
  return ProviderScope(
    overrides: [
      communityKeyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      communityLoggerProvider.overrideWithValue(const NoopAppLogger()),
      communityPostRepositoryProvider.overrideWithValue(
        _FakeCommunityPostRepository(),
      ),
      composerSourceArtifactProvider.overrideWithValue(
        _practiceSummaryArtifactJson(),
      ),
      authControllerProvider.overrideWith(
        () => _FakeAuthController(
          const AuthUser(id: 7, email: 'composer@strumsight.app'),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: const PostComposerScreen(),
    ),
  );
}

PostComposerState _state(WidgetTester tester) {
  final element = tester.element(find.byType(PostComposerScreen));
  return ProviderScope.containerOf(
    element,
  ).read(postComposerControllerProvider).value!;
}

void main() {
  group('A2 — default audience is not public', () {
    testWidgets('a fresh composer defaults to followers', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(_state(tester).audience, CommunityAudience.followers);
      // The chip rendered as selected must be "Követők" (followers), not
      // "Nyilvános" (public) — the default is visible, not just internal.
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Követők'),
      );
      expect(chip.selected, isTrue);
    });
  });

  group('§6.1 audience-threshold matrix', () {
    testWidgets('below threshold — no choice made, audience is followers', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();
      expect(_state(tester).audience, CommunityAudience.followers);
      expect(_state(tester).audience, isNot(CommunityAudience.public));
    });

    testWidgets(
      'on threshold — picking "Követők" applies immediately and is visible before submit',
      (tester) async {
        await tester.pumpWidget(_harness());
        await tester.pumpAndSettle();

        // Start from a different audience so the pick below is a real
        // transition, not a no-op against the default.
        final element = tester.element(find.byType(PostComposerScreen));
        final notifier = ProviderScope.containerOf(
          element,
        ).read(postComposerControllerProvider.notifier);
        await notifier.updateAudience(CommunityAudience.private);
        await tester.pumpAndSettle();
        expect(_state(tester).audience, CommunityAudience.private);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Követők'));
        await tester.pumpAndSettle();

        // No confirmation sheet for a non-public pick.
        expect(find.byKey(const Key('ss-confirmation-confirm')), findsNothing);
        // The choice applies immediately and is visible before any submit.
        expect(_state(tester).audience, CommunityAudience.followers);
        final chip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Követők'),
        );
        expect(chip.selected, isTrue);
      },
    );

    testWidgets(
      'above threshold — picking "Nyilvános" holds behind an irreversibility confirmation',
      (tester) async {
        await tester.pumpWidget(_harness());
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ChoiceChip, 'Nyilvános'));
        await tester.pumpAndSettle();

        // The pick does NOT apply yet — a spelled-out confirmation is
        // showing, and the audience is still the pre-pick value.
        expect(_state(tester).audience, CommunityAudience.followers);
        expect(
          find.byKey(const Key('ss-confirmation-confirm')),
          findsOneWidget,
        );
        final enLabels = lookupAppLocalizations(const Locale('en'));
        expect(find.text(enLabels.communityPublicConfirmTitle), findsOneWidget);
        expect(find.text(enLabels.communityPublicConfirmBody), findsOneWidget);

        await tester.tap(find.byKey(const Key('ss-confirmation-confirm')));
        await tester.pumpAndSettle();

        // Confirmed — the audience is now public.
        expect(_state(tester).audience, CommunityAudience.public);
      },
    );

    testWidgets(
      'above threshold — the confirmation caption comes from AppLocalizations, not a hardcoded string',
      (tester) async {
        // MAJOR-1 regression guard: the sheet used to render a Hungarian
        // constant regardless of locale. `en` and `hu` captions are
        // byte-different, so finding the `hu` caption under an `en` locale
        // (and vice-versa) is only possible if the screen still reads a
        // hardcoded string instead of `AppLocalizations.of(context)`.
        await tester.pumpWidget(_harness(locale: const Locale('hu')));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ChoiceChip, 'Nyilvános'));
        await tester.pumpAndSettle();

        final huLabels = lookupAppLocalizations(const Locale('hu'));
        final enLabels = lookupAppLocalizations(const Locale('en'));
        expect(find.text(huLabels.communityPublicConfirmTitle), findsOneWidget);
        expect(find.text(huLabels.communityPublicConfirmCta), findsOneWidget);
        expect(find.text(enLabels.communityPublicConfirmTitle), findsNothing);
      },
    );

    testWidgets(
      'above threshold — cancelling the confirmation leaves the audience unchanged',
      (tester) async {
        await tester.pumpWidget(_harness());
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ChoiceChip, 'Nyilvános'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ss-confirmation-cancel')));
        await tester.pumpAndSettle();

        expect(_state(tester).audience, CommunityAudience.followers);
      },
    );
  });

  group('A3 — the practice-share editor lists exactly the five fields', () {
    testWidgets('five SsSwitchRow toggles, all off by default', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.byType(SsSwitchRow), findsNWidgets(5));
      for (final label in <String>[
        'Akkord-idővonal',
        'Strumminta',
        'Tempó',
        'Aktív napok',
        'Legjobb pontszám',
      ]) {
        final row = tester.widget<SsSwitchRow>(
          find.widgetWithText(SsSwitchRow, label),
        );
        expect(row.value, isFalse, reason: '$label must start OFF');
      }

      // Flipping a toggle reflects the real field value, not a hardcoded
      // label — the row's `value` tracks the controller's SharePreview.
      final strumRow = find.widgetWithText(SsSwitchRow, 'Strumminta');
      await tester.scrollUntilVisible(
        strumRow,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(strumRow);
      await tester.pumpAndSettle();
      expect(_state(tester).sharePreview.includeStrumPattern, isTrue);
      expect(_state(tester).sharePreview.includeChordTimeline, isFalse);
      final flipped = tester.widget<SsSwitchRow>(
        find.widgetWithText(SsSwitchRow, 'Strumminta'),
      );
      expect(flipped.value, isTrue);
    });
  });

  group('A4 — raw audio is excluded by absence, not a toggle', () {
    testWidgets('SharePreview() default is all five flags false', (
      tester,
    ) async {
      const preview = SharePreview();
      expect(preview.includeChordTimeline, isFalse);
      expect(preview.includeStrumPattern, isFalse);
      expect(preview.includeTempo, isFalse);
      expect(preview.includeStreakDays, isFalse);
      expect(preview.includeBestScore, isFalse);
    });

    testWidgets('the composer renders no raw-audio / waveform control', (
      tester,
    ) async {
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      expect(find.textContaining('hang', findRichText: false), findsNothing);
      expect(
        find.textContaining('waveform', findRichText: false),
        findsNothing,
      );
      expect(find.textContaining('audio', findRichText: false), findsNothing);
      // Exactly five share-preview rows — a sixth (raw audio) row would
      // fail this count.
      expect(find.byType(SsSwitchRow), findsNWidgets(5));
    });
  });

  group('A2 — the profile-side default audience is also not public', () {
    testWidgets(
      'a fresh create-profile form defaults both radio groups to followers',
      (tester) async {
        final repo = _FakeCommunityProfileRepository();
        await tester.pumpWidget(
          ProviderScope(
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
              tokenStoreProvider.overrideWithValue(
                FakeTokenStore('test-token'),
              ),
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
          ),
        );
        await tester.pumpAndSettle();

        final visibilityGroup = tester.widget<RadioGroup<ProfileVisibility>>(
          find.byType(RadioGroup<ProfileVisibility>),
        );
        expect(visibilityGroup.groupValue, ProfileVisibility.followers);
        expect(visibilityGroup.groupValue, isNot(ProfileVisibility.public));

        final audienceGroup = tester.widget<RadioGroup<CommunityAudience>>(
          find.byType(RadioGroup<CommunityAudience>),
        );
        expect(audienceGroup.groupValue, CommunityAudience.followers);
        expect(audienceGroup.groupValue, isNot(CommunityAudience.public));
      },
    );
  });
}

class _FakeCommunityProfileRepository implements CommunityProfileRepository {
  @override
  Future<CommunityProfile?> fetchMyProfile() async => null;
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
  }) => throw UnsupportedError('not used in this test');
  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) => throw UnsupportedError('not used in this test');
}
