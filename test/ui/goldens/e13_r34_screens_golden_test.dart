// Golden snapshots of the E13-R34 community challenge / club / notification /
// safety screens at a compact portrait phone (412×915) and the same frame at
// textScaler 2.0, per the round brief §7/A9. Pattern follows the merged
// `test/ui/goldens/e13_r33_screens_golden_test.dart` precedent: `AppTheme`
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

import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/community/application/controllers/challenge_controller.dart'
    as challenge_controller;
import 'package:strumsight/features/community/application/controllers/notification_controller.dart';
import 'package:strumsight/features/community/data/repositories/challenge_repository_impl.dart'
    show communityChallengeRepositoryProvider;
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_challenge.dart';
import 'package:strumsight/features/community/domain/entities/community_club.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/entities/notification_item.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/challenge_repository.dart';
import 'package:strumsight/features/community/domain/repositories/club_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/notification_repository.dart';
import 'package:strumsight/features/community/domain/repositories/social_graph_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_detail_screen.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_list_screen.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_member_management_screen.dart';
import 'package:strumsight/features/community/presentation/screens/community_challenges_screen.dart';
import 'package:strumsight/features/community/presentation/screens/community_notifications_screen.dart';
import 'package:strumsight/features/community/presentation/screens/leaderboard_screen.dart';
import 'package:strumsight/features/community/presentation/screens/safety_relationships_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _compactPortrait = Size(412, 915);

// ---------------------------------------------------------------------------
// 1 — community_challenges_screen.dart (UI-59)
// ---------------------------------------------------------------------------

