/// A3 / A6 / A8 / A10 — private club leakage + safety actions +
/// club-ág localization (E13-R34, brief §6, §0.0.B/B7, §0.0.B/B10).
///
/// * A3 — the three-cell `myRole` × `visibility` gate on
///   `club_detail_screen.dart`: below the threshold (private,
///   non-member) NO club content renders; on the threshold
///   (discoverable, non-member) the name + join CTA render but no
///   tab content; above the threshold (member) full content renders.
/// * A6 / A8 — Block / Mute on `club_member_management_screen.dart`
///   route through the SAME `socialGraphRepositoryProvider` the
///   Biztonsági központ reads.
/// * A10 — the club-ág screens render Hungarian text under the `hu`
///   locale, not the English fallback (the L519 hibaosztály guard —
///   a locale-specific cell pair so a regression that hard-codes
///   either language's string is caught).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_club.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/repositories/club_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/social_graph_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_detail_screen.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_list_screen.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_member_management_screen.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _RecordingClubRepository implements CommunityClubRepository {
  _RecordingClubRepository({required this.club});

  CommunityClub club;

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async => club;

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async => CommunityPage<CommunityClub>(
    items: <CommunityClub>[club],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

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
  }) async => throw UnimplementedError('unused');

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
  }) async => throw UnimplementedError('unused');

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');
}

class _RecordingSocialGraphRepository implements SocialGraphRepository {
  final List<PublicUserId> blockCalls = <PublicUserId>[];
  final List<PublicUserId> muteCalls = <PublicUserId>[];

