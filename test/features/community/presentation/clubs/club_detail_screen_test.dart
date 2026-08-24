/// Widget tests for the club detail screen — E09-R25, ADR 0420,
/// brief §3 / §6 A2 / §6.1.
///
/// The test surface is the ``ProviderScope`` override of the
/// ``communityClubRepositoryProvider`` (the Kör 23 / Kör 21
/// pattern) plus the screen-local providers
/// (``clubFeedProvider`` / ``clubPinnedProvider`` /
/// ``clubChallengesProvider``) — the brief §0.0 #3 structural
/// precedent that the screen builds its own projections on
/// top of existing repositories, NOT new repository methods.
///
/// The brief's only Flutter-side acceptance cell is **A2** —
/// "Klub elhagyása után a cache-ből azonnal eltűnik a
/// csak-club tartalom". The test pins:
/// * the four-tab surface renders after the FutureProvider
///   resolves (Feed, Challenges, Members, About);
/// * the ``leave`` call invalidates the four providers
///   (detail + the three screen-local ones).
///
/// The test does NOT exercise the wire layer — the
/// ``communityClubRepositoryProvider`` is overridden with a
/// recording fake that just records the ``leave`` call and
/// returns a successful Future.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/features/community/domain/entities/community_club.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/repositories/club_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_detail_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Recording fake repository — captures calls and stubs the club.
// ---------------------------------------------------------------------------

class _RecordingClubRepository implements CommunityClubRepository {
  _RecordingClubRepository();

  final List<({ContentId clubId, String idempotencyKey})> leaveCalls =
      <({ContentId clubId, String idempotencyKey})>[];
  final List<({ContentId clubId, String idempotencyKey})> joinCalls =
      <({ContentId clubId, String idempotencyKey})>[];
  CommunityClub club;
  Object? failure;

  _RecordingClubRepository._(this.club);

  factory _RecordingClubRepository.build(CommunityClub seed) {
    return _RecordingClubRepository._(seed);
  }

  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    leaveCalls.add((clubId: clubId, idempotencyKey: idempotencyKey));
    if (failure != null) throw failure!;
  }

  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    joinCalls.add((clubId: clubId, idempotencyKey: idempotencyKey));
    if (failure != null) throw failure!;
  }

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async {
    return const CommunityPage<CommunityClub>(
      items: <CommunityClub>[],
      cursor: CursorPage.haltedAfterRequest(),
    );
  }

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async {
    if (failure != null) throw failure!;
    return club;
  }

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('createClub is unused.');
  }

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('updateClub is unused.');
  }

  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('invite is unused.');
  }

  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('removeMember is unused.');
  }

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('transferOwnership is unused.');
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CommunityClub _club({
  required String publicId,
  required String name,
  required ClubVisibility visibility,
  required int memberCount,
  ClubRole? myRole,
  String? ownerPublicId,
}) {
  return CommunityClub(
    id: ContentId(publicId),
    name: name,
    description: 'description for $name',
    visibility: visibility,
    tags: const <String>[],
    ownerId: PublicUserId(ownerPublicId ?? 'owner-1'),
    memberCount: memberCount,
    myRole: myRole,
    createdAt: DateTime.utc(2026, 8, 24),
  );
}