class _FakeChallengeRepository implements CommunityChallengeRepository {
  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async => CommunityPage<CommunityChallengeDefinition>(
    items: <CommunityChallengeDefinition>[
      CommunityChallengeDefinition(
        id: ContentId('golden-challenge-1'),
        version: 1,
        type: ChallengeType.personalBest,
        metric: 'score',
        difficulty: 2,
        startsAt: DateTime.utc(2026, 8, 20),
        endsAt: DateTime.utc(2026, 8, 27),
        authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5c01'),
        clubId: null,
      ),
      CommunityChallengeDefinition(
        id: ContentId('golden-challenge-2'),
        version: 1,
        type: ChallengeType.friends,
        metric: 'accuracy',
        difficulty: 1,
        startsAt: DateTime.utc(2026, 8, 22),
        endsAt: DateTime.utc(2026, 8, 29),
        authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5c02'),
        clubId: null,
      ),
    ],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async => null;

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async => throw UnimplementedError('golden fixture');
}

Widget _challengesScreen() => const CommunityChallengesScreen();
List<Override> _challengesOverrides() => [
  challenge_controller.communityChallengeRepositoryProvider.overrideWithValue(
    _FakeChallengeRepository(),
  ),
];

// ---------------------------------------------------------------------------
// 2 — leaderboard_screen.dart (UI-59)
// ---------------------------------------------------------------------------

class _FakeLeaderboardRepository implements CommunityChallengeRepository {
  @override
  Future<CommunityPage<CommunityChallengeDefinition>> listChallenges({
    required Object cursor,
    required int limit,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<CommunityChallengeDefinition> fetchDefinition({
    required ContentId challengeId,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<CommunityChallengeParticipantState?> fetchMyParticipation({
    required ContentId challengeId,
  }) async => null;

  @override
  Future<void> invite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> acceptInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> declineInvite({
    required ContentId challengeId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> cancelInvite({
    required ContentId challengeId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> submitResult({
    required ContentId challengeId,
    required int metricValue,
    required String sourceEventId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<CommunityPage<Object>> leaderboard({
    required ContentId challengeId,
    required Object cursor,
    required int limit,
  }) async => CommunityPage<LeaderboardEntry>(
    items: <LeaderboardEntry>[
      LeaderboardEntry(
        publicId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5d01'),
        rank: 1,
        displayName: 'Wolf Casaba',
        handle: '@wolfcasaba',
        metricValue: 980,
        submittedAt: DateTime.utc(2026, 8, 24),
        verifiedBadge: true,
      ),
      LeaderboardEntry(
        publicId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5d02'),
        rank: 2,
        displayName: 'Szita Kóto',
        handle: '@szitakoto',
        metricValue: 860,
        submittedAt: DateTime.utc(2026, 8, 23),
        verifiedBadge: true,
      ),
    ],
    cursor: const CursorPage.haltedAfterRequest(),
  );
}

Widget _leaderboardScreen() =>
    LeaderboardScreen(challengeId: ContentId('golden-challenge-1'));
List<Override> _leaderboardOverrides() => [
  communityChallengeRepositoryProvider.overrideWithValue(
    _FakeLeaderboardRepository(),
  ),
];

// ---------------------------------------------------------------------------
// 3 — clubs/club_list_screen.dart (UI-60)
// ---------------------------------------------------------------------------

class _FakeClubsRepository implements CommunityClubRepository {
  final CommunityClub seedClub = CommunityClub(
    id: ContentId('golden-club-1'),
    name: 'Blues Lovers',
    description: 'Weekly blues jam sessions and setlist sharing.',
    visibility: ClubVisibility.discoverable,
    tags: const <String>['blues', 'jam'],
    ownerId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5e01'),
    memberCount: 24,
    myRole: ClubRole.owner,
    createdAt: DateTime.utc(2026, 6, 1),
  );

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async => CommunityPage<CommunityClub>(
    items: <CommunityClub>[
      seedClub,
      CommunityClub(
        id: ContentId('golden-club-2'),
        name: 'Jazz Standards Circle',
        description: 'Practicing jazz standards together.',
        visibility: ClubVisibility.private,
        tags: const <String>[],
        ownerId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5e02'),
        memberCount: 8,
        myRole: ClubRole.member,
        createdAt: DateTime.utc(2026, 5, 12),
      ),
    ],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async =>
      seedClub;

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async {}
}

Widget _clubListScreen() => const ClubListScreen();
List<Override> _clubListOverrides() => [
  communityClubRepositoryProvider.overrideWithValue(_FakeClubsRepository()),
];

// ---------------------------------------------------------------------------
// 4 — clubs/club_detail_screen.dart (UI-60)
// ---------------------------------------------------------------------------

Widget _clubDetailScreen() =>
    ClubDetailScreen(clubId: ContentId('golden-club-1'));
List<Override> _clubDetailOverrides() {
  final fakeRepo = _FakeClubsRepository();
  return <Override>[
    communityClubRepositoryProvider.overrideWithValue(fakeRepo),
    clubFeedProvider.overrideWith(
      (ref, clubId) async => const CommunityPagePlaceholder<CommunityPost>(
        items: <CommunityPost>[],
      ),
    ),
    clubPinnedProvider.overrideWith(
      (ref, clubId) async => const <CommunityPost>[],
    ),
    clubChallengesProvider.overrideWith(
      (ref, clubId) async => <CommunityChallengeSummaryPlaceholder>[
        CommunityChallengeSummaryPlaceholder(
          challengePublicId: 'golden-club-challenge-1',
          metric: 'score',
          difficulty: 2,
          startsAt: DateTime.utc(2026, 8, 20),
          endsAt: DateTime.utc(2026, 8, 27),
        ),
      ],
    ),
  ];
}

// ---------------------------------------------------------------------------
// 5 — clubs/club_member_management_screen.dart (UI-60)
// ---------------------------------------------------------------------------

Widget _clubMemberManagementScreen() =>
    ClubMemberManagementScreen(clubId: ContentId('golden-club-1'));
List<Override> _clubMemberManagementOverrides() => [
  communityClubRepositoryProvider.overrideWithValue(_FakeClubsRepository()),
  clubMemberListProvider.overrideWith(
    (ref, clubId) async => <ClubMemberRow>[
      ClubMemberRow(
        memberPublicId: 'row-1',
        profilePublicId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f01'),
        role: ClubRole.owner,
        joinedAt: DateTime.utc(2026, 6, 1),
      ),
      ClubMemberRow(
        memberPublicId: 'row-2',
        profilePublicId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f02'),
        role: ClubRole.member,
        joinedAt: DateTime.utc(2026, 7, 3),
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// 6 — community_notifications_screen.dart (UI-61)
// ---------------------------------------------------------------------------

class _FakeNotificationRepository implements CommunityNotificationRepository {
  @override
  Future<CommunityPage<CommunityNotificationItem>> inboxPage({
    required Object cursor,
    required int limit,
  }) async => CommunityPage<CommunityNotificationItem>(
    items: <CommunityNotificationItem>[
      CommunityNotificationItem(
        id: ContentId('golden-notification-1'),
        kind: CommunityNotificationKind.challengeInvite,
        titleKey: 'communityNotificationChallengeInviteTitle',
        createdAt: DateTime.utc(2026, 8, 24, 9),
        isRead: false,
        relatedContentId: ContentId('golden-challenge-1'),
      ),
      CommunityNotificationItem(
        id: ContentId('golden-notification-2'),
        kind: CommunityNotificationKind.comment,
        titleKey: 'communityNotificationCommentTitle',
        bodyKey: 'communityNotificationCommentBody',
        createdAt: DateTime.utc(2026, 8, 23, 14),
        isRead: true,
      ),
    ],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<void> markRead({
    required ContentId notificationId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> markAllReadUpTo({
    required ContentId upToId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<Object> preferences() async => const <String, String>{};

  @override
  Future<void> updatePreference({
    required String category,
    required String level,
    required String idempotencyKey,
  }) async {}
}

Widget _notificationsScreen() => const CommunityNotificationsScreen();
List<Override> _notificationsOverrides() => [
  communityNotificationRepositoryProvider.overrideWithValue(
    _FakeNotificationRepository(),
  ),
];

// ---------------------------------------------------------------------------
// 7 — safety_relationships_screen.dart (UI-61)
// ---------------------------------------------------------------------------

CommunityProfile _goldenProfile(String suffix, String name) => CommunityProfile(
  userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5$suffix'),
  handle: CommunityHandle('handle-$suffix'),
  displayName: name,
  visibility: ProfileVisibility.public,
  avatarUrl: null,
  bio: null,
  skillInterests: const <String>[],
  badges: const <String>[],
  relationship: CommunityRelationshipToViewer.notRelated,
  createdAt: DateTime.utc(2026, 7, 1),
);

class _FakeSocialGraphRepository implements SocialGraphRepository {
  @override
  Future<CommunityPage<CommunityProfile>> blockedProfilesPage({
    required Object cursor,
  }) async => CommunityPage<CommunityProfile>(
    items: <CommunityProfile>[_goldenProfile('a01', 'Noisy Neighbour')],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityPage<CommunityProfile>> mutedProfilesPage({
    required Object cursor,
  }) async => CommunityPage<CommunityProfile>(
    items: <CommunityProfile>[_goldenProfile('a02', 'Quiet Muted User')],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<void> block({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> mute({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> unblock({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> unmute({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {}

  @override
  Future<CommunityPage<CommunityProfile>> followingPage({
    required PublicUserId userId,
    required Object cursor,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<CommunityPage<CommunityProfile>> followersPage({
    required PublicUserId userId,
    required Object cursor,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<ContentId> follow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<void> unfollow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<void> removeFollower({
    required PublicUserId follower,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<void> acceptFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');

  @override
  Future<void> declineFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('golden fixture');
}

Widget _safetyScreen() => const SafetyRelationshipsScreen();
List<Override> _safetyOverrides() => [
  socialGraphRepositoryProvider.overrideWithValue(_FakeSocialGraphRepository()),
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
    'challenges': (_challengesScreen, _challengesOverrides),
    'leaderboard': (_leaderboardScreen, _leaderboardOverrides),
    'club_list': (_clubListScreen, _clubListOverrides),
    'club_detail': (_clubDetailScreen, _clubDetailOverrides),
    'club_member_management': (
      _clubMemberManagementScreen,
      _clubMemberManagementOverrides,
    ),
    'notifications': (_notificationsScreen, _notificationsOverrides),
    'safety': (_safetyScreen, _safetyOverrides),
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
        await _expectGolden(tester, 'e13_r34_${entry.key}_$suffix');
      });
    }
  }
}