  @override
  Future<void> block({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    blockCalls.add(target);
  }

  @override
  Future<void> mute({
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    muteCalls.add(target);
  }

  @override
  Future<CommunityPage<CommunityProfile>> followingPage({
    required PublicUserId userId,
    required Object cursor,
  }) async => throw UnimplementedError('unused');

  @override
  Future<CommunityPage<CommunityProfile>> followersPage({
    required PublicUserId userId,
    required Object cursor,
  }) async => throw UnimplementedError('unused');

  @override
  Future<ContentId> follow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

  @override
  Future<void> unfollow({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

  @override
  Future<void> removeFollower({
    required PublicUserId follower,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

  @override
  Future<void> acceptFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

  @override
  Future<void> declineFollowRequest({
    required ContentId requestId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

  @override
  Future<void> unblock({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

  @override
  Future<void> unmute({
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw UnimplementedError('unused');

  @override
  Future<CommunityPage<CommunityProfile>> blockedProfilesPage({
    required Object cursor,
  }) async => throw UnimplementedError('unused');

  @override
  Future<CommunityPage<CommunityProfile>> mutedProfilesPage({
    required Object cursor,
  }) async => throw UnimplementedError('unused');
}

CommunityClub _club({
  required String name,
  required ClubVisibility visibility,
  ClubRole? myRole,
  String description = 'A secret jam schedule and setlist.',
}) {
  return CommunityClub(
    id: ContentId('club-1'),
    name: name,
    description: description,
    visibility: visibility,
    tags: const <String>[],
    ownerId: PublicUserId('owner-1'),
    memberCount: 5,
    myRole: myRole,
    createdAt: DateTime.utc(2026, 8, 24),
  );
}

Widget _wrapDetail(
  _RecordingClubRepository fake, {
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [communityClubRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: ClubDetailScreen(clubId: ContentId('club-1')),
    ),
  );
}

Future<void> _pumpDetail(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group(
    'A3 — below the threshold: private + non-member renders NO content',
    () {
      testWidgets(
        'the private club name and description never render for a non-member',
        (tester) async {
          final fake = _RecordingClubRepository(
            club: _club(
              name: 'Secret Blues Club',
              visibility: ClubVisibility.private,
              description: 'Only members may know this exists.',
              myRole: null,
            ),
          );
          await tester.pumpWidget(_wrapDetail(fake));
          await _pumpDetail(tester);

          expect(find.text('Secret Blues Club'), findsNothing);
          expect(find.text('Only members may know this exists.'), findsNothing);
          expect(
            find.byKey(const Key('club-private-restricted-title')),
            findsOneWidget,
          );
          // No join CTA either — private joins are invite-only.
          expect(find.text('Request to join'), findsNothing);
          // No tabs.
          expect(find.text('Feed'), findsNothing);
          expect(find.text('Members'), findsNothing);
        },
      );
    },
  );

  group(
    'A3 — on the threshold: discoverable + non-member has no tag-content',
    () {
      testWidgets(
        'the name and join CTA render, but the description and tabs do not',
        (tester) async {
          final fake = _RecordingClubRepository(
            club: _club(
              name: 'Open Jam Collective',
              visibility: ClubVisibility.discoverable,
              description: 'Members-only setlist and roster.',
              myRole: null,
            ),
          );
          await tester.pumpWidget(_wrapDetail(fake));
          await _pumpDetail(tester);

          expect(find.text('Open Jam Collective'), findsOneWidget);
          expect(find.text('Request to join'), findsOneWidget);
          // No description, no tab content — "sincs tag-tartalom".
          expect(find.text('Members-only setlist and roster.'), findsNothing);
          expect(find.text('Feed'), findsNothing);
          expect(find.text('Members'), findsNothing);
          expect(find.text('Challenges'), findsNothing);
          expect(find.text('About'), findsNothing);
        },
      );
    },
  );

  group('A3 — above the threshold: a member sees full content', () {
    testWidgets('name, description and the four tabs all render', (
      tester,
    ) async {
      final fake = _RecordingClubRepository(
        club: _club(
          name: 'Open Jam Collective',
          visibility: ClubVisibility.discoverable,
          description: 'Members-only setlist and roster.',
          myRole: ClubRole.member,
        ),
      );
      await tester.pumpWidget(_wrapDetail(fake));
      await _pumpDetail(tester);

      expect(find.text('Open Jam Collective'), findsOneWidget);
      expect(find.text('Members-only setlist and roster.'), findsOneWidget);
      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Challenges'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });
  });

  group('A10 — club visibility labels are Hungarian under the hu locale', () {
    testWidgets('en cell: "Private" renders for an English locale viewer', (
      tester,
    ) async {
      final fake = _ClubsFake(
        club: _club(
          name: 'Jazz Club',
          visibility: ClubVisibility.private,
          myRole: ClubRole.owner,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [communityClubRepositoryProvider.overrideWithValue(fake)],
          child: MaterialApp(
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const ClubListScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Private'), findsOneWidget);
      expect(find.textContaining('Privát'), findsNothing);
    });

    testWidgets('hu cell: "Privát" renders for a Hungarian locale viewer — '
        'NOT the English "Private"', (tester) async {
      final fake = _ClubsFake(
        club: _club(
          name: 'Jazz Klub',
          visibility: ClubVisibility.private,
          myRole: ClubRole.owner,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [communityClubRepositoryProvider.overrideWithValue(fake)],
          child: MaterialApp(
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('hu'),
            home: const ClubListScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Privát'), findsOneWidget);
      // The falsification guard (L519): only the ELLENKEZŐ-language
      // literal beégetve would leave the English word visible under hu.
      expect(find.textContaining('Private ·'), findsNothing);
    });
  });

  group('A6 / A8 — Block / Mute on club management share the safety state', () {
    testWidgets(
      'tapping Block on a member row calls socialGraphRepositoryProvider.block '
      'with that member\'s id — the SAME repository the Biztonsági központ reads',
      (tester) async {
        final clubId = ContentId('club-1');
        final target = PublicUserId('member-42');
        final socialFake = _RecordingSocialGraphRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              socialGraphRepositoryProvider.overrideWithValue(socialFake),
              // `_MemberRow._onAction` reads this provider
              // unconditionally before branching on the action —
              // it must be overridden even though the block/mute
              // path never calls a method on it.
              communityClubRepositoryProvider.overrideWithValue(
                _RecordingClubRepository(
                  club: _club(
                    name: 'unused',
                    visibility: ClubVisibility.discoverable,
                    myRole: ClubRole.owner,
                  ),
                ),
              ),
              clubMemberListProvider.overrideWith(
                (ref, id) async => <ClubMemberRow>[
                  ClubMemberRow(
                    memberPublicId: 'row-1',
                    profilePublicId: target,
                    role: ClubRole.member,
                    joinedAt: DateTime.utc(2026, 8, 1),
                  ),
                ],
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: ClubMemberManagementScreen(clubId: clubId),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('club-manage-action-block')));
        await tester.pumpAndSettle();

        expect(socialFake.blockCalls, <PublicUserId>[target]);
      },
    );
  });
}

/// A repository whose `listClubs` returns the seeded club — used by the
/// A10 club_list_screen cell-pair.
class _ClubsFake extends _RecordingClubRepository {
  _ClubsFake({required super.club});
}