Widget _wrap(
  _RecordingClubRepository fake, {
  required List<Override> extraOverrides,
}) {
  return ProviderScope(
    overrides: <Override>[
      communityClubRepositoryProvider.overrideWithValue(fake),
      ...extraOverrides,
    ],
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en')],
      home: ClubDetailScreen(clubId: const ContentId('club-1')),
    ),
  );
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ClubDetailScreen (E09-R25 — 4 tabs + A2 cache invalidation)', () {
    testWidgets(
      'renders the four-tab surface (Feed / Challenges / Members / About)',
      (tester) async {
        final fake = _RecordingClubRepository.build(
          _club(
            publicId: 'club-1',
            name: 'Blues Lovers',
            visibility: ClubVisibility.discoverable,
            memberCount: 12,
            myRole: ClubRole.owner,
          ),
        );

        await tester.pumpWidget(
          _wrap(fake, extraOverrides: const <Override>[]),
        );
        await _pumpScreen(tester);

        // The four tabs land in the AppBar's TabBar.
        expect(find.text('Feed'), findsOneWidget);
        expect(find.text('Challenges'), findsOneWidget);
        expect(find.text('Members'), findsOneWidget);
        expect(find.text('About'), findsOneWidget);
      },
    );

    testWidgets('renders the leave-club action when the viewer is a member', (
      tester,
    ) async {
      final fake = _RecordingClubRepository.build(
        _club(
          publicId: 'club-1',
          name: 'Blues Lovers',
          visibility: ClubVisibility.discoverable,
          memberCount: 12,
          myRole: ClubRole.member,
        ),
      );

      await tester.pumpWidget(_wrap(fake, extraOverrides: const <Override>[]));
      await _pumpScreen(tester);

      expect(find.text('Leave club'), findsOneWidget);
    });

    testWidgets('A2 — leave call invalidates the screen-local providers '
        '(clubFeedProvider / clubPinnedProvider / clubChallengesProvider)', (
      tester,
    ) async {
      final fake = _RecordingClubRepository.build(
        _club(
          publicId: 'club-1',
          name: 'Blues Lovers',
          visibility: ClubVisibility.discoverable,
          memberCount: 12,
          myRole: ClubRole.member,
        ),
      );

      // Inject an "active" future for the three screen-local
      // providers — the leave flow must clear them. The test
      // records provider-state via a counter inside the
      // overrides: the counter increments every time the
      // provider is rebuilt (the Riverpod-invalidation seam).
      var detailRevisions = 0;
      var feedRevisions = 0;
      var pinnedRevisions = 0;
      var challengesRevisions = 0;

      final clubId = const ContentId('club-1');
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            communityClubRepositoryProvider.overrideWithValue(fake),
            clubDetailProvider(clubId).overrideWith((ref) {
              detailRevisions++;
              return _club(
                publicId: 'club-1',
                name: 'Blues Lovers',
                visibility: ClubVisibility.discoverable,
                memberCount: 12,
                myRole: ClubRole.member,
              );
            }),
            clubFeedProvider(clubId).overrideWith((ref) {
              feedRevisions++;
              return const CommunityPagePlaceholder<CommunityPost>(
                items: <CommunityPost>[],
              );
            }),
            clubPinnedProvider(clubId).overrideWith((ref) {
              pinnedRevisions++;
              return const <CommunityPost>[];
            }),
            clubChallengesProvider(clubId).overrideWith((ref) {
              challengesRevisions++;
              return const <CommunityChallengeSummaryPlaceholder>[];
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const <Locale>[Locale('en')],
            home: ClubDetailScreen(clubId: clubId),
          ),
        ),
      );
      await _pumpScreen(tester);

      // Sanity — the providers were called once at first paint.
      expect(detailRevisions, greaterThanOrEqualTo(1));
      expect(feedRevisions, greaterThanOrEqualTo(1));
      expect(pinnedRevisions, greaterThanOrEqualTo(1));
      expect(challengesRevisions, greaterThanOrEqualTo(1));

      // Tap the "Leave club" action — the cache-invalidation
      // path should invalidate the four providers.
      await tester.tap(find.text('Leave club'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.leaveCalls, isNotEmpty);
      // The §A2 invariant — every screen-local provider must
      // rebuild at least once more after the leave call. The
      // detail provider is also invalidated (Kör 24).
      expect(detailRevisions, greaterThan(1));
      expect(feedRevisions, greaterThan(1));
      expect(pinnedRevisions, greaterThan(1));
      expect(challengesRevisions, greaterThan(1));
    });
  });
}
