/// Club list → club detail navigation (production wiring round
/// 2026-09-15).
///
/// The list is the only in-app entry to ``ClubDetailScreen`` (the
/// router mounts ``/community/clubs`` on the list; the detail screen
/// has no route). The cell pins that tapping a row pushes the detail
/// screen for THAT club — the detail fetches the club by the id the
/// row handed over, so the repository sees exactly one ``fetchClub``
/// with the tapped id.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';

import 'package:strumsight/features/community/domain/entities/community_club.dart';
import 'package:strumsight/features/community/domain/repositories/club_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_detail_screen.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_list_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

class _RecordingClubRepository implements CommunityClubRepository {
  _RecordingClubRepository({required this.clubs});

  final List<CommunityClub> clubs;
  final List<ContentId> fetchCalls = <ContentId>[];

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async => CommunityPage<CommunityClub>(
    items: clubs,
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async {
    fetchCalls.add(clubId);
    return clubs.firstWhere((club) => club.id == clubId);
  }

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async => throw UnimplementedError('createClub is unused.');

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async => throw UnimplementedError('updateClub is unused.');

  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('requestJoin is unused.');

  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async => throw UnimplementedError('invite is unused.');

  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('leave is unused.');

  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('removeMember is unused.');

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async => throw UnimplementedError('transferOwnership is unused.');
}

CommunityClub _club({required String publicId, required String name}) {
  return CommunityClub(
    id: ContentId(publicId),
    name: name,
    description: 'description for $name',
    // Discoverable + non-member: the detail screen renders the join
    // prompt (name + CTA), which needs no tab providers — the cell
    // measures the navigation, not the tabbed surface.
    visibility: ClubVisibility.discoverable,
    tags: const <String>[],
    ownerId: PublicUserId('owner-1'),
    memberCount: 12,
    myRole: null,
    createdAt: DateTime.utc(2026, 8, 24),
  );
}

Widget _wrap(_RecordingClubRepository fake) {
  // A GoRouter, not a bare `MaterialApp`: the shipped list opens the detail
  // with `context.push(AppRoutes.communityClubDetail)` so the back button
  // returns to the list, and a `Navigator`-only harness would measure a
  // navigation the app does not perform.
  final router = GoRouter(
    initialLocation: AppRoutes.communityClubs,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.communityClubs,
        builder: (_, _) => const ClubListScreen(),
      ),
      GoRoute(
        path: AppRoutes.communityClubDetail,
        builder: (_, state) => ClubDetailScreen(
          clubId: ContentId(state.pathParameters['clubId']!),
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [communityClubRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en')],
    ),
  );
}

void main() {
  testWidgets('tapping a club row pushes ClubDetailScreen for that club', (
    tester,
  ) async {
    final fake = _RecordingClubRepository(
      clubs: <CommunityClub>[
        _club(publicId: 'club-1', name: 'Blues Lovers'),
        _club(publicId: 'club-2', name: 'Jazz Club'),
      ],
    );

    await tester.pumpWidget(_wrap(fake));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ClubDetailScreen), findsNothing);

    await tester.tap(find.text('Jazz Club'));
    await tester.pumpAndSettle();

    final detail = tester.widget<ClubDetailScreen>(
      find.byType(ClubDetailScreen),
    );
    expect(detail.clubId, ContentId('club-2'));
    // The detail fetched exactly the tapped club — nothing else.
    expect(fake.fetchCalls, <ContentId>[ContentId('club-2')]);
    // The list is underneath, the detail on top: one AppBar title of each.
    expect(find.text('Club'), findsOneWidget);
  });
}
